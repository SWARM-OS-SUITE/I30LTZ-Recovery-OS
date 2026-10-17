// I30LTZ Recovery console: UI toolkit (palette, bundled fonts, immediate-mode widgets).
// Enterprise look: neutral dark slate, one accent, restrained status colours, real fonts.
use raylib::prelude::*;
use std::cell::RefCell;

// ── Palette ───────────────────────────────────────────────────────────────
const fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color { r, g, b, a: 255 }
}
pub const BG: Color = rgb(13, 18, 23);
pub const SURFACE: Color = rgb(20, 27, 34);
pub const SURFACE2: Color = rgb(27, 36, 45);
pub const SURFACE3: Color = rgb(34, 45, 56);
pub const BORDER: Color = rgb(40, 53, 66);
pub const TEXT: Color = rgb(228, 236, 243);
pub const MUTED: Color = rgb(139, 154, 168);
pub const FAINT: Color = rgb(92, 108, 122);
pub const ACCENT: Color = rgb(52, 211, 153);
pub const ACCENT_DK: Color = rgb(16, 94, 70);
pub const INFO: Color = rgb(96, 165, 250);
pub const OK: Color = rgb(52, 211, 153);
pub const WARN: Color = rgb(245, 178, 50);
pub const ERR: Color = rgb(239, 90, 90);

pub fn alpha(c: Color, a: u8) -> Color {
    Color { a, ..c }
}

// ── Fonts (bundled TTFs; falls back to raylib's built-in font if missing) ───
#[derive(Clone, Copy)]
pub enum Face {
    Reg,
    Bold,
    Mono,
}

struct Fonts {
    reg: Font,
    bold: Font,
    mono: Font,
}

thread_local! {
    static FONTS: RefCell<Option<Fonts>> = const { RefCell::new(None) };
}

fn load_one(rl: &mut RaylibHandle, th: &RaylibThread, dir: &str, file: &str, size: i32) -> Option<Font> {
    let f = rl.load_font_ex(th, &format!("{dir}/{file}"), size, None).ok()?;
    let tex: &raylib::ffi::Texture2D = f.as_ref();
    unsafe { raylib::ffi::SetTextureFilter(*tex, raylib::ffi::TextureFilter::TEXTURE_FILTER_BILINEAR as i32) };
    Some(f)
}

/// Installed on the ISO at /opt/i30ltz/fonts (70-scripts/build.sh); second path is for running from the build tree.
pub fn load_fonts(rl: &mut RaylibHandle, th: &RaylibThread) {
    for dir in ["/opt/i30ltz/fonts", concat!(env!("CARGO_MANIFEST_DIR"), "/../recovery-os-images/fonts")] {
        if let (Some(reg), Some(bold), Some(mono)) = (
            load_one(rl, th, dir, "Lato-Regular.ttf", 48),
            load_one(rl, th, dir, "Lato-Bold.ttf", 48),
            load_one(rl, th, dir, "Hack-Regular.ttf", 40),
        ) {
            FONTS.with(|f| *f.borrow_mut() = Some(Fonts { reg, bold, mono }));
            return;
        }
    }
}

/// Free the fonts while the window still exists (dropping them after CloseWindow crashes).
pub fn unload_fonts() {
    FONTS.with(|f| *f.borrow_mut() = None);
}

/// The bundled fonts hold plain ASCII only; map the few other characters we print.
fn ascii(s: &str) -> String {
    s.replace("°C", " C")
        .replace('\u{2026}', "...")
        .replace('\t', "    ")
        .chars()
        .map(|c| match c {
            ' '..='~' | '\n' => c,
            '°' | '·' | '•' | '●' => '*',
            '–' | '—' | '\u{2212}' => '-',
            '\u{2018}' | '\u{2019}' => '\'',
            '\u{201C}' | '\u{201D}' => '"',
            '\u{2192}' => '>',
            '\t' => ' ',
            _ => '?',
        })
        .collect()
}

pub fn txt(d: &mut impl RaylibDraw, face: Face, s: &str, x: i32, y: i32, size: i32, color: Color) {
    let s = ascii(s);
    let drawn = FONTS.with(|f| {
        if let Some(fo) = &*f.borrow() {
            let font = match face {
                Face::Reg => &fo.reg,
                Face::Bold => &fo.bold,
                Face::Mono => &fo.mono,
            };
            d.draw_text_ex(font, &s, Vector2::new(x as f32, y as f32), size as f32, 0.0, color);
            true
        } else {
            false
        }
    });
    if !drawn {
        d.draw_text(&s, x, y, size, color);
    }
}

pub fn text_w(face: Face, s: &str, size: i32) -> i32 {
    let s = ascii(s);
    FONTS.with(|f| {
        if let Some(fo) = &*f.borrow() {
            let font = match face {
                Face::Reg => &fo.reg,
                Face::Bold => &fo.bold,
                Face::Mono => &fo.mono,
            };
            font.measure_text(&s, size as f32, 0.0).x as i32
        } else {
            s.len() as i32 * (size / 2 + 1)
        }
    })
}

/// Cut `s` with an ellipsis so it fits in `max_w` pixels.
pub fn fit(face: Face, s: &str, size: i32, max_w: i32) -> String {
    if text_w(face, s, size) <= max_w {
        return s.to_string();
    }
    let mut out: String = s.chars().collect();
    while !out.is_empty() && text_w(face, &format!("{out}..."), size) > max_w {
        out.pop();
    }
    format!("{out}...")
}

// ── Input state for immediate-mode widgets ─────────────────────────────────
#[derive(Clone, Copy)]
pub struct Input {
    pub mx: i32,
    pub my: i32,
    pub clicked: bool,
}

impl Input {
    pub fn over(&self, x: i32, y: i32, w: i32, h: i32) -> bool {
        self.mx >= x && self.mx < x + w && self.my >= y && self.my < y + h
    }
    pub fn click_in(&self, x: i32, y: i32, w: i32, h: i32) -> bool {
        self.clicked && self.over(x, y, w, h)
    }
}

// ── Shapes ────────────────────────────────────────────────────────────────
pub fn rbox(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, radius: f32, color: Color) {
    let round = (2.0 * radius / (w.min(h) as f32).max(1.0)).min(1.0);
    d.draw_rectangle_rounded(Rectangle::new(x as f32, y as f32, w as f32, h as f32), round, 8, color);
}

/// Filled rounded rectangle with a 1 px border.
pub fn panel(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, fill: Color, border: Color) {
    rbox(d, x, y, w, h, 6.0, border);
    rbox(d, x + 1, y + 1, w - 2, h - 2, 5.0, fill);
}

/// Card with an optional title bar. Returns the y where content can start.
pub fn card(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, title: Option<&str>) -> i32 {
    panel(d, x, y, w, h, SURFACE, BORDER);
    if let Some(t) = title {
        txt(d, Face::Bold, &t.to_uppercase(), x + 16, y + 13, 13, MUTED);
        d.draw_rectangle(x + 1, y + 38, w - 2, 1, BORDER);
        y + 50
    } else {
        y + 14
    }
}

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Primary,
    Secondary,
}

/// Button; returns true when clicked. `enabled=false` draws it dimmed and ignores clicks.
pub fn button(d: &mut impl RaylibDraw, inp: &Input, x: i32, y: i32, w: i32, h: i32, label: &str, kind: Kind, enabled: bool) -> bool {
    let hover = enabled && inp.over(x, y, w, h);
    let (fill, border, fg) = match (kind, enabled) {
        (_, false) => (SURFACE, BORDER, FAINT),
        (Kind::Primary, true) => (if hover { rgb(72, 226, 170) } else { ACCENT }, ACCENT, rgb(6, 30, 22)),
        (Kind::Secondary, true) => (if hover { SURFACE3 } else { SURFACE2 }, if hover { FAINT } else { BORDER }, TEXT),
    };
    rbox(d, x, y, w, h, 5.0, border);
    rbox(d, x + 1, y + 1, w - 2, h - 2, 4.0, fill);
    let lw = text_w(Face::Bold, label, 14);
    txt(d, Face::Bold, label, x + (w - lw) / 2, y + (h - 16) / 2, 14, fg);
    enabled && inp.click_in(x, y, w, h)
}

/// Small status pill; returns its width.
pub fn pill(d: &mut impl RaylibDraw, x: i32, y: i32, label: &str, color: Color) -> i32 {
    let w = text_w(Face::Bold, label, 12) + 22;
    rbox(d, x, y, w, 22, 11.0, alpha(color, 38));
    d.draw_circle(x + 11, y + 11, 3.0, color);
    txt(d, Face::Bold, label, x + 19, y + 4, 12, color);
    w
}

pub fn bar(d: &mut impl RaylibDraw, x: i32, y: i32, w: i32, h: i32, pct: u8, color: Color) {
    rbox(d, x, y, w, h, h as f32 / 2.0, SURFACE3);
    let fill = (w as f32 * pct.min(100) as f32 / 100.0) as i32;
    if fill >= h {
        rbox(d, x, y, fill, h, h as f32 / 2.0, color);
    } else if fill > 0 {
        rbox(d, x, y, h, h, h as f32 / 2.0, color);
    }
}

pub fn pct_color(pct: u8) -> Color {
    if pct >= 90 {
        ERR
    } else if pct >= 75 {
        WARN
    } else {
        ACCENT
    }
}

/// Brand mark: medical cross with a lightning bolt (same mark as the splash video).
pub fn logo(d: &mut impl RaylibDraw, cx: i32, cy: i32, s: f32) {
    let (arm, half) = (13.0 * s, 4.6 * s);
    rbox(d, (cx as f32 - half) as i32, (cy as f32 - arm) as i32, (half * 2.0) as i32, (arm * 2.0) as i32, 2.0, ACCENT);
    rbox(d, (cx as f32 - arm) as i32, (cy as f32 - half) as i32, (arm * 2.0) as i32, (half * 2.0) as i32, 2.0, ACCENT);
    let p = |x: f32, y: f32| Vector2::new(cx as f32 + x * s * 0.14, cy as f32 + y * s * 0.14);
    let dark = rgb(6, 30, 22);
    // bolt, as two triangle fans (drawn in both windings so culling never hides it)
    for (a, b, c) in [
        ((14.0, -88.0), (-38.0, 10.0), (-6.0, 10.0)),
        ((14.0, -88.0), (-6.0, 10.0), (8.0, -16.0)),
        ((14.0, -88.0), (8.0, -16.0), (30.0, -88.0)),
        ((-6.0, 10.0), (-20.0, 88.0), (40.0, -16.0)),
        ((-6.0, 10.0), (40.0, -16.0), (8.0, -16.0)),
    ] {
        d.draw_triangle(p(a.0, a.1), p(b.0, b.1), p(c.0, c.1), dark);
        d.draw_triangle(p(a.0, a.1), p(c.0, c.1), p(b.0, b.1), dark);
    }
}

/// Wrap `s` to lines of at most `max_w` pixels (hard-breaks over-long words).
pub fn wrap(face: Face, s: &str, size: i32, max_w: i32) -> Vec<String> {
    let mut out = Vec::new();
    for para in s.lines() {
        if para.trim().is_empty() {
            out.push(String::new());
            continue;
        }
        let mut line = String::new();
        for word in para.split(' ') {
            let cand = if line.is_empty() { word.to_string() } else { format!("{line} {word}") };
            if text_w(face, &cand, size) <= max_w {
                line = cand;
                continue;
            }
            if !line.is_empty() {
                out.push(std::mem::take(&mut line));
            }
            let mut w = word.to_string();
            while text_w(face, &w, size) > max_w && w.chars().count() > 1 {
                let mut cut = w.clone();
                while text_w(face, &cut, size) > max_w && cut.chars().count() > 1 {
                    cut.pop();
                }
                out.push(cut.clone());
                w = w[cut.len()..].to_string();
            }
            line = w;
        }
        out.push(line);
    }
    out
}
