import 'package:flutter/material.dart';
import '../../services/hot_reload_service.dart';
import '../../theme/swarm_colors.dart';

class HotReloadToolbarButton extends StatefulWidget {
  final bool compact;
  final String? projectPath;

  const HotReloadToolbarButton({
    super.key,
    this.compact = false,
    this.projectPath,
  });

  @override
  State<HotReloadToolbarButton> createState() => _HotReloadToolbarButtonState();
}

class _HotReloadToolbarButtonState extends State<HotReloadToolbarButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerReload() async {
    _animCtrl.repeat();
    final svc = HotReloadService.instance;
    final res = await svc.hotReload(projectPath: widget.projectPath);
    if (!mounted) return;
    _animCtrl.stop();
    _animCtrl.reset();
    _showFeedback(res);
  }

  Future<void> _triggerRestart() async {
    _animCtrl.repeat();
    final svc = HotReloadService.instance;
    final res = await svc.hotRestart(projectPath: widget.projectPath);
    if (!mounted) return;
    _animCtrl.stop();
    _animCtrl.reset();
    _showFeedback(res);
  }

  void _showFeedback(HotReloadResult res) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 36, left: 16, right: 16),
        duration: const Duration(seconds: 3),
        backgroundColor: res.success ? const Color(0xFF0D2818) : const Color(0xFF261214),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: res.success ? SwarmColors.agentEmerald : SwarmColors.agentRose,
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(
              res.success ? Icons.bolt_rounded : Icons.info_outline_rounded,
              color: res.success ? SwarmColors.agentEmerald : SwarmColors.agentAmber,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res.message,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: res.success ? SwarmColors.agentEmerald : SwarmColors.textPrimary,
                    ),
                  ),
                  if (res.details != null)
                    Text(
                      res.details!,
                      style: const TextStyle(fontSize: 11, color: SwarmColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = HotReloadService.instance;

    return ValueListenableBuilder<HotReloadStatus>(
      valueListenable: svc.status,
      builder: (context, status, _) {
        final isBusy = svc.isBusy;
        final isSuccess = status == HotReloadStatus.success;

        final Color primaryColor = isSuccess
            ? SwarmColors.agentEmerald
            : isBusy
                ? SwarmColors.agentCyan
                : const Color(0xFFFFB020); // Vivid Amber Gold for Hot Reload

        return Container(
          height: widget.compact ? 20 : 24,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              if (isBusy || isSuccess)
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Main Hot Reload Button ──────────────────────────────────────
              Tooltip(
                message: 'Hot Reload (Ctrl+R / r)\nQuickly reloads code into active Flutter session',
                waitDuration: const Duration(milliseconds: 300),
                child: InkWell(
                  onTap: isBusy ? null : _triggerReload,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 6 : 8,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RotationTransition(
                          turns: _animCtrl,
                          child: Icon(
                            Icons.bolt_rounded,
                            size: widget.compact ? 12 : 14,
                            color: primaryColor,
                          ),
                        ),
                        if (!widget.compact) ...[
                          const SizedBox(width: 4),
                          Text(
                            isBusy ? 'RELOADING' : 'HOT RELOAD',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: primaryColor,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Separator line
              Container(
                width: 1,
                height: widget.compact ? 12 : 16,
                color: primaryColor.withValues(alpha: 0.3),
              ),

              // ── Hot Restart Button ──────────────────────────────────────────
              Tooltip(
                message: 'Hot Restart (Ctrl+Shift+R / R)\nRestarts the app state completely',
                waitDuration: const Duration(milliseconds: 300),
                child: InkWell(
                  onTap: isBusy ? null : _triggerRestart,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 4 : 6,
                      vertical: 2,
                    ),
                    child: Icon(
                      Icons.restart_alt_rounded,
                      size: widget.compact ? 12 : 14,
                      color: primaryColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
