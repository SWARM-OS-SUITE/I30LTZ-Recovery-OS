# Legacy build (2026-09-25, "NIGHTFALL")
Original debootstrap build of I30LTZ Recovery OS (Ubuntu 24.04 + XFCE, optional LXQt),
restored from the sda7 backup. Kept as reference while the Debian live-build profile in
`40-iso-profile/` replaces it. Reusable: chroot/ stage scripts (recovery tools, AI setup,
SSE bridge), scripts/install-to-disk.sh, scripts/watchdog.sh, config/grub, config/systemd.
SSE bridge source lives in `30-source/mad-dr-ai/sse-server/`.
