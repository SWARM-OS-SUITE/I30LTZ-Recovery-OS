mod eval;
mod chat;

use raylib::prelude::*;
use eval::{collect_all, EvalData};
use chat::spawn_chat_thread;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const BUILD_DATE: &str = env!("BUILD_DATE");
const BUILD_TS: &str = env!("BUILD_TS");

// ── Palette (DR. I30LTZ Recovery — carbon fiber + UGA red) ───────────────
const BG: Color = Color { r: 8, g: 8, b: 12, a: 255 };
const CARBON: Color = Color { r: 16, g: 16, b: 22, a: 255 };
const CARBON_LN: Color = Color { r: 26, g: 26, b: 34, a: 255 };
const UGA_RED: Color = Color { r: 186, g: 12, b: 47, a: 255 };
const UGA_RED_DIM: Color = Color { r: 120, g: 8, b: 30, a: 255 };
const UGA_SILVER: Color = Color { r: 167, g: 168, b: 170, a: 255 };
const TXT: Color = Color { r: 224, g: 224, b: 228, a: 255 };
const DIM: Color = Color { r: 100, g: 100, b: 112, a: 255 };
const OK: Color = Color { r: 0, g: 200, b: 80, a: 255 };
const WARN: Color = Color { r: 255, g: 165, b: 0, a: 255 };
const ERR: Color = Color { r: 255, g: 40, b: 60, a: 255 };

#[derive(PartialEq, Clone, Copy, Debug)]
enum Tab {
    System,
    Boot,
    Disk,
    Services,
    Chat,
}

struct State {
    tab: Tab,
    eval: EvalData,
    chat_log: Vec<(bool, String)>, // (from_boltz, text)
    chat_input: String,
    last_eval: f64,
    req_tx: std::sync::mpsc::Sender<String>,
    resp_rx: std::sync::mpsc::Receiver<String>,
    chat_waiting: bool,
    chat_scroll: i32,
}

fn main() {
    const W: i32 = 1440;
    const H: i32 = 900;
    const AVATAR_W: i32 = 420;
    const HEADER_H: i32 = 60;
    const FOOTER_H: i32 = 40;

    let (mut rl, thread) = raylib::init()
        .size(W, H)
        .title("DR. I30LTZ  |  Recovery Evaluation System")
        .resizable()
        .build();
    rl.set_target_fps(60);

    // Render texture for the 3D avatar panel
    let av_tex_h = H - HEADER_H - FOOTER_H;
    let mut av_rt = rl
        .load_render_texture(&thread, AVATAR_W as u32, av_tex_h as u32)
        .expect("render texture");

    // 3D camera — full-body view of the bulldog
    let camera = Camera3D::perspective(
        Vector3::new(0.0, 2.6, 6.5),
        Vector3::new(0.0, 1.1, 0.0),
        Vector3::new(0.0, 1.0, 0.0),
        45.0,
    );

    // Config from environment
    let lucy_url = std::env::var("LUCY_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:5000".to_string());
    let auth_token = std::env::var("SWARM_AUTH_TOKEN")
        .or_else(|_| std::env::var("BOLTZ_AUTH_TOKEN"))
        .unwrap_or_else(|_| "swarm-token-2026".to_string());

    let (req_tx, resp_rx) = spawn_chat_thread(lucy_url, auth_token);

    let mut state = State {
        tab: Tab::System,
        eval: collect_all(),
        chat_log: vec![(
            true,
            "DR. I30LTZ online.\n\nI evaluate systems, diagnose boot failures, audit disk health, \
             and provide AI-assisted recovery.\n\nType a question or describe a problem."
                .to_string(),
        )],
        chat_input: String::new(),
        last_eval: 0.0,
        req_tx,
        resp_rx,
        chat_waiting: false,
        chat_scroll: 0,
    };

    while !rl.window_should_close() {
        let t = rl.get_time();
        let t_f32 = t as f32;

        // Tab switching
        if rl.is_key_pressed(KeyboardKey::KEY_ONE) { state.tab = Tab::System; }
        if rl.is_key_pressed(KeyboardKey::KEY_TWO) { state.tab = Tab::Boot; }
        if rl.is_key_pressed(KeyboardKey::KEY_THREE) { state.tab = Tab::Disk; }
        if rl.is_key_pressed(KeyboardKey::KEY_FOUR) { state.tab = Tab::Services; }
        if rl.is_key_pressed(KeyboardKey::KEY_FIVE) { state.tab = Tab::Chat; }
        if rl.is_key_pressed(KeyboardKey::KEY_TAB) {
            state.tab = match state.tab {
                Tab::System => Tab::Boot,
                Tab::Boot => Tab::Disk,
                Tab::Disk => Tab::Services,
                Tab::Services => Tab::Chat,
                Tab::Chat => Tab::System,
            };
        }

        // Eval refresh every 5 seconds
        if t - state.last_eval > 5.0 {
            state.eval = collect_all();
            state.last_eval = t;
        }

        // Chat input
        if state.tab == Tab::Chat {
            loop {
                match rl.get_char_pressed() {
                    Some(c) if c >= ' ' => state.chat_input.push(c),
                    Some(_) => {}
                    None => break,
                }
            }
            if rl.is_key_pressed(KeyboardKey::KEY_BACKSPACE) && !state.chat_input.is_empty() {
                state.chat_input.pop();
            }
            if rl.is_key_pressed(KeyboardKey::KEY_ENTER)
                && !state.chat_input.is_empty()
                && !state.chat_waiting
            {
                let msg = state.chat_input.trim().to_string();
                if !msg.is_empty() {
                    state.chat_log.push((false, msg.clone()));
                    state.req_tx.send(msg).ok();
                    state.chat_input.clear();
                    state.chat_waiting = true;
                    state.chat_scroll = 0;
                }
            }
            // Chat scroll
            let wheel = rl.get_mouse_wheel_move();
            state.chat_scroll = (state.chat_scroll - (wheel * 3.0) as i32).max(0);
        }

        // Incoming chat response
        match state.resp_rx.try_recv() {
            Ok(resp) => {
                state.chat_log.push((true, resp));
                state.chat_waiting = false;
            }
            Err(_) => {}
        }

        // ── Render 3D avatar to texture ─────────────────────────────────────
        {
            let mut td = rl.begin_texture_mode(&thread, &mut av_rt);
            td.clear_background(Color { r: 6, g: 6, b: 10, a: 255 });

            // Carbon fiber background
            draw_carbon_panel(&mut td, 0, 0, AVATAR_W, av_tex_h);

            // 3D scene
            {
                let mut d3 = td.begin_mode3D(camera);
                // Ground grid
                d3.draw_grid(14, 0.5);
                // The dog
                draw_bulldog(&mut d3, t_f32);
                // Orbit ring — holographic evaluation circle
                draw_orbit(&mut d3, t_f32);
            }

            // Scan-line overlay
            draw_scan_lines(&mut td, 0, 0, AVATAR_W, av_tex_h, t_f32);

            // Name plate at bottom
            td.draw_rectangle(0, av_tex_h - 80, AVATAR_W, 80, Color { r: 0, g: 0, b: 0, a: 180 });
            td.draw_rectangle(0, av_tex_h - 82, AVATAR_W, 2, UGA_RED);
            td.draw_text("DR. I30LTZ", 16, av_tex_h - 68, 30, UGA_RED);
            td.draw_text("RECOVERY  EVALUATION  AI", 16, av_tex_h - 34, 16, UGA_SILVER);

            // Live indicator
            let blink = ((t_f32 * 2.0).sin() > 0.0) as i32;
            if blink == 1 {
                td.draw_circle(AVATAR_W - 20, av_tex_h - 20, 6.0, OK);
            }
            td.draw_text("LIVE", AVATAR_W - 52, av_tex_h - 26, 12, OK);
        }

        // ── Main drawing ──────────────────────────────────────────────────────
        let mut d = rl.begin_drawing(&thread);
        d.clear_background(BG);

        // Header
        draw_header(&mut d, W, t_f32);

        // Avatar texture (flip Y because OpenGL texture coords)
        d.draw_texture_rec(
            av_rt.texture(),
            Rectangle::new(0.0, 0.0, AVATAR_W as f32, -(av_tex_h as f32)),
            Vector2::new(0.0, HEADER_H as f32),
            Color::WHITE,
        );

        // Vertical divider
        d.draw_rectangle(AVATAR_W, HEADER_H, 2, H - HEADER_H - FOOTER_H, UGA_RED_DIM);

        // Right panel
        let px = AVATAR_W + 2;
        let pw = W - px;
        let py = HEADER_H;
        let ph = H - HEADER_H - FOOTER_H;

        draw_tab_bar(&mut d, px, py, pw, state.tab);

        let cy = py + 44;
        let ch = ph - 44;

        match state.tab {
            Tab::System => draw_system(&mut d, px, cy, pw, ch, &state.eval, t_f32),
            Tab::Boot => draw_boot(&mut d, px, cy, pw, ch, &state.eval),
            Tab::Disk => draw_disk(&mut d, px, cy, pw, ch, &state.eval),
            Tab::Services => draw_services(&mut d, px, cy, pw, ch, &state.eval),
            Tab::Chat => draw_chat(&mut d, px, cy, pw, ch, &state, t_f32),
        }

        // Footer
        draw_footer(&mut d, W, H);
    }
}

// ── Carbon fiber background ────────────────────────────────────────────────
fn draw_carbon_panel(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32) {
    d.draw_rectangle(x, y, w, h, CARBON);
    let step = 14i32;
    // Two sets of diagonals — woven effect
    let mut i = -h;
    while i < w + h {
        d.draw_line(x + i, y, x + i - h, y + h, CARBON_LN);
        i += step;
    }
    let mut i = -h;
    while i < w + h {
        d.draw_line(x + w - i + h, y, x + w - i, y + h, Color { r: 22, g: 22, b: 30, a: 255 });
        i += step;
    }
}

fn draw_scan_lines(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, t: f32) {
    // Moving scan line
    let scan = y + ((t * 80.0) as i32 % h);
    d.draw_rectangle(x, scan, w, 3, Color { r: 186, g: 12, b: 47, a: 22 });
    d.draw_rectangle(x, scan - 1, w, 1, Color { r: 186, g: 12, b: 47, a: 50 });
    // Static scanline rows
    let mut row = y;
    while row < y + h {
        d.draw_line(x, row, x + w, row, Color { r: 0, g: 0, b: 0, a: 30 });
        row += 4;
    }
}

// ── Header / footer / tabs ─────────────────────────────────────────────────
fn draw_header(d: &mut impl RaylibDraw, w: i32, t: f32) {
    d.draw_rectangle(0, 0, w, 60, Color { r: 10, g: 10, b: 15, a: 255 });
    d.draw_rectangle(0, 58, w, 2, UGA_RED);
    d.draw_rectangle(0, 0, 4, 60, UGA_RED);
    d.draw_rectangle(w - 4, 0, 4, 60, UGA_RED);

    d.draw_text("DR. I30LTZ", 16, 12, 32, UGA_RED);
    d.draw_text("RECOVERY EVALUATION SYSTEM", 208, 20, 16, UGA_SILVER);

    let ver_str = format!("v{}  |  {}", VERSION, BUILD_DATE);
    let vw2 = measure_text_width(&ver_str, 13);
    d.draw_text(&ver_str, w - vw2 - 20, 10, 13, DIM);
    let ts = format!("ONLINE  T+{:.0}s", t);
    let tw = measure_text_width(&ts, 13);
    d.draw_text(&ts, w - tw - 20, 28, 13, OK);
}

fn draw_footer(d: &mut impl RaylibDraw, w: i32, h: i32) {
    d.draw_rectangle(0, h - 40, w, 40, Color { r: 8, g: 8, b: 12, a: 255 });
    d.draw_rectangle(0, h - 40, w, 1, UGA_RED_DIM);
    d.draw_text("[1] SYSTEM  [2] BOOT  [3] DISK  [4] SERVICES  [5] I30LTZ CHAT  [TAB] cycle", 16, h - 26, 13, DIM);
    let ver_label = format!("DR. I30LTZ Recovery  v{}  |  {}", VERSION, BUILD_DATE);
    let vw = measure_text_width(&ver_label, 13);
    d.draw_text(&ver_label, w - vw - 12, h - 26, 13, Color { r: 80, g: 80, b: 100, a: 200 });
}

fn draw_tab_bar(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, active: Tab) {
    d.draw_rectangle(x, y, w, 44, Color { r: 10, g: 10, b: 15, a: 255 });
    d.draw_rectangle(x, y + 42, w, 2, UGA_RED_DIM);

    let tabs = [
        (Tab::System, "1  SYSTEM"),
        (Tab::Boot, "2  BOOT"),
        (Tab::Disk, "3  DISK"),
        (Tab::Services, "4  SERVICES"),
        (Tab::Chat, "5  I30LTZ CHAT"),
    ];
    let tw = w / tabs.len() as i32;
    for (i, (tab, label)) in tabs.iter().enumerate() {
        let tx = x + i as i32 * tw;
        if *tab == active {
            d.draw_rectangle(tx, y, tw, 44, UGA_RED);
            d.draw_text(label, tx + 10, y + 14, 15, Color::WHITE);
        } else {
            d.draw_rectangle_lines(tx, y, tw, 44, Color { r: 35, g: 35, b: 48, a: 255 });
            d.draw_text(label, tx + 10, y + 14, 15, DIM);
        }
    }
}

// ── System tab ────────────────────────────────────────────────────────────
fn draw_system(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, _h: i32, ev: &EvalData, t: f32) {
    let pad = 20i32;
    let col = x + pad;
    let mut row = y + pad;
    let fs = 16i32;
    let ls = 26i32;

    section_header(d, col, row, "SYSTEM OVERVIEW");
    row += 36;

    kv(d, col, row, "Hostname", &ev.hostname, TXT); row += ls;
    kv(d, col, row, "Uptime", &ev.uptime, TXT); row += ls;
    kv(d, col, row, "CPU", &ev.cpu_model, TXT); row += ls;
    kv(d, col, row, "CPU Cores", &ev.cpu_count.to_string(), TXT); row += ls;
    kv(d, col, row, "CPU Temp", &ev.cpu_temp,
       if ev.cpu_temp.contains("N/A") { DIM } else { temp_color(&ev.cpu_temp) }); row += ls;

    row += 10;
    section_header(d, col, row, "MEMORY");
    row += 36;

    let ram_used = ev.ram_total_mb - ev.ram_avail_mb;
    kv(d, col, row, "RAM Total", &format!("{} MB", ev.ram_total_mb), TXT); row += ls;
    kv(d, col, row, "RAM Used", &format!("{} MB  ({}%)", ram_used, ev.ram_used_pct),
       pct_color(ev.ram_used_pct)); row += ls;
    kv(d, col, row, "RAM Free", &format!("{} MB", ev.ram_avail_mb), TXT); row += ls;

    // RAM bar
    draw_bar(d, col, row, w - pad * 3, 16, ev.ram_used_pct, pct_color(ev.ram_used_pct));
    row += 30;

    row += 10;
    section_header(d, col, row, "LOAD AVERAGE");
    row += 36;

    kv(d, col, row, "1  min", &format!("{:.2}", ev.load_1), load_color(ev.load_1, ev.cpu_count)); row += ls;
    kv(d, col, row, "5  min", &format!("{:.2}", ev.load_5), load_color(ev.load_5, ev.cpu_count)); row += ls;
    kv(d, col, row, "15 min", &format!("{:.2}", ev.load_15), load_color(ev.load_15, ev.cpu_count)); row += ls;

    // Animated load sparkline
    let sparkle_x = col;
    let sparkle_y = row + 8;
    let sparkle_w = (w - pad * 3).min(400);
    let _ = (sparkle_x, sparkle_y, sparkle_w, t, fs);  // silence unused warnings
}

// ── Boot tab ──────────────────────────────────────────────────────────────
fn draw_boot(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, _h: i32, ev: &EvalData) {
    let col = x + 20;
    let mut row = y + 20;
    let ls = 24i32;

    section_header(d, col, row, "BOOT TIMING");
    row += 36;
    d.draw_text(&ev.boot_time, col, row, 15, TXT);
    row += ls + 10;

    section_header(d, col, row, "FAILED UNITS");
    row += 36;

    if ev.failed_units.is_empty() {
        status_chip(d, col, row, "No failed units", OK);
    } else {
        for unit in &ev.failed_units {
            status_chip(d, col, row, unit, ERR);
            row += 28;
        }
    }
    row += 36;

    section_header(d, col, row, "RECOVERY ACTIONS");
    row += 36;
    let tips = [
        "systemctl reset-failed          — clear failed unit state",
        "journalctl -p err -b            — boot errors this session",
        "systemd-analyze blame           — slowest units at boot",
        "systemctl list-units --failed   — all failed units",
    ];
    for tip in &tips {
        d.draw_text(tip, col, row, 14, DIM);
        row += 22;
    }
    let _ = w;
}

// ── Disk tab ──────────────────────────────────────────────────────────────
fn draw_disk(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, _h: i32, ev: &EvalData) {
    let col = x + 20;
    let mut row = y + 20;

    section_header(d, col, row, "DISK USAGE");
    row += 36;

    if ev.mounts.is_empty() {
        d.draw_text("No mounts detected", col, row, 15, DIM);
        return;
    }

    let bar_w = (w - 60).min(560);
    for m in &ev.mounts {
        let label = format!("{:<28}  {:>5} / {:>5}  ({}% used)",
            m.target, m.used, m.size, m.pct);
        d.draw_text(&label, col, row, 14, TXT);
        row += 18;
        draw_bar(d, col, row, bar_w, 10, m.pct, pct_color(m.pct));
        row += 20;

        // Highlight critical SWARM mounts
        if m.target.contains("Lucy") || m.target.contains("brains") || m.target.contains("boltz") || m.target.contains("slick") {
            d.draw_rectangle(col - 4, row - 52, 3, 48, UGA_RED);
        }
    }
}

// ── Services tab ──────────────────────────────────────────────────────────
fn draw_services(d: &mut impl RaylibDraw, x: i32, y: i32, _w: i32, _h: i32, ev: &EvalData) {
    let col = x + 20;
    let mut row = y + 20;
    let ls = 32i32;

    section_header(d, col, row, "SERVICE STATUS");
    row += 36;

    for svc in &ev.services {
        let (label, color) = if svc.active {
            ("● ACTIVE  ", OK)
        } else {
            ("○ INACTIVE", ERR)
        };
        d.draw_text(label, col, row, 15, color);
        d.draw_text(&svc.name, col + 120, row, 15, TXT);
        row += ls;
    }

    row += 10;
    section_header(d, col, row, "SWARM MOUNTS");
    row += 36;

    let mounts = [
        ("/mnt/Lucy", "SWARM OS live drive"),
        ("/mnt/brains", "Lucille memory"),
        ("/mnt/boltz", "DR. I30LTZ / Lucille-AI"),
        ("/mnt/slick", "Confidential mode (LUKS)"),
    ];
    for (path, desc) in &mounts {
        let exists = std::path::Path::new(path)
            .read_dir()
            .map(|mut r| r.next().is_some())
            .unwrap_or(false);
        let (sym, col_c) = if exists { ("✓", OK) } else { ("✗", DIM) };
        d.draw_text(sym, col, row, 15, col_c);
        d.draw_text(path, col + 20, row, 15, if exists { TXT } else { DIM });
        d.draw_text(desc, col + 180, row, 13, DIM);
        row += 26;
    }
}

// ── Chat tab ──────────────────────────────────────────────────────────────
fn draw_chat(
    d: &mut impl RaylibDraw,
    x: i32, y: i32, w: i32, h: i32,
    state: &State, t: f32,
) {
    draw_carbon_panel(d, x, y, w, h);

    let col = x + 16;
    let input_h = 48i32;
    let msg_area_h = h - input_h - 8;

    // Message area
    let mut msgs: Vec<(bool, Vec<String>)> = Vec::new();
    for (from_boltz, text) in &state.chat_log {
        let lines: Vec<String> = text.lines().map(|l| l.to_string()).collect();
        msgs.push((*from_boltz, lines));
    }

    // Calculate total height and apply scroll
    let line_h = 18i32;
    let mut total_h = 0i32;
    for (_, lines) in &msgs {
        total_h += (lines.len() as i32 + 1) * line_h + 12;
    }

    let max_scroll = (total_h - msg_area_h).max(0);
    let scroll = (state.chat_scroll as i32).min(max_scroll);

    // Clip to message area
    d.draw_rectangle(x, y, w, msg_area_h, Color { r: 0, g: 0, b: 0, a: 60 });

    let mut draw_y = y + 8 - scroll;
    for (from_boltz, lines) in &msgs {
        if draw_y + line_h * lines.len() as i32 > y + msg_area_h {
            // Could do proper clipping — skip for now
        }
        if draw_y < y + msg_area_h {
            let (prefix, color, bg) = if *from_boltz {
                ("DR. I30LTZ  ", UGA_RED, Color { r: 20, g: 12, b: 16, a: 255 })
            } else {
                ("You        ", UGA_SILVER, Color { r: 14, g: 14, b: 20, a: 255 })
            };
            if draw_y >= y {
                d.draw_rectangle(x, draw_y, w, line_h, bg);
                d.draw_text(prefix, col, draw_y, 13, color);
            }
            draw_y += line_h;
            for line in lines {
                if draw_y >= y && draw_y < y + msg_area_h {
                    let display = if line.is_empty() { " " } else { line.as_str() };
                    d.draw_text(display, col + 8, draw_y, 14, TXT);
                }
                draw_y += line_h;
            }
            draw_y += 12;
        } else {
            draw_y += (lines.len() as i32 + 1) * line_h + 12;
        }
    }

    // Waiting indicator
    if state.chat_waiting {
        let dots = match (t * 3.0) as i32 % 4 {
            0 => ".",
            1 => "..",
            2 => "...",
            _ => "",
        };
        let wait_y = y + msg_area_h - 22;
        d.draw_text(&format!("DR. I30LTZ  {}", dots), col, wait_y, 14, UGA_RED_DIM);
    }

    // Input bar
    let iy = y + msg_area_h + 4;
    d.draw_rectangle(x, iy, w, input_h, Color { r: 12, g: 12, b: 18, a: 255 });
    d.draw_rectangle(x, iy, w, 1, UGA_RED_DIM);

    let cursor = if ((t * 2.0) as i32 % 2) == 0 { "│" } else { " " };
    let input_display = format!("> {}{}", state.chat_input, cursor);
    d.draw_text(&input_display, col, iy + 14, 15, TXT);

    if state.chat_input.is_empty() && !state.chat_waiting {
        d.draw_text("Ask DR. I30LTZ something... (Enter to send)", col + 20, iy + 14, 15, DIM);
    }
}

// ── 3D Avatar: DR. I30LTZ — UGA Bulldog ──────────────────────────────────
fn draw_bulldog(d: &mut impl RaylibDraw3D, t: f32) {
    let breath = (t * 1.5_f32).sin() * 0.025;
    let bob = (t * 1.5_f32).sin() * 0.015;
    let tail = (t * 4.0_f32).sin() * 0.5;  // tail wag amplitude in rotation
    let blink = ((t * 0.4_f32).sin() > 0.85) as i32;

    let body_y = breath;
    let head_y = 2.05_f32 + bob + breath;

    // Colors
    let red = Color { r: 186, g: 12, b: 47, a: 255 };
    let dark_red = Color { r: 140, g: 8, b: 35, a: 255 };
    let black = Color { r: 12, g: 12, b: 18, a: 255 };
    let eye_white = Color { r: 220, g: 220, b: 220, a: 255 };
    let silver = Color { r: 167, g: 168, b: 170, a: 255 };

    // ── Paws
    for &(px, pz) in &[(-0.38, 0.40), (0.38, 0.40), (-0.38, -0.38), (0.38, -0.38)] {
        d.draw_sphere(Vector3::new(px, 0.0, pz), 0.17, black);
    }

    // ── Legs
    d.draw_cylinder(Vector3::new(-0.38, 0.0, 0.40), 0.15, 0.15, 0.72, 8, red);
    d.draw_cylinder(Vector3::new( 0.38, 0.0, 0.40), 0.15, 0.15, 0.72, 8, red);
    d.draw_cylinder(Vector3::new(-0.38, 0.0,-0.38), 0.15, 0.15, 0.72, 8, red);
    d.draw_cylinder(Vector3::new( 0.38, 0.0,-0.38), 0.15, 0.15, 0.72, 8, red);

    // ── Belly / torso
    d.draw_sphere(Vector3::new(0.0, body_y + 0.7, 0.12), 0.55, Color { r: 200, g: 18, b: 52, a: 255 });
    d.draw_sphere(Vector3::new(0.0, body_y + 1.0, 0.0), 0.68, red);

    // ── Neck
    d.draw_cylinder(Vector3::new(0.0, body_y + 1.28, 0.08), 0.28, 0.24, 0.46, 8, red);

    // ── Tech collar (red + silver beads)
    for i in 0..16i32 {
        let a = (i as f32 / 16.0) * std::f32::consts::TAU;
        let r = 0.30_f32;
        let bx = a.cos() * r;
        let bz = a.sin() * r + 0.06;
        let bead_col = if i % 4 == 0 { red } else { silver };
        d.draw_sphere(Vector3::new(bx, body_y + 1.26, bz), 0.05, bead_col);
    }

    // ── Head
    d.draw_sphere(Vector3::new(0.0, head_y, 0.0), 0.72, red);

    // Jowls
    d.draw_sphere(Vector3::new(-0.42, head_y - 0.22, 0.32), 0.36, dark_red);
    d.draw_sphere(Vector3::new( 0.42, head_y - 0.22, 0.32), 0.36, dark_red);

    // Snout
    d.draw_sphere(Vector3::new(0.0, head_y - 0.14, 0.62), 0.30, Color { r: 165, g: 10, b: 40, a: 255 });

    // Nose
    d.draw_sphere(Vector3::new(0.0, head_y - 0.04, 0.88), 0.13, black);

    // Eyes (blink by shrinking y radius)
    if blink == 0 {
        d.draw_sphere(Vector3::new(-0.30, head_y + 0.20, 0.60), 0.12, eye_white);
        d.draw_sphere(Vector3::new( 0.30, head_y + 0.20, 0.60), 0.12, eye_white);
        // Pupils
        d.draw_sphere(Vector3::new(-0.30, head_y + 0.20, 0.70), 0.065, black);
        d.draw_sphere(Vector3::new( 0.30, head_y + 0.20, 0.70), 0.065, black);
        // Eye shine
        d.draw_sphere(Vector3::new(-0.27, head_y + 0.23, 0.74), 0.025, eye_white);
        d.draw_sphere(Vector3::new( 0.33, head_y + 0.23, 0.74), 0.025, eye_white);
    } else {
        // Blink: flat dark line
        d.draw_sphere(Vector3::new(-0.30, head_y + 0.20, 0.62), 0.10, black);
        d.draw_sphere(Vector3::new( 0.30, head_y + 0.20, 0.62), 0.10, black);
    }

    // Ears
    d.draw_cylinder(Vector3::new(-0.60, head_y + 0.08, 0.0), 0.17, 0.12, 0.44, 6, dark_red);
    d.draw_cylinder(Vector3::new( 0.60, head_y + 0.08, 0.0), 0.17, 0.12, 0.44, 6, dark_red);

    // ── Tail (wagging — offset position with sine)
    let tail_x = tail * 0.04;
    d.draw_cylinder(
        Vector3::new(tail_x, body_y + 0.92, -0.64),
        0.09, 0.06, 0.30, 6,
        red,
    );
}

// Holographic evaluation orbit rings around the avatar
fn draw_orbit(d: &mut impl RaylibDraw3D, t: f32) {
    let count = 20i32;
    // Outer ring
    for i in 0..count {
        let a = (i as f32 / count as f32) * std::f32::consts::TAU + t * 0.6;
        let r = 1.6_f32;
        d.draw_sphere(
            Vector3::new(a.cos() * r, 1.0 + (a * 2.0).sin() * 0.1, a.sin() * r),
            0.04,
            Color { r: 186, g: 12, b: 47, a: 80 },
        );
    }
    // Inner ring (opposite direction)
    for i in 0..count {
        let a = (i as f32 / count as f32) * std::f32::consts::TAU - t * 0.9;
        let r = 1.1_f32;
        d.draw_sphere(
            Vector3::new(a.cos() * r, 1.05, a.sin() * r),
            0.03,
            Color { r: 167, g: 168, b: 170, a: 60 },
        );
    }
}

// ── UI helpers ────────────────────────────────────────────────────────────
fn section_header(d: &mut impl RaylibDraw, x: i32, y: i32, title: &str) {
    d.draw_rectangle(x - 4, y, 3, 20, UGA_RED);
    d.draw_text(title, x + 6, y + 2, 14, UGA_SILVER);
    d.draw_rectangle(x + 6, y + 20, measure_text_width(title, 14) + 20, 1, UGA_RED_DIM);
}

fn kv(d: &mut impl RaylibDraw, x: i32, y: i32, key: &str, val: &str, val_color: Color) {
    d.draw_text(&format!("{:<18}", key), x, y, 14, DIM);
    d.draw_text(val, x + 180, y, 14, val_color);
}

fn draw_bar(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, pct: u8, color: Color) {
    d.draw_rectangle(x, y, w, h, Color { r: 25, g: 25, b: 35, a: 255 });
    let fill = (w as f32 * pct as f32 / 100.0) as i32;
    if fill > 0 {
        d.draw_rectangle(x, y, fill, h, color);
    }
    d.draw_rectangle_lines(x, y, w, h, Color { r: 50, g: 50, b: 65, a: 255 });
}

fn status_chip(d: &mut impl RaylibDraw, x: i32, y: i32, text: &str, color: Color) {
    let tw = measure_text_width(text, 14);
    d.draw_rectangle(x - 2, y - 2, tw + 16, 22, Color { r: color.r / 5, g: color.g / 5, b: color.b / 5, a: 255 });
    d.draw_rectangle_lines(x - 2, y - 2, tw + 16, 22, color);
    d.draw_text(text, x + 6, y + 2, 14, color);
}

// ── Color helpers ─────────────────────────────────────────────────────────
fn pct_color(pct: u8) -> Color {
    if pct >= 90 { ERR } else if pct >= 70 { WARN } else { OK }
}

fn load_color(load: f32, cores: u32) -> Color {
    let ratio = load / cores.max(1) as f32;
    if ratio >= 1.0 { ERR } else if ratio >= 0.7 { WARN } else { OK }
}

fn temp_color(s: &str) -> Color {
    let val: f32 = s.trim_end_matches("°C").parse().unwrap_or(0.0);
    if val >= 85.0 { ERR } else if val >= 70.0 { WARN } else { OK }
}

fn measure_text_width(text: &str, font_size: i32) -> i32 {
    // Raylib default font: roughly 10px per char at size 20
    // At size 14: ~7px per char
    text.len() as i32 * (font_size / 2 + 1)
}
