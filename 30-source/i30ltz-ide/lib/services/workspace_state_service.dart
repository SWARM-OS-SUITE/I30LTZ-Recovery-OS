import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Platform;
import '../platform/platform.dart';
import 'package:flutter/foundation.dart';

class WorkspaceSnapshot {
  final String? workspacePath;
  final List<String> openFilePaths;
  final int activeFileIndex;
  final int cursorLine;
  final int cursorCol;
  final bool isSplit;
  final bool isSplitHorizontal;
  final String activeSidebarPanel;
  final double sidebarWidth;
  final double bottomPanelHeight;
  final bool offlineMode;
  final DateTime lastSaved;

  const WorkspaceSnapshot({
    this.workspacePath,
    this.openFilePaths = const [],
    this.activeFileIndex = -1,
    this.cursorLine = 1,
    this.cursorCol = 1,
    this.isSplit = false,
    this.isSplitHorizontal = false,
    this.activeSidebarPanel = 'files',
    this.sidebarWidth = 260.0,
    this.bottomPanelHeight = 220.0,
    this.offlineMode = false,
    required this.lastSaved,
  });

  Map<String, dynamic> toJson() => {
        'workspacePath': workspacePath,
        'openFilePaths': openFilePaths,
        'activeFileIndex': activeFileIndex,
        'cursorLine': cursorLine,
        'cursorCol': cursorCol,
        'isSplit': isSplit,
        'isSplitHorizontal': isSplitHorizontal,
        'activeSidebarPanel': activeSidebarPanel,
        'sidebarWidth': sidebarWidth,
        'bottomPanelHeight': bottomPanelHeight,
        'offlineMode': offlineMode,
        'lastSaved': lastSaved.toIso8601String(),
      };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkspaceSnapshot(
      workspacePath: json['workspacePath'] as String?,
      openFilePaths: (json['openFilePaths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      activeFileIndex: (json['activeFileIndex'] as num?)?.toInt() ?? -1,
      cursorLine: (json['cursorLine'] as num?)?.toInt() ?? 1,
      cursorCol: (json['cursorCol'] as num?)?.toInt() ?? 1,
      isSplit: json['isSplit'] as bool? ?? false,
      isSplitHorizontal: json['isSplitHorizontal'] as bool? ?? false,
      activeSidebarPanel: json['activeSidebarPanel'] as String? ?? 'files',
      sidebarWidth: (json['sidebarWidth'] as num?)?.toDouble() ?? 260.0,
      bottomPanelHeight: (json['bottomPanelHeight'] as num?)?.toDouble() ?? 220.0,
      offlineMode: json['offlineMode'] as bool? ?? false,
      lastSaved: json['lastSaved'] != null ? DateTime.tryParse(json['lastSaved']) ?? DateTime.now() : DateTime.now(),
    );
  }
}

class WorkspaceStateService extends ChangeNotifier {
  static final WorkspaceStateService instance = WorkspaceStateService._();
  WorkspaceStateService._() {
    _initStorage();
    _startNetworkWatcher();
  }

  WorkspaceSnapshot _snapshot = WorkspaceSnapshot(lastSaved: DateTime.now());
  WorkspaceSnapshot get snapshot => _snapshot;

  bool _isOnline = true;
  bool get isOnline => !_snapshot.offlineMode && _isOnline;
  bool get forceOffline => _snapshot.offlineMode;

  late final String _stateFilePath;
  Timer? _debounceTimer;

  void _initStorage() {
    final home = Platform.environment['HOME'] ?? '/home/i30ltz';
    final swarmDir = Directory('$home/.i30ltz-ide');
    if (!swarmDir.existsSync()) {
      try {
        swarmDir.createSync(recursive: true);
      } catch (_) {}
    }
    _stateFilePath = '${swarmDir.path}/workspace_state.json';
  }

  Future<void> _startNetworkWatcher() async {
    // Check real connectivity periodically
    _checkNetwork();
    Timer.periodic(const Duration(seconds: 15), (_) => _checkNetwork());
  }

  Future<void> _checkNetwork() async {
    if (_snapshot.offlineMode) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
      return;
    }
    try {
      final result = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (online != _isOnline) {
        _isOnline = online;
        notifyListeners();
      }
    } catch (_) {
      if (_isOnline) {
        _isOnline = false;
        notifyListeners();
      }
    }
  }

  Future<WorkspaceSnapshot> loadState() async {
    try {
      final file = File(_stateFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(content);
        _snapshot = WorkspaceSnapshot.fromJson(json);
        notifyListeners();
        return _snapshot;
      }
    } catch (e) {
      debugPrint('[WorkspaceStateService] Error loading state: $e');
    }
    return _snapshot;
  }

  void updateState({
    String? workspacePath,
    List<String>? openFilePaths,
    int? activeFileIndex,
    int? cursorLine,
    int? cursorCol,
    bool? isSplit,
    bool? isSplitHorizontal,
    String? activeSidebarPanel,
    double? sidebarWidth,
    double? bottomPanelHeight,
    bool? offlineMode,
  }) {
    _snapshot = WorkspaceSnapshot(
      workspacePath: workspacePath ?? _snapshot.workspacePath,
      openFilePaths: openFilePaths ?? _snapshot.openFilePaths,
      activeFileIndex: activeFileIndex ?? _snapshot.activeFileIndex,
      cursorLine: cursorLine ?? _snapshot.cursorLine,
      cursorCol: cursorCol ?? _snapshot.cursorCol,
      isSplit: isSplit ?? _snapshot.isSplit,
      isSplitHorizontal: isSplitHorizontal ?? _snapshot.isSplitHorizontal,
      activeSidebarPanel: activeSidebarPanel ?? _snapshot.activeSidebarPanel,
      sidebarWidth: sidebarWidth ?? _snapshot.sidebarWidth,
      bottomPanelHeight: bottomPanelHeight ?? _snapshot.bottomPanelHeight,
      offlineMode: offlineMode ?? _snapshot.offlineMode,
      lastSaved: DateTime.now(),
    );

    notifyListeners();

    // Debounce state persistence writes to disk
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () => _persistToDisk());
  }

  Future<void> toggleOfflineMode() async {
    final next = !_snapshot.offlineMode;
    updateState(offlineMode: next);
    await _checkNetwork();
  }

  Future<void> _persistToDisk() async {
    try {
      final file = File(_stateFilePath);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_snapshot.toJson());
      await file.writeAsString(jsonStr);
    } catch (e) {
      debugPrint('[WorkspaceStateService] Persist failed: $e');
    }
  }
}
