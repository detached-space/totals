import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Debug-only trace collector for the Telegram *restore* path.
///
/// Backup (upload) and restore (download) are asymmetric on the Telegram Bot
/// API — `sendDocument` accepts up to 50 MB while `getFile` only serves 20 MB —
/// so "backup works but restore doesn't" needs a stage-by-stage trace to place
/// the failure. Every layer on the restore leg (bot API → service → crypto →
/// import → UI) appends here; the UI can then render/share the whole trace as a
/// single text file without Xcode.
///
/// Privacy: record sizes, counts, hashes (prefixes only), and booleans — never
/// raw financial rows, the full recovery key, or the bot token.
class TelegramRestoreDiagnostics {
  TelegramRestoreDiagnostics._();

  static final TelegramRestoreDiagnostics instance =
      TelegramRestoreDiagnostics._();

  final List<String> _lines = <String>[];
  Stopwatch? _clock;

  bool get isEmpty => _lines.isEmpty;

  /// Start a fresh trace. Call once when a restore attempt begins.
  void begin(String title) {
    _lines.clear();
    _clock = Stopwatch()..start();
    _lines.add('==== $title ====');
    _lines.add('when: ${DateTime.now().toIso8601String()}');
    log('platform',
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  void log(String stage, [Object? detail]) {
    final elapsed = _clock?.elapsedMilliseconds ?? 0;
    final line =
        detail == null ? '[+${elapsed}ms] $stage' : '[+${elapsed}ms] $stage: $detail';
    _lines.add(line);
    debugPrint('debug: TGRESTORE $line');
  }

  String render() => _lines.join('\n');

  /// Short, non-sensitive hash/key prefix for correlation in the trace.
  static String short(String value, [int length = 12]) {
    final trimmed = value.trim();
    return trimmed.length <= length ? trimmed : trimmed.substring(0, length);
  }

  /// Write the current trace to a shareable text file and return its path.
  Future<String> writeToFile() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/totals_restore_diagnostics.txt';
    await File(path).writeAsString(render(), flush: true);
    return path;
  }
}
