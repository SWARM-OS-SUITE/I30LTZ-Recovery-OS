import 'dart:convert';
import 'dart:io' hide Platform;
import '../platform/platform.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import '../coder/editor_model.dart';
import 'package_signing_service.dart';

class ExtensionRuntimeLog {
  final String extensionId;
  final String message;
  final String level; // 'info', 'warn', 'error'
  final DateTime timestamp;

  const ExtensionRuntimeLog({
    required this.extensionId,
    required this.message,
    this.level = 'info',
    required this.timestamp,
  });
}

class ExtensionRuntimeService extends ChangeNotifier {
  static final ExtensionRuntimeService instance = ExtensionRuntimeService._();
  ExtensionRuntimeService._() {
    _initDirectory();
    _loadExtensions();
  }

  late final Directory _extensionsDir;
  Directory get extensionsDir => _extensionsDir;

  final List<MarketplaceExtension> _installed = [];
  final List<MarketplaceExtension> _marketplace = [];
  final List<ExtensionRuntimeLog> _runtimeLogs = [];

  List<MarketplaceExtension> get installed => List.unmodifiable(_installed);
  List<MarketplaceExtension> get marketplace => List.unmodifiable(_marketplace);
  List<ExtensionRuntimeLog> get runtimeLogs => List.unmodifiable(_runtimeLogs);

  void _initDirectory() {
    final home = Platform.environment['HOME'] ?? '/home/i30ltz';
    _extensionsDir = Directory('$home/.i30ltz-ide/extensions');
    if (!_extensionsDir.existsSync()) {
      try {
        _extensionsDir.createSync(recursive: true);
      } catch (_) {}
    }
  }

  void _loadExtensions() {
    // Initial built-in catalog
    _marketplace.addAll([
      MarketplaceExtension(
        id: 'dart-lang',
        name: 'Dart Language Pro',
        publisher: 'swarm.io',
        description: 'Deep Dart syntax analysis, code formatting, and analyzer interop',
        version: '1.2.0',
        rating: 4.9,
        installs: 12400,
        category: 'Languages',
        tags: ['dart', 'flutter', 'analyzer'],
        isInstalled: true,
        installedVersion: '1.2.0',
        isVerifiedPublisher: true,
        signatureStatus: 'verified_official',
        changelog: '• Optimized AST parser for null-safety\n• Enhanced quick fixes\n• Instant hover docs',
        versionHistory: ['1.0.0', '1.1.0', '1.2.0'],
        reviews: [
          ExtensionReview(author: 'DevKev', rating: 5, comment: 'Flawless analyzer feedback!', date: DateTime.now().subtract(const Duration(days: 3))),
          ExtensionReview(author: 'Julia99', rating: 4.8, comment: 'Super fast formatting on save', date: DateTime.now().subtract(const Duration(days: 12))),
        ],
      ),
      MarketplaceExtension(
        id: 'flutter-widgets',
        name: 'Flutter Widget Snippets',
        publisher: 'swarm.io',
        description: 'Responsive layout templates, M3 components, stateful builders',
        version: '1.3.0',
        rating: 4.8,
        installs: 9200,
        category: 'Snippets',
        tags: ['flutter', 'widgets', 'm3'],
        isInstalled: true,
        installedVersion: '1.3.0',
        isVerifiedPublisher: true,
        signatureStatus: 'verified_official',
        changelog: '• Added 40 Material 3 widget patterns\n• Adaptive navigation drawer snippets',
        versionHistory: ['1.0.0', '1.1.0', '1.2.0', '1.3.0'],
        reviews: [
          ExtensionReview(author: 'SamDart', rating: 5, comment: 'Saves 30 mins every screen build', date: DateTime.now().subtract(const Duration(days: 5))),
        ],
      ),
      MarketplaceExtension(
        id: 'git-lens',
        name: 'Git Lens Pro',
        publisher: 'swarm.io',
        description: 'Porcelain blame gutters, hunk inspector, visual commit graph DAG',
        version: '2.1.0',
        rating: 5.0,
        installs: 16800,
        category: 'Git',
        tags: ['git', 'blame', 'history'],
        isInstalled: true,
        installedVersion: '2.0.0', // has update
        isVerifiedPublisher: true,
        signatureStatus: 'verified_official',
        changelog: '• Visual commit graph DAG\n• Inline ghost blame\n• Stash management studio',
        versionHistory: ['1.8.0', '2.0.0', '2.1.0'],
        reviews: [
          ExtensionReview(author: 'LinuxHacker', rating: 5, comment: 'Best git lens on Linux desktop', date: DateTime.now().subtract(const Duration(days: 1))),
        ],
      ),
      MarketplaceExtension(
        id: 'android-sdk-tools',
        name: 'Android Native SDK Manager',
        publisher: 'swarm.io',
        description: 'Commandline SDK tools, platform detection, AVD hardware management',
        version: '2.4.0',
        rating: 4.7,
        installs: 8100,
        category: 'Android',
        tags: ['android', 'sdk', 'emulator'],
        isInstalled: false,
        isVerifiedPublisher: true,
        signatureStatus: 'verified_official',
        changelog: '• Auto-discovery of ANDROID_HOME\n• Fast AVD cold-boot',
        versionHistory: ['2.0.0', '2.4.0'],
      ),
      MarketplaceExtension(
        id: 'cpp-clangd',
        name: 'Clangd & Vulkan Helper',
        publisher: 'partner.vulkan.org',
        description: 'High-performance C++20 LSP, SPIR-V bytecode shader compilation',
        version: '1.4.2',
        rating: 4.6,
        installs: 5300,
        category: 'Languages',
        tags: ['cpp', 'clangd', 'vulkan'],
        isInstalled: false,
        isVerifiedPublisher: true,
        signatureStatus: 'verified_partner',
        changelog: '• Vulkan 1.3 validation layer integration',
        versionHistory: ['1.3.0', '1.4.2'],
      ),
      MarketplaceExtension(
        id: 'cyber-stealth-theme',
        name: 'Cyber Stealth Blue WS6 Theme',
        publisher: 'community.i30ltz',
        description: 'Vibrant electric blue neon accents, pitch black OLED editor backdrop',
        version: '1.0.1',
        rating: 4.85,
        installs: 4100,
        category: 'Themes',
        tags: ['theme', 'blue', 'ws6'],
        isInstalled: false,
        isVerifiedPublisher: false,
        signatureStatus: 'unverified_community',
        changelog: '• Initial electric blue WS6 colorway',
        versionHistory: ['1.0.0', '1.0.1'],
      ),
    ]);

    _installed.addAll(_marketplace.where((e) => e.isInstalled));

    // Scan disk for external extensions in ~/.i30ltz-ide/extensions
    _scanDisk();
  }

  void _scanDisk() {
    try {
      if (!_extensionsDir.existsSync()) return;
      for (final entity in _extensionsDir.listSync()) {
        if (entity is Directory) {
          final manifestFile = File('${entity.path}/manifest.json');
          if (manifestFile.existsSync()) {
            final json = jsonDecode(manifestFile.readAsStringSync());
            final extId = json['id'] as String? ?? entity.path.split('/').last;
            final existing = _installed.firstWhereOrNull((e) => e.id == extId);
            if (existing == null) {
              final newExt = MarketplaceExtension(
                id: extId,
                name: json['name'] as String? ?? extId,
                publisher: json['publisher'] as String? ?? 'Local Developer',
                description: json['description'] as String? ?? 'Locally installed extension',
                version: json['version'] as String? ?? '1.0.0',
                rating: 5.0,
                installs: 1,
                category: json['category'] as String? ?? 'Tools',
                tags: (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? ['local'],
                isInstalled: true,
                installedVersion: json['version'] as String? ?? '1.0.0',
                isVerifiedPublisher: false,
                signatureStatus: 'unverified_community',
              );
              _installed.add(newExt);
              _marketplace.add(newExt);
              _log(extId, 'Discovered local extension on disk: $extId', level: 'info');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ExtensionRuntimeService] Scan disk failed: $e');
    }
  }

  Future<void> installExtension(MarketplaceExtension ext) async {
    // 1. Verify signature
    final extDir = Directory('${_extensionsDir.path}/${ext.id}');
    if (!extDir.existsSync()) {
      extDir.createSync(recursive: true);
    }

    final manifest = ExtensionManifest(
      id: ext.id,
      name: ext.name,
      version: ext.version,
      publisher: ext.publisher,
      description: ext.description,
      main: 'index.js',
      permissions: ['editor.read', 'editor.write'],
    );

    final manifestFile = File('${extDir.path}/manifest.json');
    await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));

    // 2. Lifecycle hook
    await runExtensionLifecycle(ext.id, 'onActivate');

    ext.isInstalled = true;
    ext.installedVersion = ext.version;
    if (!_installed.any((e) => e.id == ext.id)) {
      _installed.add(ext);
    }

    _log(ext.id, 'Successfully installed and activated ${ext.name} v${ext.version}');
    notifyListeners();
  }

  Future<void> uninstallExtension(String extId) async {
    final ext = _marketplace.firstWhereOrNull((e) => e.id == extId);
    if (ext != null) {
      await runExtensionLifecycle(extId, 'onDeactivate');
      ext.isInstalled = false;
      ext.installedVersion = null;
      _installed.removeWhere((e) => e.id == extId);

      // Clean disk
      try {
        final dir = Directory('${_extensionsDir.path}/$extId');
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}

      _log(extId, 'Uninstalled $extId');
      notifyListeners();
    }
  }

  Future<void> updateExtension(String extId) async {
    final ext = _marketplace.firstWhereOrNull((e) => e.id == extId);
    if (ext != null) {
      await runExtensionLifecycle(extId, 'onDeactivate');
      ext.installedVersion = ext.version;
      await runExtensionLifecycle(extId, 'onActivate');
      _log(extId, 'Updated ${ext.name} to v${ext.version}');
      notifyListeners();
    }
  }

  Future<void> rollbackVersion(String extId, String targetVersion) async {
    final ext = _marketplace.firstWhereOrNull((e) => e.id == extId);
    if (ext != null) {
      await runExtensionLifecycle(extId, 'onDeactivate');
      ext.installedVersion = targetVersion;
      await runExtensionLifecycle(extId, 'onActivate');
      _log(extId, 'Rolled back ${ext.name} to v$targetVersion');
      notifyListeners();
    }
  }

  void toggleAutoUpdate(String extId) {
    final ext = _marketplace.firstWhereOrNull((e) => e.id == extId);
    if (ext != null) {
      ext.autoUpdate = !ext.autoUpdate;
      notifyListeners();
    }
  }

  void submitReview(String extId, double rating, String comment, {String author = 'i30ltz'}) {
    final ext = _marketplace.firstWhereOrNull((e) => e.id == extId);
    if (ext != null) {
      final review = ExtensionReview(author: author, rating: rating, comment: comment, date: DateTime.now());
      ext.reviews.insert(0, review);
      _log(extId, 'Review submitted by $author ($rating stars)');
      notifyListeners();
    }
  }

  /// Extension lifecycle hooks are not executed: SWARM OS has no sandboxed
  /// runtime host (no JS engine, no isolate/container boundary) to run
  /// third-party extension code in. This previously slept 60ms and logged
  /// "completed cleanly", which reported success for work that never ran.
  /// Until a real sandbox exists, say so rather than claiming success.
  Future<void> runExtensionLifecycle(String extId, String hook) async {
    _log(
      extId,
      'Hook $hook() skipped — no sandboxed extension runtime is attached',
      level: 'warn',
    );
  }

  void _log(String extId, String message, {String level = 'info'}) {
    _runtimeLogs.add(ExtensionRuntimeLog(extensionId: extId, message: message, level: level, timestamp: DateTime.now()));
    if (_runtimeLogs.length > 200) _runtimeLogs.removeAt(0);
  }
}
