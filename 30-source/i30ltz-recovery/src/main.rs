// I30LTZ Recovery console: PC and data recovery for a rescue boot.
// Enterprise layout: left navigation, drive/partition tables, guided recovery tools, local AI assistant (MAD AI).
// Rules: nothing is launched or changed without a click, and recovery tools are only ever opened in their own terminal
// where they ask before writing. Local first: no cloud, no network needed.
mod chat;
mod eval;
mod ui;

use chat::spawn_chat_thread;
use eval::{collect_all, human_size, smart_health, Drive, EvalData};
use raylib::prelude::*;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use ui::*;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const BUILD_DATE: &str = env!("BUILD_DATE");

const TOP_H: i32 = 56;
const NAV_W: i32 = 236;
const STATUS_H: i32 = 28;
const PAD: i32 = 24;

#[derive(PartialEq, Clone, Copy)]
enum Page {
    Overview,
    Drives,
    Recovery,
    System,
    Assistant,
}

const PAGES: [(Page, &str, &str); 5] = [
    (Page::Overview, "Overview", "RECOVERY"),
    (Page::Drives, "Drives & partitions", ""),
    (Page::Recovery, "Recovery tools", ""),
    (Page::System, "System & services", "SYSTEM"),
    (Page::Assistant, "MAD AI assistant", ""),
];

/// Things a click asks for. They run after the frame is drawn (the draw handle borrows the window).
enum Action {
    Goto(Page),
    Copy(String),
    Terminal(String),
    Gui(Vec<String>),
    Refresh,
}

struct Tools {
    smartctl: bool,
    testdisk: bool,
    photorec: bool,
    gparted: bool,
    ddrescue: bool,
}

struct State {
    page: Page,
    eval: EvalData,
    last_eval: f64,
    sel_drive: usize,
    sel_part: Option<usize>,
    smart: Arc<Mutex<HashMap<String, String>>>,
    smart_at: f64,
    tools: Tools,
    toast: Option<(String, f64)>,
    actions: Vec<Action>,
    chat_log: Vec<(bool, String)>, // (from the assistant, text)
    chat_input: String,
    chat_waiting: bool,
    chat_scroll: i32,
    req_tx: std::sync::mpsc::Sender<String>,
    resp_rx: std::sync::mpsc::Receiver<String>,
}

fn which(name: &str) -> bool {
    let path = std::env::var("PATH").unwrap_or_default();
    let found = path
        .split(':')
        .chain(["/usr/sbin", "/sbin", "/usr/local/sbin"])
        .any(|d| std::path::Path::new(d).join(name).is_file());
    found
}

fn start_smart_scan(map: &Arc<Mutex<HashMap<String, String>>>, drives: &[Drive]) {
    let names: Vec<String> = drives.iter().map(|d| d.name.clone()).collect();
    map.lock().unwrap().clear();
    let map = Arc::clone(map);
    std::thread::spawn(move || {
        for n in names {
            let h = smart_health(&n);
            map.lock().unwrap().insert(n, h);
        }
    });
}

fn safe_dev(name: &str) -> bool {
    !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

fn fs_check_cmd(dev: &str, fstype: &str) -> Option<String> {
    let c = match fstype {
        "ext2" | "ext3" | "ext4" => format!("sudo e2fsck -fn {dev}"),
        "ntfs" => format!("sudo ntfsfix -n {dev}"),
        "btrfs" => format!("sudo btrfs check --readonly {dev}"),
        "xfs" => format!("sudo xfs_repair -n {dev}"),
        "vfat" => format!("sudo fsck.vfat -n {dev}"),
        "exfat" => format!("sudo fsck.exfat -n {dev}"),
        _ => return None,
    };
    Some(c)
}

fn launch_terminal(cmd: &str) {
    let script = format!("{cmd}; echo; echo '[finished - press Enter to close]'; read _");
    let _ = std::process::Command::new("xterm")
        .args(["-fa", "Hack", "-fs", "11", "-bg", "#0D1217", "-fg", "#E4ECF3", "-T", "I30LTZ Recovery", "-e", "bash", "-lc", &script])
        .spawn();
}

fn main() {
    let (mut rl, thread) = raylib::init()
        .size(1440, 900)
        .title("I30LTZ Recovery  |  PC & Data Recovery Console")
        .resizable()
        .build();
    rl.set_target_fps(60);
    rl.set_window_min_size(1100, 700);
    load_fonts(&mut rl, &thread);

    // Brand banner (Dr. Boltz art). Missing file => the banner is simply not drawn.
    let banner: Option<Texture2D> = [
        "/opt/i30ltz/images/dr-boltz.jpg",
        concat!(env!("CARGO_MANIFEST_DIR"), "/../recovery-os-images/dr-boltz.jpg"),
    ]
    .iter()
    .find_map(|p| rl.load_texture(&thread, p).ok());

    let lucy_url = std::env::var("LUCY_URL").unwrap_or_else(|_| "http://127.0.0.1:5000".to_string());
    let auth_token = std::env::var("SWARM_AUTH_TOKEN")
        .or_else(|_| std::env::var("BOLTZ_AUTH_TOKEN"))
        .unwrap_or_default();
    let (req_tx, resp_rx) = spawn_chat_thread(lucy_url, auth_token);

    let eval = collect_all();
    let smart = Arc::new(Mutex::new(HashMap::new()));
    start_smart_scan(&smart, &eval.drives);

    // Dev aid: I30LTZ_START_PAGE=1..5 opens that page first (used to review the layout).
    let start_page = std::env::var("I30LTZ_START_PAGE")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .and_then(|n| PAGES.get(n.wrapping_sub(1)))
        .map(|p| p.0)
        .unwrap_or(Page::Overview);
    let mut st = State {
        page: start_page,
        eval,
        last_eval: 0.0,
        sel_drive: 0,
        sel_part: None,
        smart,
        smart_at: 0.0,
        tools: Tools {
            smartctl: which("smartctl"),
            testdisk: which("testdisk"),
            photorec: which("photorec"),
            gparted: which("gparted"),
            ddrescue: which("ddrescue"),
        },
        toast: None,
        actions: Vec::new(),
        chat_log: vec![(
            true,
            "I am Dr. I30LTZ (MAD AI), your recovery assistant. I run on this machine only. Describe the problem: a PC that will not boot, \
             a drive that disappeared, files you need back. I suggest steps; nothing runs unless you click it."
                .to_string(),
        )],
        chat_input: String::new(),
        chat_waiting: false,
        chat_scroll: 0,
        req_tx,
        resp_rx,
    };

    // Dev aid: I30LTZ_SHOT=/path/file.png saves the app's own framebuffer after a moment and exits (layout review).
    let shot_path = std::env::var("I30LTZ_SHOT").ok();
    let mut frame_no = 0u32;
    while !rl.window_should_close() {
        frame_no += 1;
        if let Some(p) = &shot_path {
            if frame_no == 45 {
                rl.take_screenshot(&thread, p);
                break;
            }
        }
        let t = rl.get_time();
        let (w, h) = (rl.get_screen_width(), rl.get_screen_height());
        let inp = Input {
            mx: rl.get_mouse_x(),
            my: rl.get_mouse_y(),
            clicked: rl.is_mouse_button_pressed(MouseButton::MOUSE_BUTTON_LEFT),
        };

        // Keyboard: page hotkeys everywhere except in the assistant, where typing must not switch pages.
        if st.page == Page::Assistant {
            if rl.is_key_pressed(KeyboardKey::KEY_ESCAPE) {
                st.page = Page::Overview;
            }
            while let Some(c) = rl.get_char_pressed() {
                if c >= ' ' && c != '\u{7f}' {
                    st.chat_input.push(c);
                }
            }
            if rl.is_key_pressed(KeyboardKey::KEY_BACKSPACE) || rl.is_key_pressed_repeat(KeyboardKey::KEY_BACKSPACE) {
                st.chat_input.pop();
            }
            if rl.is_key_pressed(KeyboardKey::KEY_ENTER) && !st.chat_waiting {
                let msg = st.chat_input.trim().to_string();
                if !msg.is_empty() {
                    st.chat_log.push((false, msg.clone()));
                    st.req_tx.send(msg).ok();
                    st.chat_input.clear();
                    st.chat_waiting = true;
                    st.chat_scroll = 0;
                }
            }
            let wheel = rl.get_mouse_wheel_move();
            st.chat_scroll = (st.chat_scroll + (wheel * 40.0) as i32).max(0);
        } else {
            for (i, key) in [KeyboardKey::KEY_ONE, KeyboardKey::KEY_TWO, KeyboardKey::KEY_THREE, KeyboardKey::KEY_FOUR, KeyboardKey::KEY_FIVE]
                .iter()
                .enumerate()
            {
                if rl.is_key_pressed(*key) {
                    st.page = PAGES[i].0;
                }
            }
            if rl.is_key_pressed(KeyboardKey::KEY_TAB) {
                let i = PAGES.iter().position(|p| p.0 == st.page).unwrap_or(0);
                st.page = PAGES[(i + 1) % PAGES.len()].0;
            }
            if rl.is_key_pressed(KeyboardKey::KEY_F5) {
                st.actions.push(Action::Refresh);
            }
        }

        if let Ok(resp) = st.resp_rx.try_recv() {
            st.chat_log.push((true, resp));
            st.chat_waiting = false;
        }
        if t - st.last_eval > 5.0 {
            st.eval = collect_all();
            st.last_eval = t;
            if st.sel_drive >= st.eval.drives.len() {
                st.sel_drive = 0;
                st.sel_part = None;
            }
        }
        if t - st.smart_at > 120.0 {
            start_smart_scan(&st.smart, &st.eval.drives);
            st.smart_at = t;
        }

        {
            let mut d = rl.begin_drawing(&thread);
            d.clear_background(BG);
            let (cx, cy, cw, ch) = (NAV_W, TOP_H, w - NAV_W, h - TOP_H - STATUS_H);
            match st.page {
                Page::Overview => page_overview(&mut d, &inp, &mut st, cx, cy, cw, ch),
                Page::Drives => page_drives(&mut d, &inp, &mut st, cx, cy, cw, ch),
                Page::Recovery => page_recovery(&mut d, &inp, &mut st, cx, cy, cw, ch),
                Page::System => page_system(&mut d, &mut st, cx, cy, cw, ch),
                Page::Assistant => page_assistant(&mut d, &mut st, cx, cy, cw, ch, t as f32),
            }
            draw_nav(&mut d, &inp, &mut st, h, banner.as_ref());
            draw_topbar(&mut d, &st, w, t);
            draw_statusbar(&mut d, &st, w, h);
            draw_toast(&mut d, &st, w, h, t);
        }

        // Run what was clicked this frame.
        for a in std::mem::take(&mut st.actions) {
            match a {
                Action::Goto(p) => st.page = p,
                Action::Copy(s) => {
                    rl.set_clipboard_text(&s).ok();
                    st.toast = Some(("Command copied to the clipboard".into(), t));
                }
                Action::Terminal(c) => {
                    launch_terminal(&c);
                    st.toast = Some(("Opened in a terminal window".into(), t));
                }
                Action::Gui(args) => {
                    let _ = std::process::Command::new(&args[0]).args(&args[1..]).spawn();
                    st.toast = Some(("Starting...".into(), t));
                }
                Action::Refresh => {
                    st.eval = collect_all();
                    st.last_eval = t;
                    start_smart_scan(&st.smart, &st.eval.drives);
                    st.smart_at = t;
                    st.toast = Some(("Refreshed".into(), t));
                }
            }
        }
    }
    drop(banner);
    unload_fonts();
}

// ── Chrome: top bar, navigation, status bar, toast ───────────────────────────
fn draw_topbar(d: &mut impl RaylibDraw, st: &State, w: i32, t: f64) {
    d.draw_rectangle(0, 0, w, TOP_H, SURFACE);
    d.draw_rectangle(0, TOP_H - 1, w, 1, BORDER);
    logo(d, 34, TOP_H / 2, 1.0);
    txt(d, Face::Bold, "I30LTZ Recovery", 62, 10, 22, TEXT);
    txt(d, Face::Reg, "PC & Data Recovery Console", 62, 33, 13, MUTED);

    let ai = if st.eval.ollama_up { ("AI engine online", OK) } else { ("AI engine offline", WARN) };
    let pw = text_w(Face::Bold, ai.0, 12) + 22;
    pill(d, w - pw - 20, 17, ai.0, ai.1);
    let host = format!("Host  {}", st.eval.hostname);
    let hw = text_w(Face::Reg, &host, 14);
    txt(d, Face::Reg, &host, w - pw - 20 - hw - 24, 19, 14, MUTED);
    let _ = t;
}

fn draw_nav(d: &mut impl RaylibDraw, inp: &Input, st: &mut State, h: i32, banner: Option<&Texture2D>) {
    d.draw_rectangle(0, TOP_H, NAV_W, h - TOP_H, SURFACE);
    d.draw_rectangle(NAV_W - 1, TOP_H, 1, h - TOP_H, BORDER);
    let mut y = TOP_H + 18;
    for (i, (page, label, section)) in PAGES.iter().enumerate() {
        if !section.is_empty() {
            if i > 0 {
                y += 10;
            }
            txt(d, Face::Bold, section, 20, y, 11, FAINT);
            y += 22;
        }
        let (x, iw, ih) = (10, NAV_W - 20, 38);
        let active = st.page == *page;
        let hover = inp.over(x, y, iw, ih);
        if active {
            rbox(d, x, y, iw, ih, 6.0, SURFACE2);
            rbox(d, x, y + 8, 3, ih - 16, 1.5, ACCENT);
        } else if hover {
            rbox(d, x, y, iw, ih, 6.0, alpha(SURFACE2, 150));
        }
        txt(d, Face::Bold, &format!("{}", i + 1), x + 16, y + 11, 13, if active { ACCENT } else { FAINT });
        txt(d, if active { Face::Bold } else { Face::Reg }, label, x + 40, y + 10, 15, if active { TEXT } else { MUTED });
        if inp.click_in(x, y, iw, ih) {
            st.actions.push(Action::Goto(*page));
        }
        y += ih + 2;
    }

    // Brand banner + version at the bottom
    let by = h - STATUS_H - 150;
    if let Some(tex) = banner {
        let (bw, bh) = (NAV_W - 32, 96);
        let (tw, th) = (tex.width as f32, tex.height as f32);
        let k = (bw as f32 / tw).max(bh as f32 / th);
        let (sw, sh) = (bw as f32 / k, bh as f32 / k);
        rbox(d, 15, by - 1, bw + 2, bh + 2, 6.0, BORDER);
        d.draw_texture_pro(
            tex,
            Rectangle::new((tw - sw) / 2.0, (th - sh) / 2.0, sw, sh),
            Rectangle::new(16.0, by as f32, bw as f32, bh as f32),
            Vector2::zero(),
            0.0,
            Color::WHITE,
        );
    }
    txt(d, Face::Reg, &format!("Version {VERSION}  -  {BUILD_DATE}"), 20, by + 106, 12, FAINT);
    txt(d, Face::Reg, "F5 refresh   Tab next page", 20, by + 124, 12, FAINT);
}

fn draw_statusbar(d: &mut impl RaylibDraw, st: &State, w: i32, h: i32) {
    d.draw_rectangle(0, h - STATUS_H, w, STATUS_H, SURFACE);
    d.draw_rectangle(0, h - STATUS_H, w, 1, BORDER);
    let sel = match st.eval.drives.get(st.sel_drive) {
        Some(dr) => {
            let part = st.sel_part.and_then(|i| dr.parts.get(i)).map(|p| format!("  >  /dev/{}", p.name)).unwrap_or_default();
            format!("Selected: /dev/{}  ({}, {}){}", dr.name, if dr.model.is_empty() { "unknown model" } else { &dr.model }, human_size(dr.size), part)
        }
        None => "No drive detected".to_string(),
    };
    txt(d, Face::Reg, &sel, 20, h - STATUS_H + 7, 13, MUTED);
    let r = format!("{} drives  -  {} failed services", st.eval.drives.len(), st.eval.failed_units.len());
    txt(d, Face::Reg, &r, w - text_w(Face::Reg, &r, 13) - 20, h - STATUS_H + 7, 13, MUTED);
}

fn draw_toast(d: &mut impl RaylibDraw, st: &State, w: i32, h: i32, t: f64) {
    if let Some((msg, at)) = &st.toast {
        if t - at < 2.2 {
            let tw = text_w(Face::Bold, msg, 14) + 32;
            panel(d, w - tw - 24, h - STATUS_H - 54, tw, 38, SURFACE3, ACCENT_DK);
            txt(d, Face::Bold, msg, w - tw - 8, h - STATUS_H - 44, 14, TEXT);
        }
    }
}

fn page_title(d: &mut impl RaylibDraw, x: i32, y: i32, title: &str, sub: &str) {
    txt(d, Face::Bold, title, x, y, 26, TEXT);
    txt(d, Face::Reg, sub, x, y + 34, 14, MUTED);
}

// ── Overview ─────────────────────────────────────────────────────────────────
fn smart_of(st: &State, name: &str) -> String {
    st.smart.lock().unwrap().get(name).cloned().unwrap_or_else(|| "checking".into())
}

fn smart_color(s: &str) -> Color {
    match s {
        "PASSED" => OK,
        "FAILED" => ERR,
        "checking" => INFO,
        _ => FAINT,
    }
}

fn page_overview(d: &mut impl RaylibDraw, inp: &Input, st: &mut State, x: i32, y: i32, w: i32, _h: i32) {
    let (x0, mut cy) = (x + PAD, y + PAD);
    let cw = w - PAD * 2;
    page_title(d, x0, cy, "Overview", "State of this machine and the drives attached to it");
    cy += 76;

    // KPI cards
    let ev = &st.eval;
    let gap = 16;
    let kw = (cw - gap * 3) / 4;
    let total: u64 = ev.drives.iter().map(|dr| dr.size).sum();
    // 1 Drives
    card(d, x0, cy, kw, 104, None);
    txt(d, Face::Reg, "Drives detected", x0 + 16, cy + 14, 13, MUTED);
    txt(d, Face::Bold, &ev.drives.len().to_string(), x0 + 16, cy + 34, 32, TEXT);
    txt(d, Face::Reg, &format!("{} total capacity", human_size(total)), x0 + 16, cy + 76, 13, MUTED);
    // 2 Memory
    let x1 = x0 + kw + gap;
    card(d, x1, cy, kw, 104, None);
    txt(d, Face::Reg, "Memory in use", x1 + 16, cy + 14, 13, MUTED);
    txt(d, Face::Bold, &format!("{}%", ev.ram_used_pct), x1 + 16, cy + 34, 32, pct_color(ev.ram_used_pct));
    bar(d, x1 + 16, cy + 80, kw - 32, 8, ev.ram_used_pct, pct_color(ev.ram_used_pct));
    // 3 Load
    let x2 = x1 + kw + gap;
    let load_pct = ((ev.load_1 / ev.cpu_count.max(1) as f32) * 100.0).min(100.0) as u8;
    card(d, x2, cy, kw, 104, None);
    txt(d, Face::Reg, "CPU load (1 min)", x2 + 16, cy + 14, 13, MUTED);
    txt(d, Face::Bold, &format!("{:.2}", ev.load_1), x2 + 16, cy + 34, 32, pct_color(load_pct));
    txt(d, Face::Reg, &format!("{} cores  -  {}", ev.cpu_count, ev.cpu_temp), x2 + 16, cy + 76, 13, MUTED);
    // 4 AI engine
    let x3 = x2 + kw + gap;
    card(d, x3, cy, kw, 104, None);
    txt(d, Face::Reg, "MAD AI engine", x3 + 16, cy + 14, 13, MUTED);
    let (lbl, col) = if ev.ollama_up { ("Online", OK) } else { ("Offline", WARN) };
    txt(d, Face::Bold, lbl, x3 + 16, cy + 34, 32, col);
    txt(d, Face::Reg, if ev.ollama_up { "Local model, no cloud" } else { "Start it:  ollama serve" }, x3 + 16, cy + 76, 13, MUTED);
    cy += 104 + gap;

    // Attention list + workflow
    let lw = cw * 6 / 10;
    let mut issues: Vec<(Color, String)> = Vec::new();
    for u in &ev.failed_units {
        issues.push((ERR, format!("Service failed: {u}")));
    }
    for dr in &ev.drives {
        let s = smart_of(st, &dr.name);
        if s == "FAILED" {
            issues.push((ERR, format!("/dev/{}: SMART health check FAILED. Image this drive first (ddrescue).", dr.name)));
        }
    }
    for m in &ev.mounts {
        if m.pct >= 90 {
            issues.push((WARN, format!("{} is {}% full", m.target, m.pct)));
        }
    }
    if !ev.ollama_up {
        issues.push((WARN, "MAD AI engine is offline (ollama is not running)".into()));
    }
    let ah = 238;
    let top = card(d, x0, cy, lw, ah, Some("Needs attention"));
    if issues.is_empty() {
        d.draw_circle(x0 + 24, top + 10, 5.0, OK);
        txt(d, Face::Reg, "No issues detected on this machine.", x0 + 40, top + 2, 15, TEXT);
    }
    for (i, (c, m)) in issues.iter().take(6).enumerate() {
        let yy = top + i as i32 * 30;
        d.draw_circle(x0 + 24, yy + 10, 5.0, *c);
        txt(d, Face::Reg, &fit(Face::Reg, m, 15, lw - 64), x0 + 40, yy + 2, 15, TEXT);
    }
    let rx = x0 + lw + gap;
    let rw = cw - lw - gap;
    let top = card(d, rx, cy, rw, ah, Some("Recovery workflow"));
    for (i, s) in ["Check drive health (SMART)", "Image a failing drive first", "Repair filesystem or boot", "Recover files"].iter().enumerate() {
        let yy = top + i as i32 * 28;
        rbox(d, rx + 16, yy, 22, 22, 11.0, ACCENT_DK);
        txt(d, Face::Bold, &(i + 1).to_string(), rx + 23, yy + 3, 13, ACCENT);
        txt(d, Face::Reg, s, rx + 48, yy + 3, 15, TEXT);
    }
    if button(d, inp, rx + 16, cy + ah - 52, rw - 32, 36, "Open recovery tools", Kind::Primary, true) {
        st.actions.push(Action::Goto(Page::Recovery));
    }
    cy += ah + gap;

    // Drives summary
    let n = st.eval.drives.len().min(4) as i32;
    let sh = 50 + 30 + n.max(1) * 34 + 10;
    let top = card(d, x0, cy, cw, sh, Some("Drives"));
    drive_table_header(d, x0, top, cw);
    drive_rows(d, inp, st, x0, top + 28, cw, 4, false);
}

fn drive_table_header(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32) {
    for (off, label) in drive_cols(w) {
        txt(d, Face::Bold, label, x + 16 + off, y + 2, 12, FAINT);
    }
    d.draw_rectangle(x + 1, y + 24, w - 2, 1, BORDER);
}

fn drive_cols(w: i32) -> [(i32, &'static str); 7] {
    let f = |p: f32| (w as f32 * p) as i32;
    [(0, "DEVICE"), (f(0.10), "MODEL"), (f(0.34), "INTERFACE"), (f(0.46), "TYPE"), (f(0.58), "CAPACITY"), (f(0.72), "PARTITIONS"), (f(0.84), "HEALTH")]
}

/// Rows of the drive table; clicking a row selects it (and jumps to Drives when `jump`).
fn drive_rows(d: &mut impl RaylibDraw, inp: &Input, st: &mut State, x: i32, y: i32, w: i32, max: usize, jump: bool) -> i32 {
    let cols = drive_cols(w);
    if st.eval.drives.is_empty() {
        txt(d, Face::Reg, "No drives detected. Check cables, or run a rescan with F5.", x + 16, y + 8, 14, MUTED);
        return 34;
    }
    let drives = st.eval.drives.clone();
    for (i, dr) in drives.iter().take(max).enumerate() {
        let ry = y + i as i32 * 34;
        let selected = i == st.sel_drive;
        if selected {
            d.draw_rectangle(x + 1, ry, w - 2, 34, alpha(ACCENT_DK, 120));
            d.draw_rectangle(x + 1, ry, 3, 34, ACCENT);
        } else if inp.over(x, ry, w, 34) {
            d.draw_rectangle(x + 1, ry, w - 2, 34, alpha(SURFACE2, 200));
        }
        let ty = ry + 8;
        let cx = |k: usize| x + 16 + cols[k].0;
        txt(d, Face::Mono, &format!("/dev/{}", dr.name), cx(0), ty + 1, 13, TEXT);
        txt(d, Face::Reg, &fit(Face::Reg, if dr.model.is_empty() { "-" } else { &dr.model }, 14, cols[2].0 - cols[1].0 - 12), cx(1), ty, 14, TEXT);
        txt(d, Face::Reg, &if dr.tran.is_empty() { "-".to_string() } else { dr.tran.to_uppercase() }, cx(2), ty, 14, MUTED);
        txt(d, Face::Reg, dr.kind(), cx(3), ty, 14, MUTED);
        txt(d, Face::Reg, &human_size(dr.size), cx(4), ty, 14, TEXT);
        txt(d, Face::Reg, &dr.parts.len().to_string(), cx(5), ty, 14, MUTED);
        let s = smart_of(st, &dr.name);
        let label = match s.as_str() {
            "PASSED" => "Healthy",
            "FAILED" => "FAILING",
            "checking" => "Checking",
            _ => "No SMART data",
        };
        pill(d, cx(6) - 4, ry + 6, label, smart_color(&s));
        if inp.click_in(x, ry, w, 34) {
            st.sel_drive = i;
            st.sel_part = None;
            if jump {
                st.actions.push(Action::Goto(Page::Drives));
            }
        }
    }
    34 * drives.len().min(max) as i32
}

// ── Drives & partitions ────────────────────────────────────────────────────────
fn page_drives(d: &mut impl RaylibDraw, inp: &Input, st: &mut State, x: i32, y: i32, w: i32, _h: i32) {
    let (x0, mut cy) = (x + PAD, y + PAD);
    let cw = w - PAD * 2;
    page_title(d, x0, cy, "Drives & partitions", "Select a drive, then a partition, to use it in the recovery tools");
    if button(d, inp, x0 + cw - 120, cy + 4, 120, 34, "Rescan (F5)", Kind::Secondary, true) {
        st.actions.push(Action::Refresh);
    }
    cy += 76;

    let n = st.eval.drives.len() as i32;
    let dh = 50 + 30 + n.max(1) * 34 + 10;
    let top = card(d, x0, cy, cw, dh, Some("Physical drives"));
    drive_table_header(d, x0, top, cw);
    drive_rows(d, inp, st, x0, top + 28, cw, 12, false);
    cy += dh + 16;

    let Some(dr) = st.eval.drives.get(st.sel_drive).cloned() else { return };
    let rows = dr.parts.len().max(1) as i32;
    let ph = 50 + 30 + rows * 34 + 52;
    let top = card(d, x0, cy, cw, ph, Some(&format!("Partitions on /dev/{}", dr.name)));
    let f = |p: f32| (cw as f32 * p) as i32;
    let cols = [(0, "PARTITION"), (f(0.14), "FILESYSTEM"), (f(0.28), "LABEL"), (f(0.46), "CAPACITY"), (f(0.58), "USED"), (f(0.78), "MOUNT POINT")];
    for (off, label) in cols {
        txt(d, Face::Bold, label, x0 + 16 + off, top + 2, 12, FAINT);
    }
    d.draw_rectangle(x0 + 1, top + 24, cw - 2, 1, BORDER);
    if dr.parts.is_empty() {
        txt(d, Face::Reg, "No partitions (empty or unreadable partition table). TestDisk can look for lost partitions.", x0 + 16, top + 36, 14, MUTED);
    }
    for (i, p) in dr.parts.iter().enumerate() {
        let ry = top + 28 + i as i32 * 34;
        let selected = st.sel_part == Some(i);
        if selected {
            d.draw_rectangle(x0 + 1, ry, cw - 2, 34, alpha(ACCENT_DK, 120));
            d.draw_rectangle(x0 + 1, ry, 3, 34, ACCENT);
        } else if inp.over(x0, ry, cw, 34) {
            d.draw_rectangle(x0 + 1, ry, cw - 2, 34, alpha(SURFACE2, 200));
        }
        let ty = ry + 8;
        let cx = |k: usize| x0 + 16 + cols[k].0;
        txt(d, Face::Mono, &format!("/dev/{}", p.name), cx(0), ty + 1, 13, TEXT);
        txt(d, Face::Reg, if p.fstype.is_empty() { "-" } else { &p.fstype }, cx(1), ty, 14, MUTED);
        txt(d, Face::Reg, &fit(Face::Reg, if p.label.is_empty() { "-" } else { &p.label }, 14, f(0.16)), cx(2), ty, 14, TEXT);
        txt(d, Face::Reg, &human_size(p.size), cx(3), ty, 14, TEXT);
        let used = st.eval.mounts.iter().find(|m| m.source == format!("/dev/{}", p.name)).map(|m| m.pct);
        match used {
            Some(pc) => {
                bar(d, cx(4), ty + 5, f(0.10), 8, pc, pct_color(pc));
                txt(d, Face::Reg, &format!("{pc}%"), cx(4) + f(0.10) + 10, ty, 13, MUTED);
            }
            None => txt(d, Face::Reg, "not mounted", cx(4), ty, 13, FAINT),
        }
        txt(d, Face::Mono, &fit(Face::Mono, if p.mountpoint.is_empty() { "-" } else { &p.mountpoint }, 13, cw - cols[5].0 - 40), cx(5), ty + 1, 13, MUTED);
        if inp.click_in(x0, ry, cw, 34) {
            st.sel_part = Some(i);
        }
    }
    let by = top + 28 + rows * 34 + 8;
    txt(d, Face::Reg, &format!("Serial {}   -   {}", if dr.serial.is_empty() { "unknown" } else { &dr.serial }, if dr.read_only { "read-only device" } else { "read/write device" }), x0 + 16, by + 10, 13, MUTED);
    if button(d, inp, x0 + cw - 226, by, 210, 34, "Use in recovery tools", Kind::Primary, true) {
        st.actions.push(Action::Goto(Page::Recovery));
    }
}

// ── Recovery tools ───────────────────────────────────────────────────────────
fn page_recovery(d: &mut impl RaylibDraw, inp: &Input, st: &mut State, x: i32, y: i32, w: i32, _h: i32) {
    let (x0, mut cy) = (x + PAD, y + PAD);
    let cw = w - PAD * 2;
    page_title(d, x0, cy, "Recovery tools", "Guided tools for the selected drive. Each opens in its own window; nothing starts until you click.");
    cy += 76;

    let dr = st.eval.drives.get(st.sel_drive).cloned();
    // Target bar
    panel(d, x0, cy, cw, 54, SURFACE, BORDER);
    match &dr {
        Some(dr) => {
            txt(d, Face::Reg, "Target", x0 + 16, cy + 9, 12, FAINT);
            let part = st.sel_part.and_then(|i| dr.parts.get(i));
            let t = match part {
                Some(p) => format!("/dev/{}  >  /dev/{}  ({})", dr.name, p.name, if p.fstype.is_empty() { "unknown filesystem" } else { &p.fstype }),
                None => format!("/dev/{}  ({}, {})", dr.name, if dr.model.is_empty() { "unknown model" } else { &dr.model }, human_size(dr.size)),
            };
            txt(d, Face::Mono, &t, x0 + 16, cy + 28, 14, TEXT);
            if button(d, inp, x0 + cw - 146, cy + 10, 130, 34, "Change target", Kind::Secondary, true) {
                st.actions.push(Action::Goto(Page::Drives));
            }
        }
        None => {
            txt(d, Face::Reg, "No drive detected. Attach the drive and press F5.", x0 + 16, cy + 18, 15, WARN);
        }
    }
    cy += 54 + 16;

    let Some(dr) = dr else { return };
    let dev = format!("/dev/{}", dr.name);
    let part_dev = st.sel_part.and_then(|i| dr.parts.get(i)).map(|p| (format!("/dev/{}", p.name), p.fstype.clone()));
    let ok_dev = safe_dev(&dr.name);
    let tools = &st.tools;

    struct Card<'a> {
        title: &'a str,
        desc: &'a str,
        cmd: String,
        label: &'a str,
        enabled: bool,
        why_not: &'a str,
        action: Option<Action>,
    }
    let fs_cmd = part_dev.as_ref().and_then(|(p, f)| fs_check_cmd(p, f));
    let cards = vec![
        Card {
            title: "1  Check drive health",
            desc: "Full SMART report: reallocated sectors, pending sectors, temperature, error log. Read-only.",
            cmd: format!("sudo smartctl -a {dev} | less"),
            label: "Open SMART report",
            enabled: tools.smartctl && ok_dev,
            why_not: "smartctl is not installed",
            action: Some(Action::Terminal(format!("sudo smartctl -a {dev} | less"))),
        },
        Card {
            title: "2  Image a failing drive",
            desc: "Copy it sector by sector to a file on a healthy drive, then recover from the copy. Do this first when SMART shows errors.",
            cmd: format!("sudo ddrescue -f -n {dev} /path/to/backup/{}.img /path/to/backup/{}.map", dr.name, dr.name),
            label: "Copy command",
            enabled: tools.ddrescue,
            why_not: "ddrescue is not installed",
            action: Some(Action::Copy(format!("sudo ddrescue -f -n {dev} /path/to/backup/{}.img /path/to/backup/{}.map", dr.name, dr.name))),
        },
        Card {
            title: "3  Check filesystem (read-only)",
            desc: "Reports filesystem damage without changing anything. Select a partition on the Drives page first.",
            cmd: fs_cmd.clone().unwrap_or_else(|| "select a partition with a known filesystem".into()),
            label: "Run read-only check",
            enabled: fs_cmd.is_some() && part_dev.as_ref().map(|(p, _)| safe_dev(p.trim_start_matches("/dev/"))).unwrap_or(false),
            why_not: "select a partition (ext4, NTFS, btrfs, XFS, FAT, exFAT)",
            action: fs_cmd.clone().map(Action::Terminal),
        },
        Card {
            title: "4  Recover lost partitions",
            desc: "TestDisk finds deleted partitions, repairs the partition table and boot sector, and can copy files off.",
            cmd: format!("sudo testdisk {dev}"),
            label: "Open TestDisk",
            enabled: tools.testdisk && ok_dev,
            why_not: "TestDisk is not installed",
            action: Some(Action::Terminal(format!("sudo testdisk {dev}"))),
        },
        Card {
            title: "5  Recover deleted files",
            desc: "PhotoRec carves files by signature (documents, photos, archives) even when the filesystem is gone.",
            cmd: format!("sudo photorec {dev}"),
            label: "Open PhotoRec",
            enabled: tools.photorec && ok_dev,
            why_not: "PhotoRec is not installed",
            action: Some(Action::Terminal(format!("sudo photorec {dev}"))),
        },
        Card {
            title: "6  Partition editor",
            desc: "GParted: resize, move, format or repair partitions. It shows what it will change and asks before applying.",
            cmd: format!("sudo -E gparted {dev}"),
            label: "Open GParted",
            enabled: tools.gparted && ok_dev,
            why_not: "GParted is not installed",
            action: Some(Action::Gui(vec!["sudo".into(), "-E".into(), "gparted".into(), dev.clone()])),
        },
    ];

    let gap = 16;
    let kw = (cw - gap * 2) / 3;
    let kh = 196;
    let mut pending: Option<Action> = None;
    for (i, c) in cards.into_iter().enumerate() {
        let (col, row) = (i as i32 % 3, i as i32 / 3);
        let (kx, ky) = (x0 + col * (kw + gap), cy + row * (kh + gap));
        let top = card(d, kx, ky, kw, kh, Some(c.title));
        for (li, line) in wrap(Face::Reg, c.desc, 13, kw - 32).iter().take(3).enumerate() {
            txt(d, Face::Reg, line, kx + 16, top + li as i32 * 18, 13, MUTED);
        }
        rbox(d, kx + 16, ky + kh - 98, kw - 32, 26, 4.0, BG);
        txt(d, Face::Mono, &fit(Face::Mono, &c.cmd, 11, kw - 52), kx + 24, ky + kh - 92, 11, if c.enabled { TEXT } else { FAINT });
        if button(d, inp, kx + 16, ky + kh - 60, kw - 32, 36, c.label, if c.enabled { Kind::Primary } else { Kind::Secondary }, c.enabled) {
            pending = c.action;
        }
        if !c.enabled {
            txt(d, Face::Reg, c.why_not, kx + 16, ky + kh - 20, 12, FAINT);
        }
    }
    if let Some(a) = pending {
        st.actions.push(a);
    }
    let ny = cy + 2 * (kh + gap);
    txt(d, Face::Reg, "Always recover to a different drive than the one you are reading from. TestDisk, PhotoRec and GParted ask before they write.", x0, ny, 13, MUTED);
}

// ── System & services ────────────────────────────────────────────────────────
fn kv(d: &mut impl RaylibDraw, x: i32, y: i32, k: &str, v: &str, c: Color) {
    txt(d, Face::Reg, k, x, y, 14, MUTED);
    txt(d, Face::Reg, v, x + 150, y, 14, c);
}

fn page_system(d: &mut impl RaylibDraw, st: &mut State, x: i32, y: i32, w: i32, _h: i32) {
    let (x0, mut cy) = (x + PAD, y + PAD);
    let cw = w - PAD * 2;
    page_title(d, x0, cy, "System & services", "Hardware, boot health and background services");
    cy += 76;
    let ev = &st.eval;
    let gap = 16;
    let lw = (cw - gap) / 2;

    let top = card(d, x0, cy, lw, 292, Some("System"));
    let temp_c = if ev.cpu_temp.contains("N/A") { MUTED } else { TEXT };
    let ram_used = ev.ram_total_mb.saturating_sub(ev.ram_avail_mb);
    let rows: [(&str, String, Color); 7] = [
        ("Hostname", ev.hostname.clone(), TEXT),
        ("Uptime", ev.uptime.clone(), TEXT),
        ("Processor", ev.cpu_model.clone(), TEXT),
        ("Cores", ev.cpu_count.to_string(), TEXT),
        ("CPU temperature", ev.cpu_temp.clone(), temp_c),
        ("Memory", format!("{} MB total, {} MB used ({}%)", ev.ram_total_mb, ram_used, ev.ram_used_pct), pct_color(ev.ram_used_pct)),
        ("Boot time", ev.boot_time.clone(), TEXT),
    ];
    for (i, (k, v, c)) in rows.iter().enumerate() {
        kv(d, x0 + 16, top + i as i32 * 28, k, &fit(Face::Reg, v, 14, lw - 190), *c);
    }
    let by = top + 7 * 28 + 4;
    for (i, (lbl, v)) in [("Load 1m", ev.load_1), ("5m", ev.load_5), ("15m", ev.load_15)].iter().enumerate() {
        let bx = x0 + 16 + i as i32 * ((lw - 32) / 3);
        let pc = ((v / ev.cpu_count.max(1) as f32) * 100.0).min(100.0) as u8;
        txt(d, Face::Reg, &format!("{lbl}  {v:.2}"), bx, by, 12, MUTED);
        bar(d, bx, by + 20, (lw - 32) / 3 - 14, 6, pc, pct_color(pc));
    }

    let rx = x0 + lw + gap;
    let top = card(d, rx, cy, lw, 292, Some("Services"));
    for (i, s) in ev.services.iter().take(9).enumerate() {
        let yy = top + i as i32 * 28;
        txt(d, Face::Reg, &s.name, rx + 16, yy, 14, TEXT);
        pill(d, rx + lw - 120, yy - 3, if s.active { "Running" } else { "Stopped" }, if s.active { OK } else { ERR });
    }
    cy += 292 + gap;

    let fh = 150 + ev.failed_units.len().min(3) as i32 * 26;
    let top = card(d, x0, cy, cw, fh, Some("Failed units & suggested checks"));
    if ev.failed_units.is_empty() {
        d.draw_circle(x0 + 24, top + 10, 5.0, OK);
        txt(d, Face::Reg, "No failed systemd units.", x0 + 40, top + 2, 14, TEXT);
    } else {
        for (i, u) in ev.failed_units.iter().take(3).enumerate() {
            d.draw_circle(x0 + 24, top + i as i32 * 26 + 10, 5.0, ERR);
            txt(d, Face::Mono, u, x0 + 40, top + i as i32 * 26 + 2, 13, TEXT);
        }
    }
    let ty = top + ev.failed_units.len().max(1).min(3) as i32 * 26 + 10;
    txt(d, Face::Mono, "journalctl -p err -b   |   systemd-analyze blame   |   systemctl reset-failed", x0 + 16, ty, 12, MUTED);
}

// ── MAD AI assistant ─────────────────────────────────────────────────────────
fn page_assistant(d: &mut impl RaylibDraw, st: &mut State, x: i32, y: i32, w: i32, h: i32, t: f32) {
    let (x0, cy) = (x + PAD, y + PAD);
    let cw = w - PAD * 2;
    page_title(d, x0, cy, "MAD AI assistant", "Dr. I30LTZ runs locally. It suggests; you decide. Press Esc to leave.");
    let top = cy + 76;
    let box_h = h - 76 - PAD * 2;
    card(d, x0, top, cw, box_h, None);

    let input_h = 52;
    let (vx, vy, vw, vh) = (x0 + 1, top + 1, cw - 2, box_h - input_h - 2);
    let bw = (vw as f32 * 0.74) as i32;
    // Lay out all bubbles first to know the total height.
    let mut items: Vec<(bool, Vec<String>, i32)> = Vec::new();
    let mut total = 12;
    for (bot, text) in &st.chat_log {
        let lines = wrap(Face::Reg, text, 15, bw - 28);
        let hh = lines.len() as i32 * 21 + 24;
        total += hh + 14;
        items.push((*bot, lines, hh));
    }
    if st.chat_waiting {
        total += 50;
    }
    let max_scroll = (total - vh).max(0);
    st.chat_scroll = st.chat_scroll.min(max_scroll);
    let offset = max_scroll - st.chat_scroll;

    {
        let mut sc = d.begin_scissor_mode(vx, vy, vw, vh);
        let mut yy = vy + 12 - offset;
        for (bot, lines, hh) in &items {
            let bx = if *bot { vx + 16 } else { vx + vw - bw - 16 };
            if yy + hh > vy && yy < vy + vh {
                panel(&mut sc, bx, yy, bw, *hh, if *bot { SURFACE2 } else { ACCENT_DK }, if *bot { BORDER } else { ACCENT_DK });
                for (i, l) in lines.iter().enumerate() {
                    txt(&mut sc, Face::Reg, l, bx + 14, yy + 11 + i as i32 * 21, 15, TEXT);
                }
            }
            yy += hh + 14;
        }
        if st.chat_waiting {
            let dots = ".".repeat(1 + (t * 3.0) as usize % 3);
            txt(&mut sc, Face::Reg, &format!("Dr. I30LTZ is thinking{dots}"), vx + 20, yy + 4, 14, MUTED);
        }
    }

    // Input
    let iy = top + box_h - input_h;
    d.draw_rectangle(x0 + 1, iy, cw - 2, 1, BORDER);
    let shown = if st.chat_input.is_empty() { "Describe the problem, then press Enter".to_string() } else { st.chat_input.clone() };
    let tail = fit_tail(&shown, cw - 70);
    txt(d, Face::Reg, &tail, x0 + 20, iy + 16, 16, if st.chat_input.is_empty() { FAINT } else { TEXT });
    if (t * 2.0) as i32 % 2 == 0 && !st.chat_input.is_empty() {
        d.draw_rectangle(x0 + 22 + text_w(Face::Reg, &tail, 16), iy + 14, 2, 22, ACCENT);
    }
}

/// Keep the end of `s` visible when it is wider than `max_w`.
fn fit_tail(s: &str, max_w: i32) -> String {
    let mut out: Vec<char> = s.chars().collect();
    while out.len() > 1 && text_w(Face::Reg, &out.iter().collect::<String>(), 16) > max_w {
        out.remove(0);
    }
    out.into_iter().collect()
}
