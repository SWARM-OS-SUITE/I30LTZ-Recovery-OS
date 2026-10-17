import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../accessibility.dart';

class AccessibilityPanel extends StatefulWidget {
  const AccessibilityPanel({super.key});

  @override
  State<AccessibilityPanel> createState() => _AccessibilityPanelState();
}

class _AccessibilityPanelState extends State<AccessibilityPanel> {
  final _a11y = AccessibilitySettings.instance;

  @override
  void initState() {
    super.initState();
    _a11y.addListener(_onChanged);
  }

  @override
  void dispose() {
    _a11y.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Font ─────────────────────────────────────────────────
        const _SectionLabel('EDITOR FONT'),
        _RowLabel('Font size', '${_a11y.fontSize.toStringAsFixed(1)} px'),
        Slider(
          value: _a11y.fontSize,
          min: 10, max: 24, divisions: 14,
          activeColor: SwarmColors.accent,
          inactiveColor: SwarmColors.border,
          label: '${_a11y.fontSize.toStringAsFixed(1)} px',
          onChanged: (v) => _a11y.setFontSize(double.parse(v.toStringAsFixed(1))),
        ),
        _RowLabel('Line height', '${_a11y.lineHeight.toStringAsFixed(0)} px'),
        Slider(
          value: _a11y.lineHeight,
          min: 16, max: 32, divisions: 8,
          activeColor: SwarmColors.agentCyan,
          inactiveColor: SwarmColors.border,
          label: '${_a11y.lineHeight.toStringAsFixed(0)} px',
          onChanged: (v) => _a11y.setLineHeight((v / 2).round() * 2.0),
        ),
        const SizedBox(height: 16),

        // ── Display ────────────────────────────────────────────────
        const _SectionLabel('DISPLAY'),
        _Toggle(
          label: 'High contrast',
          subtitle: 'Increases text/background contrast ratio',
          value: _a11y.highContrast,
          onChanged: _a11y.setHighContrast,
        ),
        _Toggle(
          label: 'Visible focus rings',
          subtitle: 'Shows accent border on focused widgets',
          value: _a11y.focusRings,
          onChanged: _a11y.setFocusRings,
        ),
        _Toggle(
          label: 'Reduce motion',
          subtitle: 'Disables animated transitions and pulsing effects',
          value: _a11y.reducedMotion,
          onChanged: _a11y.setReducedMotion,
        ),
        const SizedBox(height: 16),

        // ── Preview ────────────────────────────────────────────────
        const _SectionLabel('PREVIEW'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _a11y.highContrast ? Colors.black : SwarmColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _a11y.highContrast ? Colors.white : SwarmColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('void main() {', style: TextStyle(fontFamily: 'monospace', fontSize: _a11y.fontSize, height: _a11y.lineHeight / _a11y.fontSize, color: const Color(0xFFBB86FC))),
            Text("  print('Hello, Swarm OS!');", style: TextStyle(fontFamily: 'monospace', fontSize: _a11y.fontSize, height: _a11y.lineHeight / _a11y.fontSize, color: _a11y.highContrast ? Colors.white : SwarmColors.textPrimary)),
            Text('}', style: TextStyle(fontFamily: 'monospace', fontSize: _a11y.fontSize, height: _a11y.lineHeight / _a11y.fontSize, color: const Color(0xFFBB86FC))),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Reset ──────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _a11y.resetDefaults,
            icon: const Icon(Icons.restart_alt_rounded, size: 14),
            label: const Text('Reset to defaults', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: SwarmColors.textMuted, side: const BorderSide(color: SwarmColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(vertical: 8)),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Font and line height changes apply immediately to all open editors.', style: TextStyle(fontSize: 10, color: SwarmColors.textDisabled)),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: SwarmColors.textMuted, letterSpacing: 1.2)),
      );
}

class _RowLabel extends StatelessWidget {
  final String label, value;
  const _RowLabel(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.accent, fontWeight: FontWeight.bold)),
        ]),
      );
}

class _Toggle extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
              Text(subtitle, style: const TextStyle(fontSize: 10, color: SwarmColors.textDisabled)),
            ]),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: SwarmColors.accent,
            trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? SwarmColors.accent.withValues(alpha: 0.3) : SwarmColors.bgElevated),
          ),
        ]),
      );
}
