import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/log/log_params.dart';

/// Process-wide file logger. Configure once from [LogParams] in `runMultiApp`.
///
/// Do not construct; use [MvdLog.instance].
@internal
class MvdLog {
  MvdLog._();

  static final MvdLog instance = MvdLog._();

  LogParams _params = const LogParams();
  Directory? _directory;
  File? _file;
  bool _ready = false;

  /// Directory that holds `mvd.log`. Same path in debug and release.
  Directory? get directory => _directory;

  /// Active log file, or null when logging is off / not yet opened.
  File? get file => _file;

  /// Applies [params] and opens (or closes) the log file.
  ///
  /// [directoryOverride] is for tests.
  void configure(LogParams params, {Directory? directoryOverride}) {
    _params = params;
    _ready = false;
    _file = null;
    _directory = null;
    if (!params.enable) return;
    _directory = directoryOverride ?? defaultLogDirectory();
    _directory!.createSync(recursive: true);
    _file = File('${_directory!.path}${Platform.pathSeparator}mvd.log');
    if (!_file!.existsSync()) {
      _file!.createSync();
    }
    _ready = true;
    info('log', 'logger started', {
      'path': _file!.path,
      'sizeKb': params.sizeKb,
      'kDebugMode': kDebugMode,
      'kReleaseMode': kReleaseMode,
    });
  }

  /// Cache directory shared by debug and release of the host process.
  ///
  /// macOS: `~/Library/Caches/multiview_desktop`
  /// Windows: `%LOCALAPPDATA%/multiview_desktop/logs`
  /// Linux: `${XDG_CACHE_HOME:-~/.cache}/multiview_desktop`
  ///
  /// Cleared with the OS/user cache, not with a debug-only temp folder.
  static Directory defaultLogDirectory() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      return Directory('$home/Library/Caches/multiview_desktop');
    }
    if (Platform.isWindows) {
      final base =
          Platform.environment['LOCALAPPDATA'] ?? Platform.environment['TEMP'] ?? Directory.systemTemp.path;
      return Directory('$base${Platform.pathSeparator}multiview_desktop${Platform.pathSeparator}logs');
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final cache = Platform.environment['XDG_CACHE_HOME'] ?? '$home/.cache';
    return Directory('$cache/multiview_desktop');
  }

  void info(String module, String message, [Map<String, Object?>? data]) =>
      _emit('I', module, message, data, toConsole: false);

  void warn(String module, String message, [Map<String, Object?>? data]) =>
      _emit('W', module, message, data, toConsole: true);

  void error(String module, String message, [Map<String, Object?>? data]) =>
      _emit('E', module, message, data, toConsole: true);

  /// Logs view-id mapping / parent links.
  ///
  /// Public ids are 1-based on every platform. [publicId] / [parentPublicId]
  /// below 1 (including `0`) is [error]. Negative real ids other than native
  /// [CreateViewError] codes are also [error]. Real `0` is valid on Windows/Linux.
  void ids(
    String module,
    String message, {
    int? realId,
    int? publicId,
    int? parentRealId,
    int? parentPublicId,
    int? shift,
    Map<String, Object?>? extra,
  }) {
    final data = <String, Object?>{
      'realId': ?realId,
      'publicId': ?publicId,
      'parentRealId': ?parentRealId,
      'parentPublicId': ?parentPublicId,
      'shift': ?shift,
      ...?extra,
    };

    if (realId != null && CreateViewError.isErrorCode(realId)) {
      error(module, '$message: native create returned error code', data);
      return;
    }
    if (parentRealId != null && CreateViewError.isErrorCode(parentRealId)) {
      error(module, '$message: parent is a native error code', data);
      return;
    }

    final invalid = <String>[];
    if (realId != null && realId < 0) invalid.add('realId');
    if (parentRealId != null && parentRealId < 0) invalid.add('parentRealId');
    if (publicId != null && publicId < 1) invalid.add('publicId');
    if (parentPublicId != null && parentPublicId < 1) invalid.add('parentPublicId');
    if (invalid.isNotEmpty) {
      error(module, '$message: invalid view id (${invalid.join(', ')}; public ids must be >= 1)', data);
      return;
    }
    info(module, message, data);
  }

  @visibleForTesting
  void resetForTest() {
    _params = const LogParams();
    _directory = null;
    _file = null;
    _ready = false;
  }

  void _emit(String level, String module, String message, Map<String, Object?>? data, {required bool toConsole}) {
    if (!_params.enable || !_ready || _file == null) return;
    final ts = DateTime.now().toUtc().toIso8601String();
    final line = '$ts $level [$module] $message${_fmt(data)}';
    try {
      _rotateIfNeeded(line.length + 1);
      _file!.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MVD][log] failed to write: $e');
      }
      return;
    }
    if (toConsole && kDebugMode) {
      debugPrint('[MVD]$line');
    }
  }

  void _rotateIfNeeded(int incomingBytes) {
    final maxBytes = _params.sizeKb <= 0 ? 1024 * 1024 : _params.sizeKb * 1024;
    final current = _file!.existsSync() ? _file!.lengthSync() : 0;
    if (current + incomingBytes <= maxBytes) return;
    final prev = File('${_file!.path}.prev');
    if (prev.existsSync()) {
      prev.deleteSync();
    }
    _file!.renameSync(prev.path);
    _file = File('${_directory!.path}${Platform.pathSeparator}mvd.log');
    _file!.createSync();
  }

  String _fmt(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return '';
    final parts = <String>[];
    for (final e in data.entries) {
      if (e.value == null) continue;
      parts.add('${e.key}=${e.value}');
    }
    if (parts.isEmpty) return '';
    return ' ${parts.join(' ')}';
  }
}
