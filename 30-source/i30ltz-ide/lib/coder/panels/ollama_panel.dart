import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../../theme/swarm_text_styles.dart';

// ── Ollama REST API on localhost:11434 ────────────────────────────────────────
const _base = 'http://localhost:11434';

class _OllamaModel {
  final String name;
  final int sizeBytes;
  final String modifiedAt;
  final String family;
  final String paramSize;
  final String quantLevel;

  _OllamaModel({
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    this.family = '',
    this.paramSize = '',
    this.quantLevel = '',
  });

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / 1024 / 1024).toStringAsFixed(0)} MB';
    return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  factory _OllamaModel.fromJson(Map<String, dynamic> j) => _OllamaModel(
        name: j['name'] as String? ?? '',
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        modifiedAt: j['modified_at'] as String? ?? '',
        family: j['details']?['family'] as String? ?? '',
        paramSize: j['details']?['parameter_size'] as String? ?? '',
        quantLevel: j['details']?['quantization_level'] as String? ?? '',
      );
}

// ── Curated pull catalog (<=7B only: Recovery OS hard limit, iGPU / shared RAM) ─────────────────────
class _CatalogEntry {
  final String modelId;   // ollama pull name
  final String label;     // display name
  final String size;      // approximate on-disk size
  final String desc;
  final Color accent;

  const _CatalogEntry({
    required this.modelId,
    required this.label,
    required this.size,
    required this.desc,
    required this.accent,
  });
}

const _catalog = [
  // ── Tiny / always-on ─────────────────────────────────────────────────────
  _CatalogEntry(modelId: 'llama3.2:1b',        label: 'Llama 3.2 1B',          size: '1.3 GB', desc: 'Ultra-fast edge responder. Good for quick Q&A and lightweight autocomplete.', accent: Color(0xFF4CAF50)),
  _CatalogEntry(modelId: 'llama3.2:3b',        label: 'Llama 3.2 3B',          size: '2.0 GB', desc: 'Meta flagship 3B — strong chat and reasoning for its size.', accent: Color(0xFF4CAF50)),
  _CatalogEntry(modelId: 'phi3.5-mini',        label: 'Phi-3.5 Mini (3.8B)',    size: '2.2 GB', desc: 'Microsoft Phi — punches above its weight on coding and math.', accent: Color(0xFF2196F3)),
  _CatalogEntry(modelId: 'gemma2:2b',          label: 'Gemma 2 2B',             size: '1.6 GB', desc: 'Google Gemma 2 — compact and fast for general chat.', accent: Color(0xFFF48FB1)),
  // ── 7B tier ───────────────────────────────────────────────────────────────
  _CatalogEntry(modelId: 'qwen2.5:7b',         label: 'Qwen 2.5 7B',            size: '4.7 GB', desc: 'Alibaba generalist — excellent instruction following and multilingual.', accent: Color(0xFFFF9800)),
  _CatalogEntry(modelId: 'qwen2.5-coder:7b',   label: 'Qwen 2.5 Coder 7B',     size: '4.7 GB', desc: 'Best-in-class 7B code model. Beats CodeLlama 34B on many benchmarks.', accent: Color(0xFFFF9800)),
  _CatalogEntry(modelId: 'deepseek-r1:7b',     label: 'DeepSeek R1 7B',         size: '4.7 GB', desc: 'DeepSeek R1 reasoning distilled into 7B. Chain-of-thought coding and math.', accent: Color(0xFF00BCD4)),
  _CatalogEntry(modelId: 'mistral:7b',         label: 'Mistral 7B',             size: '4.1 GB', desc: 'European flagship 7B — fast, efficient, great for coding and dialogue.', accent: Color(0xFF9C27B0)),
  _CatalogEntry(modelId: 'codellama:7b',       label: 'CodeLlama 7B',           size: '3.8 GB', desc: 'Meta code infill specialist — FIM, fill-in-middle, Python/C++/Java.', accent: Color(0xFF3F51B5)),
  _CatalogEntry(modelId: 'gemma3:4b',          label: 'Gemma 3 4B',             size: '2.5 GB', desc: 'Google Gemma 3 4B — vision capable, long context, strong reasoning.', accent: Color(0xFFF48FB1)),
  _CatalogEntry(modelId: 'phi4-mini',          label: 'Phi-4 Mini (3.8B)',       size: '2.5 GB', desc: 'Latest Microsoft Phi-4 Mini — improved math and code over Phi-3.5.', accent: Color(0xFF2196F3)),
  _CatalogEntry(modelId: 'deepseek-coder:6.7b', label: 'DeepSeek Coder 6.7B',  size: '3.8 GB', desc: 'DeepSeek code model with project-level code context and 16K window.', accent: Color(0xFF00BCD4)),
  _CatalogEntry(modelId: 'smollm2:1.7b',       label: 'SmolLM2 1.7B',           size: '1.0 GB', desc: 'HuggingFace 1.7B ultra-compact model — great for offline chip-level devices.', accent: Color(0xFF607D8B)),
  _CatalogEntry(modelId: 'nomic-embed-text',   label: 'Nomic Embed Text',        size: '274 MB', desc: 'Local embedding model for RAG pipelines — turns text into vectors.', accent: Color(0xFF78909C)),
];

class OllamaPanel extends StatefulWidget {
  const OllamaPanel({super.key});

  @override
  State<OllamaPanel> createState() => _OllamaPanelState();
}

class _OllamaPanelState extends State<OllamaPanel> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _ollamaRunning = false;
  List<_OllamaModel> _installed = [];
  bool _loading = true;

  // Active pull state
  String? _pulling;
  String _pullLog = '';
  double _pullProgress = 0;
  Process? _pullProcess;

  // Delete confirm
  String? _confirmDelete;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tab.dispose();
    _pullProcess?.kill();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$_base/api/tags'));
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final models = (data['models'] as List?)
            ?.map((m) => _OllamaModel.fromJson(m as Map<String, dynamic>))
            .toList() ?? [];
        setState(() {
          _ollamaRunning = true;
          _installed = models;
          _loading = false;
        });
      } else {
        setState(() { _ollamaRunning = false; _loading = false; });
      }
      client.close();
    } catch (_) {
      setState(() { _ollamaRunning = false; _loading = false; });
    }
  }

  Future<void> _startOllama() async {
    await Process.run('systemctl', ['--user', 'start', 'ollama']).catchError((_) async {
      return Process.run('bash', ['-c', 'ollama serve &']);
    });
    await Future.delayed(const Duration(seconds: 2));
    _refresh();
  }

  Future<void> _pull(String modelId) async {
    if (_pulling != null) return;
    setState(() {
      _pulling = modelId;
      _pullLog = '';
      _pullProgress = 0;
    });
    try {
      _pullProcess = await Process.start('ollama', ['pull', modelId]);
      _pullProcess!.stdout.transform(utf8.decoder).listen((chunk) {
        if (!mounted) return;
        setState(() {
          _pullLog += chunk;
          // Parse progress from "pulling <digest>... X%"
          final match = RegExp(r'(\d+)%').allMatches(chunk);
          if (match.isNotEmpty) {
            _pullProgress = int.parse(match.last.group(1)!) / 100.0;
          }
        });
      });
      _pullProcess!.stderr.transform(utf8.decoder).listen((chunk) {
        if (!mounted) return;
        setState(() => _pullLog += chunk);
      });
      final exit = await _pullProcess!.exitCode;
      if (mounted) {
        setState(() {
          _pulling = null;
          _pullProgress = exit == 0 ? 1.0 : 0;
          _pullLog += exit == 0 ? '\n✓ Pull complete.' : '\n✗ Pull failed (exit $exit).';
        });
        if (exit == 0) _refresh();
      }
    } catch (e) {
      if (mounted) setState(() { _pulling = null; _pullLog += '\n✗ Error: $e'; });
    }
  }

  void _cancelPull() {
    _pullProcess?.kill();
    setState(() { _pulling = null; _pullLog += '\n⚠ Cancelled.'; });
  }

  Future<void> _delete(String name) async {
    setState(() => _confirmDelete = null);
    try {
      final client = HttpClient();
      final req = await client.deleteUrl(Uri.parse('$_base/api/delete'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'name': name}));
      final res = await req.close();
      await res.drain();
      client.close();
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'), backgroundColor: const Color(0xFFEF4444)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Color(0xFF0F0C1F),
          border: Border(bottom: BorderSide(color: SwarmColors.border)),
        ),
        child: Row(children: [
          const Text('🦙', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text('Ollama Models', style: SwarmTextStyles.h2.copyWith(fontSize: 13, color: SwarmColors.textPrimary)),
          const SizedBox(width: 10),
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (_ollamaRunning ? const Color(0xFF34C759) : const Color(0xFFEF4444)).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: _ollamaRunning ? const Color(0xFF34C759) : const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(_ollamaRunning ? 'Running' : 'Offline', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _ollamaRunning ? const Color(0xFF34C759) : const Color(0xFFEF4444))),
            ]),
          ),
          const Spacer(),
          if (!_ollamaRunning)
            _Btn('Start Ollama', const Color(0xFF34C759), _startOllama)
          else
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 16, color: SwarmColors.textMuted), onPressed: _refresh, tooltip: 'Refresh', constraints: const BoxConstraints(), padding: const EdgeInsets.all(4)),
        ]),
      ),
      // iGPU notice
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        color: const Color(0xFF1A0A00),
        child: const Row(children: [
          Icon(Icons.memory_rounded, size: 11, color: Color(0xFFFF9800)),
          SizedBox(width: 6),
          Expanded(child: Text('Integrated GPU detected — running CPU-only. Safe models: ≤7B (needs ~5 GB free RAM each).', style: TextStyle(fontSize: 10, color: Color(0xFFFF9800)))),
        ]),
      ),
      // Tabs
      Container(
        color: const Color(0xFF0A0818),
        child: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          labelColor: const Color(0xFF0A84FF),
          unselectedLabelColor: SwarmColors.textMuted,
          indicatorColor: const Color(0xFF0A84FF),
          indicatorWeight: 2,
          tabs: [
            Tab(text: 'INSTALLED (${_installed.length})', height: 30),
            const Tab(text: 'PULL CATALOG', height: 30),
          ],
        ),
      ),
      // Pull progress bar (shown when pulling)
      if (_pulling != null)
        _PullBar(modelId: _pulling!, progress: _pullProgress, log: _pullLog, onCancel: _cancelPull),
      // Tab content
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A84FF)))
            : !_ollamaRunning
                ? _OfflineState(onStart: _startOllama)
                : TabBarView(controller: _tab, children: [
                    _InstalledTab(
                      models: _installed,
                      confirmDelete: _confirmDelete,
                      onDeleteTap: (n) => setState(() => _confirmDelete = n),
                      onDeleteConfirm: _delete,
                      onDeleteCancel: () => setState(() => _confirmDelete = null),
                    ),
                    _CatalogTab(
                      installed: _installed.map((m) => m.name).toSet(),
                      pulling: _pulling,
                      onPull: _pull,
                    ),
                  ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INSTALLED TAB
// ══════════════════════════════════════════════════════════════════════════════
class _InstalledTab extends StatelessWidget {
  final List<_OllamaModel> models;
  final String? confirmDelete;
  final ValueChanged<String> onDeleteTap;
  final ValueChanged<String> onDeleteConfirm;
  final VoidCallback onDeleteCancel;

  const _InstalledTab({
    required this.models,
    required this.confirmDelete,
    required this.onDeleteTap,
    required this.onDeleteConfirm,
    required this.onDeleteCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('🦙', style: TextStyle(fontSize: 40)),
          SizedBox(height: 8),
          Text('No models installed yet.\nSwitch to Pull Catalog to download one.', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted, height: 1.5), textAlign: TextAlign.center),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: models.length,
      itemBuilder: (_, i) {
        final m = models[i];
        final deleting = confirmDelete == m.name;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: deleting ? const Color(0xFF2D0A0A) : SwarmColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: deleting ? const Color(0xFFEF4444).withValues(alpha: 0.5) : SwarmColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🦙', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Text(m.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary, fontFamily: 'monospace'))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF34C759).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
                child: Text(m.sizeLabel, style: const TextStyle(fontSize: 9, color: Color(0xFF34C759), fontWeight: FontWeight.bold)),
              ),
            ]),
            if (m.paramSize.isNotEmpty || m.quantLevel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 24),
                child: Text('${m.family}  ${m.paramSize}  ${m.quantLevel}'.trim(), style: const TextStyle(fontSize: 10, color: SwarmColors.textDisabled, fontFamily: 'monospace')),
              ),
            if (deleting) ...[
              const SizedBox(height: 8),
              const Text('Delete this model? This cannot be undone.', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
              const SizedBox(height: 6),
              Row(children: [
                _Btn('Delete', const Color(0xFFEF4444), () => onDeleteConfirm(m.name)),
                const SizedBox(width: 6),
                _Btn('Cancel', SwarmColors.textMuted, onDeleteCancel),
              ]),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 24),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF34C759)),
                  const SizedBox(width: 4),
                  const Text('Installed · Ready', style: TextStyle(fontSize: 9, color: Color(0xFF34C759))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => onDeleteTap(m.name),
                    child: const Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 12, color: SwarmColors.textDisabled),
                      SizedBox(width: 3),
                      Text('Remove', style: TextStyle(fontSize: 9, color: SwarmColors.textDisabled)),
                    ]),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CATALOG TAB
// ══════════════════════════════════════════════════════════════════════════════
class _CatalogTab extends StatelessWidget {
  final Set<String> installed;
  final String? pulling;
  final ValueChanged<String> onPull;

  const _CatalogTab({required this.installed, required this.pulling, required this.onPull});

  bool _isInstalled(String id) => installed.any((n) => n == id || n.startsWith('$id:') || id.startsWith('$n:'));

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _catalog.length,
      itemBuilder: (_, i) {
        final entry = _catalog[i];
        final isInstalled = _isInstalled(entry.modelId);
        final isPulling = pulling == entry.modelId;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isInstalled ? entry.accent.withValues(alpha: 0.06) : SwarmColors.bgElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isInstalled ? entry.accent.withValues(alpha: 0.35) : SwarmColors.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 3, height: 44,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: entry.accent, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(entry.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary)),
                const SizedBox(width: 6),
                Text(entry.modelId, style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: SwarmColors.textDisabled)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: SwarmColors.bgSurface, borderRadius: BorderRadius.circular(3), border: Border.all(color: SwarmColors.border)),
                  child: Text(entry.size, style: const TextStyle(fontSize: 9, color: SwarmColors.textMuted, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(entry.desc, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted, height: 1.4)),
              const SizedBox(height: 6),
              Row(children: [
                if (isInstalled)
                  const Row(children: [
                    Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF34C759)),
                    SizedBox(width: 3),
                    Text('Installed', style: TextStyle(fontSize: 9, color: Color(0xFF34C759), fontWeight: FontWeight.bold)),
                  ])
                else if (isPulling)
                  const Row(children: [
                    SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0A84FF))),
                    SizedBox(width: 6),
                    Text('Pulling…', style: TextStyle(fontSize: 9, color: Color(0xFF0A84FF), fontWeight: FontWeight.bold)),
                  ])
                else
                  GestureDetector(
                    onTap: pulling == null ? () => onPull(entry.modelId) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: entry.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: entry.accent.withValues(alpha: pulling == null ? 0.5 : 0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download_rounded, size: 11, color: pulling == null ? entry.accent : SwarmColors.textDisabled),
                        const SizedBox(width: 4),
                        Text('Pull', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: pulling == null ? entry.accent : SwarmColors.textDisabled)),
                      ]),
                    ),
                  ),
              ]),
            ])),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PULL PROGRESS BAR
// ══════════════════════════════════════════════════════════════════════════════
class _PullBar extends StatelessWidget {
  final String modelId;
  final double progress;
  final String log;
  final VoidCallback onCancel;

  const _PullBar({required this.modelId, required this.progress, required this.log, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final lastLine = log.trim().split('\n').lastWhere((l) => l.isNotEmpty, orElse: () => 'Connecting…');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF0A84FF).withValues(alpha: 0.08),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0A84FF))),
          const SizedBox(width: 8),
          Expanded(child: Text('Pulling $modelId…', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0A84FF)))),
          GestureDetector(onTap: onCancel, child: const Icon(Icons.close_rounded, size: 14, color: SwarmColors.textMuted)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 3,
            color: const Color(0xFF0A84FF),
            backgroundColor: SwarmColors.border,
          ),
        ),
        const SizedBox(height: 4),
        Text(lastLine.length > 80 ? lastLine.substring(lastLine.length - 80) : lastLine,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: SwarmColors.textDisabled)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFLINE STATE
// ══════════════════════════════════════════════════════════════════════════════
class _OfflineState extends StatelessWidget {
  final VoidCallback onStart;
  const _OfflineState({required this.onStart});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: SwarmColors.textDisabled),
          const SizedBox(height: 10),
          const Text('Ollama is not running', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: SwarmColors.textSecondary)),
          const SizedBox(height: 4),
          const Text('Start the Ollama service to use local models.', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_circle_rounded, size: 16),
            label: const Text('Start Ollama', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34C759), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          ),
          const SizedBox(height: 8),
          const Text('Or run:  ollama serve', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: SwarmColors.textDisabled)),
        ]),
      );
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Btn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withValues(alpha: 0.4))),
          child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        ),
      );
}
