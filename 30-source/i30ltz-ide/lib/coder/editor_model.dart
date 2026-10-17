import 'dart:io';
import 'package:flutter/material.dart';

class OpenFile {
  final String path;
  String content;
  bool isDirty;
  String? language;
  TextEditingController controller;
  ScrollController scrollController;
  int cursorLine;
  int cursorCol;

  OpenFile({
    required this.path,
    required this.content,
    this.isDirty = false,
    this.language,
    int? cursorLine,
    int? cursorCol,
  })  : controller = TextEditingController(text: content),
        scrollController = ScrollController(),
        cursorLine = cursorLine ?? 0,
        cursorCol = cursorCol ?? 0 {
    language ??= _detectLanguage(path);
  }

  String get name => path.split('/').last;
  String get displayPath => path.length > 50 ? '...${path.substring(path.length - 47)}' : path;

  static String _detectLanguage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => 'dart',
      'py' => 'python',
      'js' || 'mjs' => 'javascript',
      'ts' || 'tsx' => 'typescript',
      'kt' || 'kts' => 'kotlin',
      'java' => 'java',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'md' => 'markdown',
      'sh' || 'bash' => 'shell',
      'cs' => 'csharp',
      'cpp' || 'cc' || 'cxx' => 'cpp',
      'c' || 'h' => 'c',
      'html' => 'html',
      'css' => 'css',
      'xml' => 'xml',
      'gradle' || 'groovy' => 'groovy',
      'toml' => 'toml',
      'rs' => 'rust',
      'go' => 'go',
      _ => 'plain',
    };
  }

  void dispose() {
    controller.dispose();
    scrollController.dispose();
  }
}

class GitStatus {
  final String branch;
  final List<GitChange> staged;
  final List<GitChange> unstaged;
  final List<GitChange> untracked;
  final int ahead;
  final int behind;

  const GitStatus({
    this.branch = 'main',
    this.staged = const [],
    this.unstaged = const [],
    this.untracked = const [],
    this.ahead = 0,
    this.behind = 0,
  });

  int get totalChanges => staged.length + unstaged.length + untracked.length;
}

class GitChange {
  final String path;
  final String status; // M, A, D, R, C, U, ?
  final bool isStaged;

  const GitChange({required this.path, required this.status, required this.isStaged});

  String get statusLabel => switch (status) {
        'M' => 'Modified',
        'A' => 'Added',
        'D' => 'Deleted',
        'R' => 'Renamed',
        '?' => 'Untracked',
        _ => status,
      };

  Color get statusColor => switch (status) {
        'M' => const Color(0xFFF59E0B),
        'A' => const Color(0xFF10B981),
        'D' => const Color(0xFFEF4444),
        'R' => const Color(0xFF06B6D4),
        '?' => const Color(0xFF8B5CF6),
        _ => const Color(0xFF9CA3AF),
      };
}

class DiagnosticItem {
  final String file;
  final int line;
  final int col;
  final String message;
  final DiagnosticSeverity severity;

  const DiagnosticItem({
    required this.file,
    required this.line,
    required this.col,
    required this.message,
    required this.severity,
  });
}

enum DiagnosticSeverity { error, warning, info, hint }

class AndroidDevice {
  final String id;
  final String name;
  final String state; // device, offline, unauthorized
  final bool isEmulator;
  final String? apiLevel;

  const AndroidDevice({
    required this.id,
    required this.name,
    required this.state,
    required this.isEmulator,
    this.apiLevel,
  });

  bool get isOnline => state == 'device';
}

class ExtensionReview {
  final String author;
  final double rating;
  final String comment;
  final DateTime date;

  const ExtensionReview({
    required this.author,
    required this.rating,
    required this.comment,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'author': author,
        'rating': rating,
        'comment': comment,
        'date': date.toIso8601String(),
      };

  factory ExtensionReview.fromJson(Map<String, dynamic> json) => ExtensionReview(
        author: json['author'] as String? ?? 'Anonymous',
        rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
        comment: json['comment'] as String? ?? '',
        date: json['date'] != null ? DateTime.tryParse(json['date']) ?? DateTime.now() : DateTime.now(),
      );
}

class MarketplaceExtension {
  final String id;
  final String name;
  final String publisher;
  final String description;
  final String version; // latest available
  final double rating;
  final int installs;
  final String category;
  final List<String> tags;
  bool isInstalled;
  String? installedVersion;     // version currently installed
  final String changelog;       // release notes for latest version
  final List<String> versionHistory; // previous versions for rollback
  final bool isVerifiedPublisher;
  final String signatureStatus; // 'verified_official', 'verified_partner', 'unverified_community'
  bool autoUpdate;
  bool isEnabled;
  final List<ExtensionReview> reviews;

  bool get hasUpdate => isInstalled && installedVersion != null && installedVersion != version;

  MarketplaceExtension({
    required this.id,
    required this.name,
    required this.publisher,
    required this.description,
    required this.version,
    required this.rating,
    required this.installs,
    required this.category,
    required this.tags,
    this.isInstalled = false,
    this.installedVersion,
    this.changelog = '',
    this.versionHistory = const [],
    this.isVerifiedPublisher = true,
    this.signatureStatus = 'verified_official',
    this.autoUpdate = true,
    this.isEnabled = true,
    this.reviews = const [],
  });
}

class SearchResult {
  final String file;
  final int line;
  final String lineText;
  final int matchStart;
  final int matchEnd;

  const SearchResult({
    required this.file,
    required this.line,
    required this.lineText,
    required this.matchStart,
    required this.matchEnd,
  });
}

class FileNode {
  final String path;
  final String name;
  final bool isDir;
  List<FileNode> children;
  bool isExpanded;

  FileNode({
    required this.path,
    required this.name,
    required this.isDir,
    this.children = const [],
    this.isExpanded = false,
  });

  static FileNode fromFileSystem(String rootPath) {
    final dir = Directory(rootPath);
    return _build(dir, rootPath);
  }

  static FileNode _build(Directory dir, String rootPath) {
    final name = dir.path.split('/').last;
    List<FileNode> children = [];
    try {
      final entries = dir.listSync()
        ..sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return a.path.split('/').last.compareTo(b.path.split('/').last);
        });
      for (final e in entries) {
        final eName = e.path.split('/').last;
        if (eName.startsWith('.') && eName != '.gitignore') continue;
        if (['node_modules', '__pycache__', '.dart_tool', 'build', '.gradle'].contains(eName)) continue;
        if (e is Directory) {
          children.add(_build(e, rootPath));
        } else if (e is File) {
          children.add(FileNode(path: e.path, name: eName, isDir: false));
        }
      }
    } catch (_) {}
    return FileNode(path: dir.path, name: name, isDir: true, children: children);
  }
}
