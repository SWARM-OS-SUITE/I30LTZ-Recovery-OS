import 'dart:convert';
import 'dart:io' hide Platform;
import '../platform/platform.dart';
import 'package:flutter/foundation.dart';

class IdeProfile {
  final String id;
  final String name;
  final String description;
  final String iconName;
  final int tabSize;
  final double fontSize;
  final String fontFamily;
  final bool wordWrap;
  final bool showLineNumbers;
  final bool autoSave;
  final bool showMinimap;
  final bool formatOnSave;
  final bool showGitBlame;
  final bool offlineLocalFirst;
  final String aiCompletionMode; // 'local' (Ollama), 'off'

  const IdeProfile({
    required this.id,
    required this.name,
    required this.description,
    this.iconName = 'code',
    this.tabSize = 2,
    this.fontSize = 13.0,
    this.fontFamily = 'monospace',
    this.wordWrap = false,
    this.showLineNumbers = true,
    this.autoSave = true,
    this.showMinimap = false,
    this.formatOnSave = true,
    this.showGitBlame = true,
    this.offlineLocalFirst = false,
    this.aiCompletionMode = 'local',
  });

  IdeProfile copyWith({
    String? name,
    String? description,
    String? iconName,
    int? tabSize,
    double? fontSize,
    String? fontFamily,
    bool? wordWrap,
    bool? showLineNumbers,
    bool? autoSave,
    bool? showMinimap,
    bool? formatOnSave,
    bool? showGitBlame,
    bool? offlineLocalFirst,
    String? aiCompletionMode,
  }) {
    return IdeProfile(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      tabSize: tabSize ?? this.tabSize,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      wordWrap: wordWrap ?? this.wordWrap,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      autoSave: autoSave ?? this.autoSave,
      showMinimap: showMinimap ?? this.showMinimap,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      showGitBlame: showGitBlame ?? this.showGitBlame,
      offlineLocalFirst: offlineLocalFirst ?? this.offlineLocalFirst,
      aiCompletionMode: aiCompletionMode ?? this.aiCompletionMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'iconName': iconName,
        'tabSize': tabSize,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'wordWrap': wordWrap,
        'showLineNumbers': showLineNumbers,
        'autoSave': autoSave,
        'showMinimap': showMinimap,
        'formatOnSave': formatOnSave,
        'showGitBlame': showGitBlame,
        'offlineLocalFirst': offlineLocalFirst,
        'aiCompletionMode': aiCompletionMode,
      };

  factory IdeProfile.fromJson(Map<String, dynamic> json) {
    return IdeProfile(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? 'Custom Profile',
      description: json['description'] as String? ?? '',
      iconName: json['iconName'] as String? ?? 'code',
      tabSize: (json['tabSize'] as num?)?.toInt() ?? 2,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 13.0,
      fontFamily: json['fontFamily'] as String? ?? 'monospace',
      wordWrap: json['wordWrap'] as bool? ?? false,
      showLineNumbers: json['showLineNumbers'] as bool? ?? true,
      autoSave: json['autoSave'] as bool? ?? true,
      showMinimap: json['showMinimap'] as bool? ?? false,
      formatOnSave: json['formatOnSave'] as bool? ?? true,
      showGitBlame: json['showGitBlame'] as bool? ?? true,
      offlineLocalFirst: json['offlineLocalFirst'] as bool? ?? false,
      aiCompletionMode: json['aiCompletionMode'] as String? ?? 'local',
    );
  }

  // Predefined Presets
  static const flutterDev = IdeProfile(
    id: 'preset-flutter',
    name: 'Flutter & Dart Pro',
    description: 'Optimized for cross-platform UI development, 2-space indentation, hot reload hooks',
    iconName: 'flutter',
    tabSize: 2,
    fontSize: 13.5,
    fontFamily: 'monospace',
    wordWrap: false,
    showLineNumbers: true,
    autoSave: true,
    showMinimap: false,
    formatOnSave: true,
    showGitBlame: true,
    offlineLocalFirst: false,
    aiCompletionMode: 'local',
  );

  static const cppEngine = IdeProfile(
    id: 'preset-cpp',
    name: 'C++ Systems & Vulkan',
    description: 'High-density systems programming, 4-space indent, strict syntax, minimap enabled',
    iconName: 'memory',
    tabSize: 4,
    fontSize: 12.5,
    fontFamily: 'monospace',
    wordWrap: false,
    showLineNumbers: true,
    autoSave: false,
    showMinimap: true,
    formatOnSave: false,
    showGitBlame: true,
    offlineLocalFirst: true,
    aiCompletionMode: 'off',
  );

  static const androidMobile = IdeProfile(
    id: 'preset-android',
    name: 'Android Mobile Native',
    description: 'Kotlin/Java mobile workspace with integrated ADB and gradle hot paths',
    iconName: 'android',
    tabSize: 4,
    fontSize: 13.0,
    fontFamily: 'monospace',
    wordWrap: true,
    showLineNumbers: true,
    autoSave: true,
    showMinimap: false,
    formatOnSave: true,
    showGitBlame: true,
    offlineLocalFirst: false,
    aiCompletionMode: 'local',
  );

  static const devOps = IdeProfile(
    id: 'preset-devops',
    name: 'DevOps & Cloud Orchestrator',
    description: 'YAML, Docker, Shell scripts, side-by-side terminal, strict git history',
    iconName: 'cloud',
    tabSize: 2,
    fontSize: 12.0,
    fontFamily: 'monospace',
    wordWrap: true,
    showLineNumbers: true,
    autoSave: true,
    showMinimap: true,
    formatOnSave: true,
    showGitBlame: true,
    offlineLocalFirst: false,
    aiCompletionMode: 'local',
  );
}

class SettingsProfileService extends ChangeNotifier {
  static final SettingsProfileService instance = SettingsProfileService._();
  SettingsProfileService._() {
    _init();
  }

  late final String _profilesFilePath;
  List<IdeProfile> _profiles = [
    IdeProfile.flutterDev,
    IdeProfile.cppEngine,
    IdeProfile.androidMobile,
    IdeProfile.devOps,
  ];

  IdeProfile _activeProfile = IdeProfile.flutterDev;

  List<IdeProfile> get profiles => List.unmodifiable(_profiles);
  IdeProfile get activeProfile => _activeProfile;

  void _init() {
    final home = Platform.environment['HOME'] ?? '/home/i30ltz';
    final dir = Directory('$home/.i30ltz-ide');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    _profilesFilePath = '${dir.path}/ide_profiles.json';
    loadProfiles();
  }

  Future<void> loadProfiles() async {
    try {
      final file = File(_profilesFilePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final list = (data['profiles'] as List<dynamic>?)
                ?.map((e) => IdeProfile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        final activeId = data['activeProfileId'] as String?;

        if (list.isNotEmpty) {
          _profiles = list;
          _activeProfile = _profiles.firstWhere((p) => p.id == activeId, orElse: () => _profiles.first);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[SettingsProfileService] Load failed: $e');
    }
  }

  Future<void> selectProfile(String profileId) async {
    final match = _profiles.firstWhere((p) => p.id == profileId, orElse: () => _activeProfile);
    _activeProfile = match;
    notifyListeners();
    await saveProfiles();
  }

  Future<void> updateActiveProfile(IdeProfile updated) async {
    final idx = _profiles.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      _profiles[idx] = updated;
    } else {
      _profiles.add(updated);
    }
    _activeProfile = updated;
    notifyListeners();
    await saveProfiles();
  }

  Future<void> saveProfiles() async {
    try {
      final file = File(_profilesFilePath);
      final map = {
        'activeProfileId': _activeProfile.id,
        'profiles': _profiles.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
    } catch (e) {
      debugPrint('[SettingsProfileService] Save failed: $e');
    }
  }

  String exportProfileJson(IdeProfile profile) {
    return const JsonEncoder.withIndent('  ').convert(profile.toJson());
  }

  Future<bool> importProfileFromJson(String jsonStr) async {
    try {
      final Map<String, dynamic> map = jsonDecode(jsonStr);
      final profile = IdeProfile.fromJson(map);
      await updateActiveProfile(profile);
      return true;
    } catch (_) {
      return false;
    }
  }
}
