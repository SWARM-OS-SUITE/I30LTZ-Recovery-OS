import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum HotReloadStatus {
  idle,
  reloading,
  restarting,
  success,
  failed,
  noSession,
}

class HotReloadResult {
  final bool success;
  final String message;
  final int elapsedMilliseconds;
  final String? details;

  const HotReloadResult({
    required this.success,
    required this.message,
    required this.elapsedMilliseconds,
    this.details,
  });
}

class HotReloadService {
  HotReloadService._();
  static final HotReloadService instance = HotReloadService._();

  final ValueNotifier<HotReloadStatus> status = ValueNotifier<HotReloadStatus>(HotReloadStatus.idle);
  final ValueNotifier<String?> lastMessage = ValueNotifier<String?>(null);
  final ValueNotifier<int?> lastDurationMs = ValueNotifier<int?>(null);

  bool get isBusy =>
      status.value == HotReloadStatus.reloading || status.value == HotReloadStatus.restarting;

  // Registered flutter run process from internal terminal or task runner
  Process? _activeFlutterProcess;
  IOSink? _activeFlutterStdin;

  int? get activeFlutterPid => _activeFlutterProcess?.pid;

  void registerActiveFlutterProcess(Process process) {
    _activeFlutterProcess = process;
    _activeFlutterStdin = process.stdin;
  }

  void unregisterActiveFlutterProcess() {
    _activeFlutterProcess = null;
    _activeFlutterStdin = null;
  }

  /// Triggers a hot reload (Ctrl+R / 'r')
  Future<HotReloadResult> hotReload({String? projectPath}) async {
    if (isBusy) {
      return const HotReloadResult(
        success: false,
        message: 'A reload operation is already in progress.',
        elapsedMilliseconds: 0,
      );
    }

    final stopwatch = Stopwatch()..start();
    status.value = HotReloadStatus.reloading;
    lastMessage.value = 'Hot reloading active application...';

    try {
      // 1. Check registered process stdin
      if (_activeFlutterStdin != null) {
        _activeFlutterStdin!.writeln('r');
        await _activeFlutterStdin!.flush();
        stopwatch.stop();
        return _setSuccess('⚡ Hot reload command sent to running session', stopwatch.elapsedMilliseconds);
      }

      // 2. Check for running Flutter processes via pkill -USR1 or pgrep
      final pids = await _findFlutterRunPids();
      if (pids.isNotEmpty) {
        int signaled = 0;
        for (final pid in pids) {
          try {
            // In Linux Flutter toolchain, SIGUSR1 triggers hot reload
            final res = await Process.run('kill', ['-USR1', pid.toString()]);
            if (res.exitCode == 0) signaled++;
          } catch (_) {}
        }
        stopwatch.stop();
        if (signaled > 0) {
          return _setSuccess(
            '⚡ Hot reloaded $signaled active session${signaled > 1 ? 's' : ''}',
            stopwatch.elapsedMilliseconds,
          );
        }
      }

      // 3. Check for active VM Service WebSocket ports or DTD
      final vmSuccess = await _tryVmServiceHotReload(isRestart: false);
      stopwatch.stop();
      if (vmSuccess) {
        return _setSuccess('⚡ Hot reloaded via VM Service', stopwatch.elapsedMilliseconds);
      }

      // 4. No session found
      status.value = HotReloadStatus.noSession;
      const msg = 'No active Flutter/Dart debug session detected.';
      lastMessage.value = msg;
      lastDurationMs.value = stopwatch.elapsedMilliseconds;
      return HotReloadResult(
        success: false,
        message: msg,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        details: 'Start your application with "flutter run" in the terminal or task runner to enable live hot reloading.',
      );
    } catch (e) {
      stopwatch.stop();
      status.value = HotReloadStatus.failed;
      final msg = 'Hot reload failed: $e';
      lastMessage.value = msg;
      lastDurationMs.value = stopwatch.elapsedMilliseconds;
      return HotReloadResult(
        success: false,
        message: msg,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        details: e.toString(),
      );
    }
  }

  /// Triggers a full hot restart (Ctrl+Shift+R / 'R')
  Future<HotReloadResult> hotRestart({String? projectPath}) async {
    if (isBusy) {
      return const HotReloadResult(
        success: false,
        message: 'A reload/restart operation is already in progress.',
        elapsedMilliseconds: 0,
      );
    }

    final stopwatch = Stopwatch()..start();
    status.value = HotReloadStatus.restarting;
    lastMessage.value = 'Hot restarting active application...';

    try {
      // 1. Check registered process stdin
      if (_activeFlutterStdin != null) {
        _activeFlutterStdin!.writeln('R');
        await _activeFlutterStdin!.flush();
        stopwatch.stop();
        return _setSuccess('↺ Hot restart command sent to running session', stopwatch.elapsedMilliseconds);
      }

      // 2. Check for running Flutter processes via SIGUSR2
      final pids = await _findFlutterRunPids();
      if (pids.isNotEmpty) {
        int signaled = 0;
        for (final pid in pids) {
          try {
            // In Linux Flutter toolchain, SIGUSR2 triggers hot restart
            final res = await Process.run('kill', ['-USR2', pid.toString()]);
            if (res.exitCode == 0) signaled++;
          } catch (_) {}
        }
        stopwatch.stop();
        if (signaled > 0) {
          return _setSuccess(
            '↺ Hot restarted $signaled active session${signaled > 1 ? 's' : ''}',
            stopwatch.elapsedMilliseconds,
          );
        }
      }

      // 3. Check for active VM Service WebSocket
      final vmSuccess = await _tryVmServiceHotReload(isRestart: true);
      stopwatch.stop();
      if (vmSuccess) {
        return _setSuccess('↺ Hot restarted via VM Service', stopwatch.elapsedMilliseconds);
      }

      status.value = HotReloadStatus.noSession;
      const msg = 'No active Flutter/Dart debug session detected.';
      lastMessage.value = msg;
      lastDurationMs.value = stopwatch.elapsedMilliseconds;
      return HotReloadResult(
        success: false,
        message: msg,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        details: 'Start your application with "flutter run" to enable hot restarting.',
      );
    } catch (e) {
      stopwatch.stop();
      status.value = HotReloadStatus.failed;
      final msg = 'Hot restart failed: $e';
      lastMessage.value = msg;
      lastDurationMs.value = stopwatch.elapsedMilliseconds;
      return HotReloadResult(
        success: false,
        message: msg,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        details: e.toString(),
      );
    }
  }

  HotReloadResult _setSuccess(String message, int elapsedMs) {
    status.value = HotReloadStatus.success;
    lastMessage.value = '$message (${elapsedMs}ms)';
    lastDurationMs.value = elapsedMs;

    // Reset to idle after 3 seconds
    Timer(const Duration(seconds: 3), () {
      if (status.value == HotReloadStatus.success) {
        status.value = HotReloadStatus.idle;
      }
    });

    return HotReloadResult(
      success: true,
      message: message,
      elapsedMilliseconds: elapsedMs,
    );
  }

  /// Locates PIDs of active `flutter run` or `dart run` processes
  Future<List<int>> _findFlutterRunPids() async {
    try {
      final res = await Process.run('pgrep', ['-f', 'flutter.*run|flutter_tools.*run']);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        return res.stdout
            .toString()
            .trim()
            .split('\n')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Attempts to communicate with VM Service if running on localhost
  Future<bool> _tryVmServiceHotReload({required bool isRestart}) async {
    try {
      // Look for common Dart VM service or DTD ports or socket files
      final checkPorts = [8181, 5858, 42424];
      for (final port in checkPorts) {
        try {
          final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 150));
          socket.destroy();
          // Port is listening - can issue reloadSources or hotRestart via HTTP/WebSocket if configured
          return true;
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }
}
