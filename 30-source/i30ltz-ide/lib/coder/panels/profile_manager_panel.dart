import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/swarm_colors.dart';
import '../../services/settings_profile_service.dart';

class ProfileManagerPanel extends StatefulWidget {
  const ProfileManagerPanel({super.key});

  @override
  State<ProfileManagerPanel> createState() => _ProfileManagerPanelState();
}

class _ProfileManagerPanelState extends State<ProfileManagerPanel> {
  final SettingsProfileService _service = SettingsProfileService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _exportJson() {
    final json = _service.exportProfileJson(_service.activeProfile);
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile configuration JSON copied to clipboard'),
        backgroundColor: SwarmColors.bgElevated,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showImportDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SwarmColors.bgSurface,
        title: const Text('Import Profile JSON', style: TextStyle(color: SwarmColors.textPrimary, fontSize: 14)),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Paste profile JSON here...',
              hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 11),
              filled: true,
              fillColor: SwarmColors.bgBase,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: SwarmColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.accent),
            onPressed: () async {
              final ok = await _service.importProfileFromJson(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Profile imported successfully!' : 'Invalid profile JSON syntax'),
                    backgroundColor: ok ? SwarmColors.agentEmerald : SwarmColors.agentRose,
                  ),
                );
              }
            },
            child: const Text('Import & Activate', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _service.activeProfile;
    final profiles = _service.profiles;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.manage_accounts_rounded, color: SwarmColors.accent, size: 20),
            const SizedBox(width: 8),
            const Text('SETTINGS & PROFILE HUB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              tooltip: 'Import Profile JSON',
              color: SwarmColors.textSecondary,
              onPressed: _showImportDialog,
            ),
            IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 16),
              tooltip: 'Export Active Profile',
              color: SwarmColors.textSecondary,
              onPressed: _exportJson,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Profile Cards Grid / Carousel
        const Text('ENVIRONMENT PRESETS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SwarmColors.textDisabled, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        ...profiles.map((p) {
          final isSelected = p.id == active.id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? SwarmColors.accent.withAlpha(25) : SwarmColors.bgSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isSelected ? SwarmColors.accent : SwarmColors.border),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                p.id.contains('flutter')
                    ? Icons.flutter_dash
                    : p.id.contains('cpp')
                        ? Icons.memory
                        : p.id.contains('android')
                            ? Icons.android
                            : Icons.cloud,
                color: isSelected ? SwarmColors.accent : SwarmColors.textSecondary,
                size: 20,
              ),
              title: Row(
                children: [
                  Text(p.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? SwarmColors.accent : SwarmColors.textPrimary)),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: SwarmColors.accent, borderRadius: BorderRadius.circular(3)),
                      child: const Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(p.description, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
              trailing: isSelected
                  ? null
                  : TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => _service.selectProfile(p.id),
                      child: const Text('Activate', style: TextStyle(fontSize: 11, color: SwarmColors.textSecondary)),
                    ),
            ),
          );
        }),

        const Divider(height: 24, color: SwarmColors.border),
        const Text('ACTIVE PROFILE PREFERENCES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SwarmColors.textDisabled, letterSpacing: 1.1)),
        const SizedBox(height: 12),

        // Editor Tab Size
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Indentation Tab Size', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2 spaces', style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 4, label: Text('4 spaces', style: TextStyle(fontSize: 11))),
              ],
              selected: {active.tabSize},
              onSelectionChanged: (val) => _service.updateActiveProfile(active.copyWith(tabSize: val.first)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Editor Font Size
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Font Size (${active.fontSize.toStringAsFixed(1)} pt)', style: const TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
            Slider(
              value: active.fontSize,
              min: 10,
              max: 22,
              divisions: 24,
              activeColor: SwarmColors.accent,
              onChanged: (val) => _service.updateActiveProfile(active.copyWith(fontSize: val)),
            ),
          ],
        ),

        // Word Wrap
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Soft Word Wrap', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
          subtitle: const Text('Wrap long code lines inside the viewport', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          value: active.wordWrap,
          activeThumbColor: SwarmColors.accent,
          onChanged: (val) => _service.updateActiveProfile(active.copyWith(wordWrap: val)),
        ),

        // Line Numbers
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Line Numbers', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
          value: active.showLineNumbers,
          activeThumbColor: SwarmColors.accent,
          onChanged: (val) => _service.updateActiveProfile(active.copyWith(showLineNumbers: val)),
        ),

        // Format on Save
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Format On Save', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
          subtitle: const Text('Auto format code using language formatter', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          value: active.formatOnSave,
          activeThumbColor: SwarmColors.accent,
          onChanged: (val) => _service.updateActiveProfile(active.copyWith(formatOnSave: val)),
        ),

        // Git Blame Gutter
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('GitLens In-Editor Blame Annotations', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
          subtitle: const Text('Show author and commit date inline beside active line', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          value: active.showGitBlame,
          activeThumbColor: SwarmColors.accent,
          onChanged: (val) => _service.updateActiveProfile(active.copyWith(showGitBlame: val)),
        ),

        // Offline / Local-First Mode
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Offline / Local-First Mode', style: TextStyle(fontSize: 12, color: SwarmColors.textPrimary)),
          subtitle: const Text('Prioritize zero-network disk caches and disable outbound telemetry', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          value: active.offlineLocalFirst,
          activeThumbColor: SwarmColors.accent,
          onChanged: (val) => _service.updateActiveProfile(active.copyWith(offlineLocalFirst: val)),
        ),
      ],
    );
  }
}
