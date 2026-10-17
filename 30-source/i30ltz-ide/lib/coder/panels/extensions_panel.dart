import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../editor_model.dart';
import '../../services/extension_runtime_service.dart';
import '../dialogs/developer_publishing_dialog.dart';

class ExtensionsPanel extends StatefulWidget {
  const ExtensionsPanel({super.key});

  @override
  State<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends State<ExtensionsPanel> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedCategory = 'All';
  final ExtensionRuntimeService _service = ExtensionRuntimeService.instance;

  static const _categories = ['All', 'Languages', 'Linters', 'Themes', 'Snippets', 'Android', 'AI', 'Git', 'Tools'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<MarketplaceExtension> get _filteredMarketplace {
    return _service.marketplace.where((e) {
      final matchesQuery = _query.isEmpty ||
          e.name.toLowerCase().contains(_query.toLowerCase()) ||
          e.description.toLowerCase().contains(_query.toLowerCase()) ||
          e.tags.any((t) => t.toLowerCase().contains(_query.toLowerCase()));
      final matchesCategory = _selectedCategory == 'All' || e.category == _selectedCategory;
      return matchesQuery && matchesCategory;
    }).toList();
  }

  List<MarketplaceExtension> get _filteredInstalled {
    return _service.installed.where((e) {
      final matchesQuery = _query.isEmpty ||
          e.name.toLowerCase().contains(_query.toLowerCase()) ||
          e.description.toLowerCase().contains(_query.toLowerCase());
      return matchesQuery;
    }).toList();
  }

  int get _updateCount => _service.installed.where((e) => e.hasUpdate).length;

  void _install(MarketplaceExtension ext) async {
    await _service.installExtension(ext);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Installed & Activated ${ext.name} v${ext.version}'),
          duration: const Duration(seconds: 2),
          backgroundColor: SwarmColors.bgElevated,
        ),
      );
    }
  }

  void _uninstall(MarketplaceExtension ext) async {
    await _service.uninstallExtension(ext.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uninstalled ${ext.name}'),
          duration: const Duration(seconds: 2),
          backgroundColor: SwarmColors.bgElevated,
        ),
      );
    }
  }

  void _update(MarketplaceExtension ext) async {
    await _service.updateExtension(ext.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated ${ext.name} to v${ext.version}'),
          duration: const Duration(seconds: 2),
          backgroundColor: SwarmColors.bgElevated,
        ),
      );
    }
  }

  void _rollback(MarketplaceExtension ext, String targetVersion) async {
    await _service.rollbackVersion(ext.id, targetVersion);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rolled back ${ext.name} to v$targetVersion'),
          duration: const Duration(seconds: 2),
          backgroundColor: SwarmColors.bgElevated,
        ),
      );
    }
  }

  void _openPublishingPortal() {
    showDialog(
      context: context,
      builder: (ctx) => const DeveloperPublishingDialog(),
    );
  }

  void _showReviewsDialog(MarketplaceExtension ext) {
    final commentCtrl = TextEditingController();
    double rating = 5.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: SwarmColors.bgSurface,
          title: Row(
            children: [
              const Icon(Icons.rate_review_rounded, color: SwarmColors.accent, size: 18),
              const SizedBox(width: 8),
              Text('${ext.name} Reviews & Feedback', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary)),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Average Rating and Verified Publisher
                Row(
                  children: [
                    ...List.generate(
                        5,
                        (i) => Icon(
                              i < ext.rating.floor() ? Icons.star_rounded : Icons.star_half_rounded,
                              size: 16,
                              color: SwarmColors.agentAmber,
                            )),
                    const SizedBox(width: 8),
                    Text('${ext.rating.toStringAsFixed(1)} / 5.0 (${ext.reviews.length} reviews)', style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: SwarmColors.border),
                // Review List
                Expanded(
                  child: ext.reviews.isEmpty
                      ? const Center(child: Text('No reviews yet. Be the first to review!', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: ext.reviews.length,
                          separatorBuilder: (_, __) => const Divider(height: 12, color: SwarmColors.border),
                          itemBuilder: (context, index) {
                            final rev = ext.reviews[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(rev.author, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SwarmColors.accent)),
                                    const Spacer(),
                                    Row(
                                      children: List.generate(
                                        rev.rating.toInt(),
                                        (_) => const Icon(Icons.star_rounded, size: 11, color: SwarmColors.agentAmber),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(rev.comment, style: const TextStyle(fontSize: 11, color: SwarmColors.textPrimary)),
                              ],
                            );
                          },
                        ),
                ),
                const Divider(height: 1, color: SwarmColors.border),
                const SizedBox(height: 8),
                // Submit Form
                const Text('Leave a Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SwarmColors.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('Rating: ', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)),
                    ...[1, 2, 3, 4, 5].map((s) => IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          icon: Icon(s <= rating ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: SwarmColors.agentAmber),
                          onPressed: () => setDState(() => rating = s.toDouble()),
                        )),
                  ],
                ),
                TextField(
                  controller: commentCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11, color: SwarmColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Share your experience...',
                    hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 11),
                    filled: true,
                    fillColor: SwarmColors.bgElevated,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: SwarmColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.accent),
              onPressed: () {
                if (commentCtrl.text.trim().isNotEmpty) {
                  _service.submitReview(ext.id, rating, commentCtrl.text.trim());
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Submit Review', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar & Publisher Portal Button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search Marketplace & Extensions...',
                    hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 11),
                    prefixIcon: const Icon(Icons.search, size: 16, color: SwarmColors.textMuted),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            color: SwarmColors.textMuted,
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: SwarmColors.bgElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.publish_rounded, size: 14),
                label: const Text('Publish', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: SwarmColors.accent,
                  side: const BorderSide(color: SwarmColors.accent),
                ),
                onPressed: _openPublishingPortal,
              ),
            ],
          ),
        ),

        // Tabs
        Container(
          color: SwarmColors.bgSurface,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            labelColor: SwarmColors.accent,
            unselectedLabelColor: SwarmColors.textMuted,
            indicatorColor: SwarmColors.accent,
            indicatorWeight: 2,
            tabs: [
              const Tab(text: 'MARKETPLACE', height: 32),
              Tab(
                height: 32,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('INSTALLED (${_service.installed.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    if (_updateCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: SwarmColors.agentAmber, borderRadius: BorderRadius.circular(8)),
                        child: Text('$_updateCount', style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'RUNTIME LOGS', height: 32),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              // 1. Marketplace
              Column(
                children: [
                  // Category chips
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isSel = cat == _selectedCategory;
                        return FilterChip(
                          label: Text(cat, style: TextStyle(fontSize: 10, color: isSel ? Colors.black : SwarmColors.textSecondary, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                          selected: isSel,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: SwarmColors.bgElevated,
                          selectedColor: SwarmColors.accent,
                          checkmarkColor: Colors.black,
                          onSelected: (_) => setState(() => _selectedCategory = cat),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, color: SwarmColors.border),
                  // Marketplace list
                  Expanded(
                    child: _filteredMarketplace.isEmpty
                        ? const Center(child: Text('No matching extensions found', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)))
                        : ListView.builder(
                            itemCount: _filteredMarketplace.length,
                            itemBuilder: (context, index) {
                              final ext = _filteredMarketplace[index];
                              return _ExtensionCard(
                                ext: ext,
                                onInstall: _install,
                                onUninstall: _uninstall,
                                onUpdate: _update,
                                onRollback: _rollback,
                                onToggleAutoUpdate: (id) => _service.toggleAutoUpdate(id),
                                onShowReviews: () => _showReviewsDialog(ext),
                              );
                            },
                          ),
                  ),
                ],
              ),

              // 2. Installed
              _filteredInstalled.isEmpty
                  ? const Center(child: Text('No extensions installed', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)))
                  : ListView.builder(
                      itemCount: _filteredInstalled.length,
                      itemBuilder: (context, index) {
                        final ext = _filteredInstalled[index];
                        return _ExtensionCard(
                          ext: ext,
                          showManage: true,
                          onInstall: _install,
                          onUninstall: _uninstall,
                          onUpdate: _update,
                          onRollback: _rollback,
                          onToggleAutoUpdate: (id) => _service.toggleAutoUpdate(id),
                          onShowReviews: () => _showReviewsDialog(ext),
                        );
                      },
                    ),

              // 3. Runtime Logs
              Container(
                color: SwarmColors.bgBase,
                child: _service.runtimeLogs.isEmpty
                    ? const Center(child: Text('No runtime execution logs yet', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _service.runtimeLogs.length,
                        itemBuilder: (context, index) {
                          final log = _service.runtimeLogs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${log.timestamp.toIso8601String().substring(11, 19)}] ',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: SwarmColors.textDisabled),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: SwarmColors.accent.withAlpha(30), borderRadius: BorderRadius.circular(3)),
                                  child: Text(log.extensionId, style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: SwarmColors.accent)),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    log.message,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtensionCard extends StatefulWidget {
  final MarketplaceExtension ext;
  final bool showManage;
  final void Function(MarketplaceExtension) onInstall;
  final void Function(MarketplaceExtension) onUninstall;
  final void Function(MarketplaceExtension) onUpdate;
  final void Function(MarketplaceExtension, String) onRollback;
  final void Function(String) onToggleAutoUpdate;
  final VoidCallback onShowReviews;

  const _ExtensionCard({
    required this.ext,
    this.showManage = false,
    required this.onInstall,
    required this.onUninstall,
    required this.onUpdate,
    required this.onRollback,
    required this.onToggleAutoUpdate,
    required this.onShowReviews,
  });

  @override
  State<_ExtensionCard> createState() => _ExtensionCardState();
}

class _ExtensionCardState extends State<_ExtensionCard> {
  bool _changelogOpen = false;

  Color get _catColor {
    switch (widget.ext.category) {
      case 'Languages':
        return SwarmColors.accent;
      case 'Linters':
        return SwarmColors.agentAmber;
      case 'Themes':
        return Colors.purpleAccent;
      case 'Snippets':
        return SwarmColors.agentEmerald;
      case 'Android':
        return Colors.greenAccent;
      case 'AI':
        return Colors.cyanAccent;
      case 'Git':
        return Colors.orangeAccent;
      default:
        return SwarmColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.ext;
    final hasUpdate = ext.hasUpdate;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SwarmColors.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hasUpdate ? SwarmColors.agentAmber.withAlpha(120) : SwarmColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and badges
                Row(
                  children: [
                    Expanded(
                      child: Text(ext.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary), overflow: TextOverflow.ellipsis),
                    ),
                    if (ext.isVerifiedPublisher) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Verified official publisher',
                        child: Icon(Icons.verified, size: 14, color: SwarmColors.agentEmerald),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text('v${ext.version}', style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted, fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(ext.publisher, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                    const SizedBox(width: 8),
                    // Signature verification badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: ext.signatureStatus == 'verified_official'
                            ? SwarmColors.agentEmerald.withAlpha(30)
                            : ext.signatureStatus == 'verified_partner'
                                ? Colors.cyan.withAlpha(30)
                                : SwarmColors.agentAmber.withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        ext.signatureStatus == 'verified_official'
                            ? 'ED25519 SIGNED'
                            : ext.signatureStatus == 'verified_partner'
                                ? 'PARTNER KEY'
                                : 'COMMUNITY',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: ext.signatureStatus == 'verified_official'
                              ? SwarmColors.agentEmerald
                              : ext.signatureStatus == 'verified_partner'
                                  ? Colors.cyan
                                  : SwarmColors.agentAmber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(ext.description, style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                // Stats, category, actions
                Row(
                  children: [
                    InkWell(
                      onTap: widget.onShowReviews,
                      child: Row(
                        children: [
                          ...List.generate(
                              5,
                              (i) => Icon(
                                    i < ext.rating.floor() ? Icons.star_rounded : Icons.star_half_rounded,
                                    size: 11,
                                    color: SwarmColors.agentAmber,
                                  )),
                          const SizedBox(width: 4),
                          Text(ext.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.download, size: 10, color: SwarmColors.textMuted),
                    const SizedBox(width: 2),
                    Text('${(ext.installs / 1000).toStringAsFixed(1)}k', style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: _catColor.withAlpha(30), borderRadius: BorderRadius.circular(3)),
                      child: Text(ext.category, style: TextStyle(fontSize: 9, color: _catColor, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    // Action Buttons
                    if (!ext.isInstalled)
                      _ActionBtn(label: 'Install', color: SwarmColors.accent, onTap: () => widget.onInstall(ext))
                    else if (hasUpdate)
                      _ActionBtn(label: 'Update', color: SwarmColors.agentAmber, onTap: () => widget.onUpdate(ext))
                    else
                      _ActionBtn(label: 'Uninstall', color: SwarmColors.agentRose, onTap: () => widget.onUninstall(ext)),
                  ],
                ),
                // Version rollback and auto-update (installed only)
                if (ext.isInstalled && widget.showManage) ...[
                  const Divider(height: 16, color: SwarmColors.border),
                  Row(
                    children: [
                      if (ext.versionHistory.isNotEmpty) ...[
                        const Icon(Icons.history_rounded, size: 12, color: SwarmColors.textDisabled),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          onSelected: (v) => widget.onRollback(ext, v),
                          color: SwarmColors.bgElevated,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: SwarmColors.border)),
                          itemBuilder: (_) => ext.versionHistory.reversed
                              .map((v) => PopupMenuItem(
                                    value: v,
                                    height: 30,
                                    child: Text('Rollback to v$v', style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary)),
                                  ))
                              .toList(),
                          child: const Text('Rollback', style: TextStyle(fontSize: 10, color: SwarmColors.textDisabled, decoration: TextDecoration.underline)),
                        ),
                      ],
                      const SizedBox(width: 12),
                      // Auto-update toggle
                      InkWell(
                        onTap: () => widget.onToggleAutoUpdate(ext.id),
                        child: Row(
                          children: [
                            Icon(ext.autoUpdate ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 13, color: ext.autoUpdate ? SwarmColors.accent : SwarmColors.textDisabled),
                            const SizedBox(width: 4),
                            const Text('Auto-update', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (ext.changelog.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _changelogOpen = !_changelogOpen),
                          child: Row(
                            children: [
                              const Text('Changelog', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                              const SizedBox(width: 2),
                              Icon(_changelogOpen ? Icons.expand_less : Icons.expand_more, size: 12, color: SwarmColors.textMuted),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_changelogOpen && ext.changelog.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: SwarmColors.bgBase, borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('v${ext.version} — Release Notes', style: const TextStyle(fontSize: 10, color: SwarmColors.agentAmber, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(ext.changelog, style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary, height: 1.4)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(35),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withAlpha(100)),
          ),
          child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        ),
      );
}
