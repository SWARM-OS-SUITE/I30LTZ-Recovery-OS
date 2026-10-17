import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../../theme/swarm_text_styles.dart';
import '../editor_model.dart';

class FileExplorerPanel extends StatefulWidget {
  final String? rootPath;
  final ValueChanged<String> onFileOpen;
  final String? activeFilePath;
  final VoidCallback? onOpenFolder;

  const FileExplorerPanel({
    super.key,
    this.rootPath,
    required this.onFileOpen,
    this.activeFilePath,
    this.onOpenFolder,
  });

  @override
  State<FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<FileExplorerPanel> {
  FileNode? _root;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.rootPath != null) _loadTree(widget.rootPath!);
  }

  @override
  void didUpdateWidget(FileExplorerPanel old) {
    super.didUpdateWidget(old);
    if (old.rootPath != widget.rootPath && widget.rootPath != null) {
      _loadTree(widget.rootPath!);
    }
  }

  Future<void> _loadTree(String path) async {
    setState(() => _loading = true);
    final node = await Future(() => FileNode.fromFileSystem(path));
    node.isExpanded = true;
    if (mounted) setState(() { _root = node; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(rootPath: widget.rootPath, onOpenFolder: widget.onOpenFolder, onRefresh: () {
          if (widget.rootPath != null) _loadTree(widget.rootPath!);
        }),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
              : widget.rootPath == null || _root == null
                  ? _EmptyState(onOpen: widget.onOpenFolder)
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: _root!.children
                          .map((n) => _FileNode(
                                node: n,
                                depth: 0,
                                onFileOpen: widget.onFileOpen,
                                activeFilePath: widget.activeFilePath,
                              ))
                          .toList(),
                    ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String? rootPath;
  final VoidCallback? onOpenFolder;
  final VoidCallback onRefresh;
  const _Header({this.rootPath, this.onOpenFolder, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      child: Row(
        children: [
          Text(
            rootPath != null ? rootPath!.split('/').last.toUpperCase() : 'EXPLORER',
            style: SwarmTextStyles.labelSmall.copyWith(color: SwarmColors.textMuted, fontSize: 10, letterSpacing: 1.2),
          ),
          const Spacer(),
          _IconBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New Folder', onTap: () {}),
          _IconBtn(icon: Icons.note_add_outlined, tooltip: 'New File', onTap: () {}),
          _IconBtn(icon: Icons.refresh, tooltip: 'Refresh', onTap: onRefresh),
          _IconBtn(icon: Icons.folder_open_rounded, tooltip: 'Open Folder', onTap: onOpenFolder ?? () {}),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 14, color: SwarmColors.textMuted),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onOpen;
  const _EmptyState({this.onOpen});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded, size: 48, color: SwarmColors.textDisabled),
            const SizedBox(height: 12),
            Text('No folder open', style: SwarmTextStyles.bodySmall.copyWith(color: SwarmColors.textMuted)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onOpen,
              child: const Text('Open Folder', style: TextStyle(color: SwarmColors.accent, fontSize: 12)),
            ),
          ],
        ),
      );
}

class _FileNode extends StatefulWidget {
  final FileNode node;
  final int depth;
  final ValueChanged<String> onFileOpen;
  final String? activeFilePath;

  const _FileNode({
    required this.node,
    required this.depth,
    required this.onFileOpen,
    this.activeFilePath,
  });

  @override
  State<_FileNode> createState() => _FileNodeState();
}

class _FileNodeState extends State<_FileNode> {
  bool _hovered = false;

  Color _iconColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart'         => const Color(0xFF54C5F8),
      'py'           => const Color(0xFFFFE873),
      'js' || 'mjs'  => const Color(0xFFF7DF1E),
      'ts' || 'tsx'  => const Color(0xFF3178C6),
      'kt' || 'kts'  => const Color(0xFF7F52FF),
      'java'         => const Color(0xFFF89820),
      'json'         => const Color(0xFFF59E0B),
      'yaml' || 'yml'=> const Color(0xFF84CC16),
      'md'           => const Color(0xFF9CA3AF),
      'sh' || 'bash' => const Color(0xFF22C55E),
      'cs'           => const Color(0xFF9B59B6),
      'cpp' || 'cc'  => const Color(0xFF00599C),
      'html'         => const Color(0xFFE34F26),
      'css'          => const Color(0xFF264DE4),
      'xml'          => const Color(0xFFFF6600),
      'gradle'       => const Color(0xFF02303A),
      'rs'           => const Color(0xFFDEA584),
      'go'           => const Color(0xFF00ADD8),
      _              => SwarmColors.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.activeFilePath == widget.node.path;
    final indent = widget.depth * 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {
              if (widget.node.isDir) {
                setState(() => widget.node.isExpanded = !widget.node.isExpanded);
              } else {
                widget.onFileOpen(widget.node.path);
              }
            },
            child: Container(
              height: 22,
              padding: EdgeInsets.only(left: 10 + indent, right: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? SwarmColors.accent.withValues(alpha: 0.12)
                    : _hovered
                        ? SwarmColors.bgHover
                        : Colors.transparent,
                border: isActive ? const Border(left: BorderSide(color: SwarmColors.accent, width: 2)) : null,
              ),
              child: Row(
                children: [
                  if (widget.node.isDir)
                    Icon(
                      widget.node.isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: SwarmColors.textMuted,
                    )
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 4),
                  Icon(
                    widget.node.isDir ? (widget.node.isExpanded ? Icons.folder_open : Icons.folder) : _fileIcon(widget.node.name),
                    size: 14,
                    color: widget.node.isDir ? SwarmColors.agentAmber : _iconColor(widget.node.name),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.node.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: isActive ? SwarmColors.textPrimary : SwarmColors.textSecondary,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.node.isDir && widget.node.isExpanded)
          ...widget.node.children.map((child) => _FileNode(
                node: child,
                depth: widget.depth + 1,
                onFileOpen: widget.onFileOpen,
                activeFilePath: widget.activeFilePath,
              )),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'kt' || 'java' || 'cs' || 'cpp' || 'c' || 'rs' || 'go' => Icons.code,
      'json' || 'yaml' || 'yml' || 'xml' || 'toml' => Icons.data_object,
      'md' || 'txt' || 'rst' => Icons.article_outlined,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      'html' || 'css' => Icons.web,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => Icons.image_outlined,
      'gradle' || 'kts' => Icons.build_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}
