# I30LTZ Recovery OS images
Copied 2026-10-12 from /mnt/Lucy/images/websitebackgrounds (SWARM's folder, read-only for Recovery work), resized to
<=1920x1080 JPG q85. Only art that fits Recovery OS: SWARM / Lucille-branded images were deliberately left out.

| File | Source | Use |
|---|---|---|
| dr-boltz.jpg | drbotlz4k.png | GRUB + syslinux boot splash (make-boot-splash.sh), nav banner in the Recovery console |
| wild-thing.jpg | wildthing.jpg | wallpaper (installed to /opt/i30ltz/images) |
| country-state-of-mind.jpg | countrystateofmind.jpeg | wallpaper |
| country-boy-can-survive.jpg | countryboycan survive.jpeg | wallpaper |

Left out on purpose: IDECODEBACKGROUND, thisisnowgaming, FALLENSOLDIER (all say "Lucille AI Core"/SWARM),
i320k3n.&i30ltz (login-form mock-up baked in), drbolt? (near-duplicate of drbotlz4k), droidbg (SWARM IDE art), and the rest.

`70-scripts/build.sh` copies this folder into the ISO at /opt/i30ltz/images and builds the boot splash from dr-boltz.jpg.

## Splash video (2026-10-12)
`splash/i30ltz-recovery-splash.mp4`: 7.0 s, 1920x1080, 30 fps, H.264 yuv420p, no audio, 1.7 MB. PC-doctor story: dead PC on a
patient monitor -> CLEAR! -> lightning shock -> heartbeat -> DR. I30LTZ / MAD AI -> drives scanned, boot repaired, data
recovered -> STABLE. `splash/i30ltz-recovery-splash-final.png` is the last frame, a review still only: it is NOT a ready GRUB/syslinux
fallback (the boot menu covers the lower half; syslinux is 640x480). The fallback needs its own top-half render at wiring time.
Re-render: `python3 splash/make_splash.py` (Pillow + ffmpeg; fonts-lato + fonts-hack at render time only).

## Status (2026-10-13)
Wired by `70-scripts/build.sh` (written + compiled, ISO NOT built or booted yet):
- `*.jpg` -> `/opt/i30ltz/images` (the Recovery console shows `dr-boltz.jpg` as the banner in its left navigation);
- `70-scripts/make-boot-splash.sh` renders the GRUB/syslinux boot-menu splash from `dr-boltz.jpg` (previewed with rsvg-convert only);
- `fonts/` -> `/opt/i30ltz/fonts`.
The splash VIDEO (`splash/`) is rendered but not wired: it waits for the user's approval (Plymouth cannot play video; it
would be played by mpv/ffplay at console start, with a static fallback for GRUB).
Findings for whoever wires the video: live-build 20250505 overlays `config/bootloaders/<name>/` on its defaults (cp -af); the boot menu covers
the lower half of the screen.

## Fonts (2026-10-12)
`fonts/` holds Lato (Regular, Bold) and Hack (Regular) with their licences. They are loaded at runtime by the Recovery
console (`30-source/i30ltz-recovery/src/ui.rs`) from `/opt/i30ltz/fonts` (staged by build.sh); the IDE bundles its own copies.
