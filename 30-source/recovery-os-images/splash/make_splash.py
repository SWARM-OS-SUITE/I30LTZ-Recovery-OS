#!/usr/bin/env python3
"""I30LTZ Recovery OS boot splash video: "the MAD DR. revives a dead PC".

Story (7 s): a dead PC on a patient monitor (fibrillation -> flatline) -> "CLEAR!" -> lightning shock ->
heartbeat returns -> DR. I30LTZ / MAD AI title -> drive scan, boot repair and data recovery finish -> STABLE.

Renders 1920x1080 @ 30 fps with Pillow and pipes raw frames to ffmpeg (H.264, yuv420p, no audio).
  python3 make_splash.py                         -> i30ltz-recovery-splash.mp4 + i30ltz-recovery-splash-final.png
  python3 make_splash.py --stills 2.0,4.0 --out-dir DIR   -> PNG stills only (for review)
Fonts are needed at render time only (not at boot): Lato Black + Hack Bold (Debian: fonts-lato, fonts-hack).
Name rule: the AI is "MAD AI" (never "MAD IT").
"""
import argparse
import math
import os
import random
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
DURATION = 7.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_MP4 = "i30ltz-recovery-splash.mp4"
OUT_PNG = "i30ltz-recovery-splash-final.png"

FONT_TITLE = "/usr/share/fonts/truetype/lato/Lato-Black.ttf"
FONT_MONO = "/usr/share/fonts/truetype/hack/Hack-Bold.ttf"

BG = (4, 8, 12)
GREEN = (57, 255, 136)
CYAN = (34, 211, 238)
MAGENTA = (255, 43, 214)
RED = (255, 52, 72)
AMBER = (255, 170, 40)
WHITE = (236, 255, 246)
DIM = (80, 130, 110)

# Timeline (seconds)
T_FLAT = 1.55     # fibrillation -> flatline
T_CLEAR = 1.75    # "CLEAR!" + defib charged
T_SHOCK = 2.35    # lightning, flash, heart restarts
T_TITLE = 2.9     # DR. I30LTZ wipes in
T_MAD = 3.45      # MAD AI glitches in
T_SUB = 3.9       # subtitle types
T_STATUS = 4.3    # repair log starts
T_DONE = 6.2      # recovery 100%, STABLE; hold to the end

# Layout
CX = W // 2
MON = (770, 130, 1150, 370)            # monitor bezel (the patient)
SCREEN_C = (CX, (MON[1] + MON[3]) // 2)
TITLE_Y, MAD_Y, SUB_Y = 548, 672, 762
ECG_Y, ECG_AMP = 880, 60
SWEEP = 960.0                          # ECG px per second
BEAT_PX = 620.0                        # px between heartbeats (~93 bpm)
ECG_GAP = 70                           # erased gap ahead of the sweep head

_fonts = {}


def font(path, size):
    key = (path, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, size)
    return _fonts[key]


def scale(c, a):
    """Fade a colour; the fx layer is additive light, so darker == more transparent."""
    a = max(0.0, min(1.0, a))
    return tuple(int(v * a) for v in c)


def mix(c1, c2, k):
    k = max(0.0, min(1.0, k))
    return tuple(int(a + (b - a) * k) for a, b in zip(c1, c2))


def ramp(t, t0, dur):
    return max(0.0, min(1.0, (t - t0) / dur))


def ease(x):
    return x * x * (3 - 2 * x)


# ── Background: monitor grid, CRT scanlines, vignette ──────────────────────
def make_background():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    for x in range(0, W, 40):
        d.line([(x, 0), (x, H)], fill=(14, 44, 32) if x % 200 == 0 else (9, 24, 19))
    for y in range(0, H, 40):
        d.line([(0, y), (W, y)], fill=(14, 44, 32) if y % 200 == 0 else (9, 24, 19))
    for y in range(0, H, 3):
        d.line([(0, y), (W, y)], fill=(2, 5, 7))
    vignette = Image.radial_gradient("L").resize((W, H), Image.BILINEAR)
    vignette = vignette.point(lambda v: min(255, max(0, int((v - 70) * 1.25))))
    return Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), img, vignette)


# ── ECG (the PC's heartbeat) ───────────────────────────────────────────────
_rng = random.Random(7)
_vf = [_rng.uniform(-1, 1) for _ in range(8192)]
S_RESTART = (T_SHOCK + 0.12) * SWEEP


def ecg_state(s):
    t = s / SWEEP
    if t < T_FLAT:
        return "vf"
    if s < S_RESTART:
        return "flat"
    return "ok"


def pqrst(p):
    v = 0.12 * math.exp(-((p - 0.14) / 0.035) ** 2)    # P
    v -= 0.14 * math.exp(-((p - 0.235) / 0.009) ** 2)  # Q
    v += 1.00 * math.exp(-((p - 0.255) / 0.009) ** 2)  # R
    v -= 0.32 * math.exp(-((p - 0.276) / 0.010) ** 2)  # S
    v += 0.24 * math.exp(-((p - 0.47) / 0.055) ** 2)   # T
    return v


def beat_phase(s):
    return ((s - S_RESTART) / BEAT_PX + 0.62) % 1.0


def ecg_value(s):
    st = ecg_state(s)
    if st == "vf":
        i, f = divmod(s / 6.0, 1.0)
        i = int(i)
        jit = _vf[i % 8192] * (1 - f) + _vf[(i + 1) % 8192] * f
        return (0.42 * math.sin(s * 0.045) + 0.28 * math.sin(s * 0.11 + 1.3)
                + 0.18 * math.sin(s * 0.027 + 0.5) + 0.25 * jit)
    if st == "flat":
        return _vf[int(s) % 8192] * 0.015
    return pqrst(beat_phase(s))


ECG_COLORS = {"vf": (255, 80, 60), "flat": RED, "ok": GREEN}


def draw_ecg(d, t):
    head = t * SWEEP
    span = W - ECG_GAP
    s = max(0.0, head - span)
    prev = None
    while s <= head:
        x = s % W
        y = ECG_Y - ECG_AMP * ecg_value(s)
        if prev is not None and x > prev[0]:
            age = (head - s) / span
            col = scale(ECG_COLORS[ecg_state(s)], 0.4 + 0.6 * (1 - age))
            d.line([prev, (x, y)], fill=col, width=4)
        prev = (x, y)
        s += 2.0
    hx = head % W
    hy = ECG_Y - ECG_AMP * ecg_value(head)
    d.ellipse((hx - 7, hy - 7, hx + 7, hy + 7), fill=WHITE)


def heart_pulse(t):
    """1.0 right after an R spike passes the sweep head, decaying; 0 before the restart."""
    head = t * SWEEP
    if head < S_RESTART:
        return 0.0
    since = ((beat_phase(head) - 0.255) % 1.0) * BEAT_PX / SWEEP
    return math.exp(-since * 5.0)


# ── The patient: a PC monitor ──────────────────────────────────────────────
def draw_monitor(d, color, a):
    c = scale(color, a)
    d.rounded_rectangle(MON, radius=20, outline=c, width=7)
    d.rounded_rectangle((MON[0] + 18, MON[1] + 18, MON[2] - 18, MON[3] - 18),
                        radius=8, outline=scale(color, a * 0.35), width=2)
    b = MON[3]
    d.polygon([(CX - 30, b), (CX + 30, b), (CX + 46, b + 40), (CX - 46, b + 40)], outline=c, width=6)
    d.rounded_rectangle((CX - 120, b + 40, CX + 120, b + 56), radius=8, outline=c, width=6)


def draw_dead_face(d, a, t):
    c = scale(RED, a)
    cx, cy = SCREEN_C
    for ex in (cx - 62, cx + 62):
        ey, r = cy - 28, 22
        d.line([(ex - r, ey - r), (ex + r, ey + r)], fill=c, width=8)
        d.line([(ex - r, ey + r), (ex + r, ey - r)], fill=c, width=8)
    pts = [(cx - 64 + i * 8.5, cy + 46 + 7 * math.sin(i * 1.2 + t * 14)) for i in range(16)]
    d.line(pts, fill=c, width=6)


BOLT = [(14, -88), (-38, 10), (-6, 10), (-20, 88), (40, -16), (8, -16), (30, -88)]


def draw_cross_bolt(d, a, k, pulse):
    """Medical cross with the I30LTZ lightning bolt; k = scale-in 0..1."""
    if k < 0.15 or a <= 0:
        return
    cx, cy = SCREEN_C
    sc = k * (1 + 0.05 * pulse) * 0.82
    arm, half = 96 * sc, 32 * sc
    cg = scale(mix(GREEN, WHITE, pulse * 0.45), a)
    fill = scale(GREEN, a * 0.22)
    d.rounded_rectangle((cx - half, cy - arm, cx + half, cy + arm), radius=8 * sc, fill=fill, outline=cg, width=6)
    d.rounded_rectangle((cx - arm, cy - half, cx + arm, cy + half), radius=8 * sc, fill=fill, outline=cg, width=6)
    d.rectangle((cx - half + 5, cy - half + 5, cx + half - 5, cy + half - 5), fill=fill)
    pts = [(cx + x * sc, cy + y * sc) for x, y in BOLT]
    d.polygon(pts, fill=scale(MAGENTA, a), outline=scale(WHITE, a), width=3)


def draw_lightning(d, rng, a):
    """Defib shock: a jagged bolt from the top edge into the monitor, with branches."""
    def path(x0, y0, x1, y1, rough, depth):
        pts = [(x0, y0), (x1, y1)]
        for _ in range(depth):
            nxt = [pts[0]]
            for p, q in zip(pts, pts[1:]):
                mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
                nxt += [(mx + rng.uniform(-rough, rough), my), q]
            pts, rough = nxt, rough * 0.55
        return pts

    main = path(CX + rng.uniform(-200, 200), -10, CX, MON[1] - 4, 120, 6)
    branches = [path(*main[i], main[i][0] + rng.uniform(-260, 260), main[i][1] + rng.uniform(60, 160), 50, 4)
                for i in rng.sample(range(8, len(main) - 8), 3)]
    for pts, w in [(main, 1.0)] + [(b, 0.5) for b in branches]:
        d.line(pts, fill=scale(CYAN, a), width=int(14 * w))
        d.line(pts, fill=scale(WHITE, a), width=max(2, int(5 * w)))


# ── Text layers (pre-rendered masks) ───────────────────────────────────────
def text_mask(text, fnt, cx, cy, tracking=0):
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    if tracking == 0:
        d.text((cx, cy), text, font=fnt, fill=255, anchor="mm")
    else:
        widths = [fnt.getlength(ch) for ch in text]
        x = cx - (sum(widths) + tracking * (len(text) - 1)) / 2
        for ch, w in zip(text, widths):
            d.text((x, cy), ch, font=fnt, fill=255, anchor="lm")
            x += w + tracking
    return m, m.getbbox()


def paste_mask(fx, mask, bbox, color, a, x_cut=None):
    x0, y0, x1, y1 = bbox
    if x_cut is not None:
        x1 = min(x1, int(x_cut))
    if x1 <= x0 or a <= 0:
        return
    fx.paste(scale(color, a), (x0, y0, x1, y1), mask.crop((x0, y0, x1, y1)))


def paste_rgb_split(fx, mask, bbox, color, a, o):
    """Glitch: shift the red and blue parts of the colour apart by o px."""
    x0, y0, x1, y1 = bbox
    box = (x0 - 60, y0 - 10, x1 + 60, y1 + 10)
    m = mask.crop(box)
    shifted = [ImageChops.offset(m, dx, 0) for dx in (-o, 0, o)]
    chans = [s.point(lambda v, k=c * a / 255: int(v * k)) for s, c in zip(shifted, color)]
    layer = Image.merge("RGB", chans)
    alpha = ImageChops.lighter(ImageChops.lighter(chans[0], chans[1]), chans[2])
    fx.paste(layer, box[:2], alpha.point(lambda v: 255 if v else 0))


# ── HUD, repair log, progress ──────────────────────────────────────────────
TASKS = [("scanning drives", 0.0), ("repairing boot + partitions", 0.6), ("recovering data", 1.2)]


def progress(t):
    return ease(ramp(t, T_STATUS + 0.2, T_DONE - T_STATUS - 0.2))


def draw_hud(d, t):
    a = ease(ramp(t, 0.1, 0.5))
    blink = int(t * 4) % 2 == 0
    alive = t >= T_SHOCK
    prog = progress(t)
    m24, m20 = font(FONT_MONO, 24), font(FONT_MONO, 20)
    d.text((60, 52), "I30LTZ RECOVERY OS", font=font(FONT_MONO, 28), fill=scale(GREEN, a), anchor="lm")
    if alive:
        d.text((60, 90), "DR. I30LTZ ON CALL  ·  PATIENT PC-01", font=m24, fill=scale(CYAN, a), anchor="lm")
    else:
        d.text((60, 90), "CODE BLUE  ·  PATIENT PC-01", font=m24, fill=scale(RED, a * (1 if blink else 0.35)), anchor="lm")
    d.text((60, 124), "PC & DATA RECOVERY UNIT", font=m20, fill=scale(DIM, a), anchor="lm")

    if t < T_FLAT:
        hr = ("VF", RED)
    elif not alive:
        hr = ("000", RED)
    else:
        hr = ("072", GREEN)
    cool = ramp(t, T_STATUS, 1.2)
    cpu = ("98°C", RED) if cool == 0 else (f"{int(98 - 57 * ease(cool))}°C", GREEN if cool >= 1 else AMBER)
    disk = ("OK", GREEN) if t >= T_STATUS + TASKS[1][1] + 0.45 else ("SMART FAIL", RED)
    if prog <= 0:
        data = ("LOST", RED)
    elif prog < 1:
        data = (f"{int(prog * 100)}%", AMBER)
    else:
        data = ("RECOVERED", GREEN)
    if not alive:
        status = ("CRITICAL", RED if blink else scale(RED, 0.35))
    elif t < T_DONE:
        status = ("RECOVERING", AMBER)
    else:
        status = ("STABLE", GREEN)
    rows = [("HR", hr), ("CPU", cpu), ("DISK", disk), ("DATA", data), ("STATUS", status)]
    for i, (label, (val, col)) in enumerate(rows):
        y = 52 + i * 34
        d.text((1500, y), label, font=m24, fill=scale(DIM, a), anchor="lm")
        d.text((1860, y), val, font=m24, fill=scale(col, a), anchor="rm")


def draw_repair_log(d, t):
    if t < T_STATUS:
        return
    m24 = font(FONT_MONO, 24)
    prog = progress(t)
    for i, (name, off) in enumerate(TASKS):
        start = T_STATUS + off
        if t < start:
            continue
        base = f"> {name} ".ljust(36, ".") + " "
        n = int(len(base) * ramp(t, start, 0.35))
        y = 952 + i * 34
        d.text((110, y), base[:n], font=m24, fill=scale(GREEN, 0.8), anchor="lm")
        if n < len(base):
            if int(t * 8) % 2 == 0:
                cx = 110 + m24.getlength(base[:n])
                d.rectangle((cx + 2, y - 11, cx + 14, y + 11), fill=GREEN)
            continue
        if t < start + 0.45:
            continue
        if i < 2:
            res, col = "OK", GREEN
        else:
            res, col = f"{int(prog * 100)}%", (GREEN if prog >= 1 else AMBER)
        d.text((110 + m24.getlength(base), y), res, font=m24, fill=col, anchor="lm")

    # progress bar
    a = ease(ramp(t, T_STATUS, 0.3))
    done = prog >= 1
    d.text((1180, 952), "RECOVERY COMPLETE" if done else "DATA RECOVERY", font=m24,
           fill=scale(GREEN if done else CYAN, a), anchor="lm")
    d.text((1810, 952), f"{int(prog * 100)}%", font=m24, fill=scale(GREEN if done else CYAN, a), anchor="rm")
    x0, y0, x1, y1 = 1180, 980, 1810, 1004
    d.rectangle((x0, y0, x1, y1), outline=scale(CYAN, a), width=2)
    fill_to = x0 + 5 + (x1 - x0 - 10) * prog
    bx = x0 + 5
    while bx + 12 <= fill_to:
        d.rectangle((bx, y0 + 5, bx + 12, y1 - 5), fill=GREEN)
        bx += 16


# ── Compositing ────────────────────────────────────────────────────────────
def bloom(base, fx):
    small = fx.resize((W // 2, H // 2), Image.BILINEAR)
    g1 = small.filter(ImageFilter.GaussianBlur(4)).resize((W, H), Image.BILINEAR)
    g2 = small.resize((W // 4, H // 4), Image.BILINEAR).filter(ImageFilter.GaussianBlur(9)).resize((W, H), Image.BILINEAR)
    out = ImageChops.add(base, fx)
    out = ImageChops.screen(out, g1)
    return ImageChops.screen(out, g2)


def slice_glitch(img, rng, n, amp):
    for _ in range(n):
        y0 = rng.randrange(0, H - 40)
        h = rng.randrange(6, 40)
        strip = img.crop((0, y0, W, y0 + h))
        img.paste(strip, (rng.randint(-amp, amp), y0))
    return img


class Splash:
    def __init__(self):
        for f in (FONT_TITLE, FONT_MONO):
            if not os.path.exists(f):
                sys.exit(f"missing font {f} (install fonts-lato / fonts-hack)")
        self.bg = make_background()
        self.title, self.title_bb = text_mask("DR. I30LTZ", font(FONT_TITLE, 168), CX, TITLE_Y)
        self.mad, self.mad_bb = text_mask("MAD AI", font(FONT_TITLE, 104), CX, MAD_Y, tracking=22)
        self.clear, self.clear_bb = text_mask("CLEAR!", font(FONT_TITLE, 150), CX, TITLE_Y + 10)
        self.sub_text = "RECOVERY OS  ·  PC & DATA RECOVERY"
        sub_font = font(FONT_MONO, 38)
        self.sub_x = CX - sub_font.getlength(self.sub_text) / 2

    def frame(self, i):
        t = i / FPS
        rng = random.Random(i * 7919 + 13)
        fx = Image.new("RGB", (W, H), (0, 0, 0))
        d = ImageDraw.Draw(fx)
        alive = t >= T_SHOCK
        pulse = heart_pulse(t)

        # patient monitor
        if not alive:
            a = ease(ramp(t, 0.0, 0.4)) * (0.75 + 0.25 * math.sin(t * 37))
            draw_monitor(d, RED, a)
            draw_dead_face(d, a, t)
        else:
            k = ease(ramp(t, T_SHOCK + 0.08, 0.35))
            draw_monitor(d, mix(WHITE, GREEN, k), 0.85 + 0.15 * pulse)
            draw_cross_bolt(d, 1.0, k, pulse)

        draw_ecg(d, t)
        draw_hud(d, t)

        # CLEAR! (defib charged)
        if T_CLEAR <= t < T_SHOCK and int(t * 6) % 2 == 0:
            paste_mask(fx, self.clear, self.clear_bb, RED, 1.0)
            d.text((CX, TITLE_Y + 110), "DEFIB CHARGED  ·  360 J", font=font(FONT_MONO, 30), fill=AMBER, anchor="mm")

        # lightning
        if T_SHOCK - 0.05 <= t < T_SHOCK + 0.22:
            draw_lightning(d, rng, 1.0 - 0.6 * ramp(t, T_SHOCK, 0.22))

        # DR. I30LTZ: scan wipe left -> right
        if t >= T_TITLE:
            k = ease(ramp(t, T_TITLE, 0.55))
            x0, y0, x1, y1 = self.title_bb
            edge = x0 + k * (x1 - x0 + 40)
            paste_mask(fx, self.title, self.title_bb, (222, 255, 234), 0.9 + 0.1 * pulse, x_cut=edge)
            if k < 1:
                d.rectangle((edge - 2, y0 - 14, edge + 2, y1 + 14), fill=CYAN)

        # MAD AI: glitches in, stray glitches later, clean at the end
        if t >= T_MAD:
            g = 1.0 - ramp(t, T_MAD, 0.45)
            blip = any(b <= t < b + 0.07 for b in (5.25, 5.95))
            if g > 0 or blip:
                o = rng.randint(4, 26) if blip else int(g * rng.randint(6, 30))
                if g < 0.15 or rng.random() > 0.25:
                    paste_rgb_split(fx, self.mad, self.mad_bb, MAGENTA, 1.0, o)
            else:
                paste_mask(fx, self.mad, self.mad_bb, MAGENTA, 0.92 + 0.08 * pulse)

        # subtitle typing
        if t >= T_SUB:
            sub_font = font(FONT_MONO, 38)
            n = int(len(self.sub_text) * ramp(t, T_SUB, 0.6))
            d.text((self.sub_x, SUB_Y), self.sub_text[:n], font=sub_font, fill=CYAN, anchor="lm")
            if n < len(self.sub_text) and int(t * 8) % 2 == 0:
                cx = self.sub_x + sub_font.getlength(self.sub_text[:n])
                d.rectangle((cx + 3, SUB_Y - 18, cx + 21, SUB_Y + 18), fill=CYAN)

        draw_repair_log(d, t)

        out = bloom(self.bg, fx)

        # shock: flash, shake, tearing
        if T_SHOCK <= t < T_SHOCK + 0.35:
            k = ramp(t, T_SHOCK, 0.35)
            amp = int(14 * (1 - k))
            out = slice_glitch(out, rng, 6, 50)
            if amp:
                out = ImageChops.offset(out, rng.randint(-amp, amp), rng.randint(-amp, amp))
            out = Image.blend(out, Image.new("RGB", (W, H), (235, 250, 255)), 0.9 * (1 - k) ** 2)
        elif T_MAD <= t < T_MAD + 0.2 or any(b <= t < b + 0.07 for b in (5.25, 5.95)):
            out = slice_glitch(out, rng, 3, 24)
        return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out-dir", default=HERE)
    ap.add_argument("--stills", help="comma-separated times in seconds; writes PNGs only")
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    sp = Splash()
    n = int(round(DURATION * FPS))

    if args.stills:
        for s in args.stills.split(","):
            i = min(n - 1, int(round(float(s) * FPS)))
            p = os.path.join(args.out_dir, f"still-{float(s):05.2f}s.png")
            sp.frame(i).save(p)
            print(p)
        return

    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found")
    mp4 = os.path.join(args.out_dir, OUT_MP4)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
           "-movflags", "+faststart", "-an", mp4]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    last = None
    for i in range(n):
        last = sp.frame(i)
        proc.stdin.write(last.tobytes())
        if i % 30 == 0:
            print(f"frame {i}/{n}", file=sys.stderr)
    proc.stdin.close()
    if proc.wait() != 0:
        sys.exit("ffmpeg failed")
    last.save(os.path.join(args.out_dir, OUT_PNG))
    print(mp4)
    print(os.path.join(args.out_dir, OUT_PNG))


if __name__ == "__main__":
    main()
