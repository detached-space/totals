import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:totals/services/sms_service.dart';

/// Ingests bank messages captured on iOS via a Shortcuts automation.
///
/// iOS can't read SMS, so a "When I get a message" Shortcut drops each bank
/// message as a small text file straight into the app's Documents directory —
/// i.e. the **"Totals" folder** that appears in the Files app. Users never
/// create or pick a subfolder. This service drains that folder on launch/resume
/// and runs each message through the **same** parser the Android SMS path uses,
/// so bank detection, de-duplication, categorization and balance updates all
/// work identically.
///
/// Because the drop folder is the shared Documents directory, the drain only
/// touches files with a message extension ([_messageExtensions]) and ignores
/// everything else the app keeps there (the SQLite DB, etc.).
///
/// Drop-file contract — one file per message, `.txt`:
///   just the raw message text (the bank is identified from the body). An
///   optional `sender:`/`receivedAt:` header followed by a `---` line is also
///   supported but not required.
class MessageIngestService {
  MessageIngestService._();
  static final MessageIngestService instance = MessageIngestService._();

  /// Only files with these extensions are treated as message drops; everything
  /// else in the Documents folder is left untouched — notably the SQLite DB and
  /// the `totals_export_*.json` data backups, which is why `.json` is excluded.
  static const List<String> _messageExtensions = ['.txt'];
  static const String _failedDirName = 'failed';

  /// Queue file appended by the native "Log SMS Entry" App Intent
  /// (ios/Runner/LogSMSIntent.swift). Entries: ISO8601 line, `---`, raw SMS
  /// text, then a `===` delimiter line.
  static const String queueFileName = 'sms_queue.txt';
  static const String _queueProcessingPrefix = 'sms_queue.processing-';

  bool _draining = false;

  /// True while a drain is actively processing messages — drives the
  /// "Importing messages…" pill in the shell. Only flips on when there is
  /// real work, so quiet drains don't flash UI.
  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);

  /// The folder a Shortcut drops message files into: the app's Documents
  /// directory, surfaced as "Totals" in the Files app. No subfolder to create.
  Future<Directory> dropDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  /// Reads every dropped message file and parses it via
  /// [SmsService.processMessage].
  ///
  /// Retention: a file is **deleted** as soon as the parser has handled it —
  /// whether that produced a transaction, a de-duplicated no-op, or a
  /// `failed_parses` record in the DB. Nothing accumulates on disk in the
  /// normal case. A file the parser *couldn't* handle — malformed, empty, or a
  /// message whose sender matches no known bank — is moved to a `failed`
  /// subfolder (app-created; the user never touches it) instead of deleted, so a
  /// genuinely unrecognized bank text is never silently lost and won't loop on
  /// every drain.
  ///
  /// Idempotent and safe to call often (re-entrancy guarded); the parser's own
  /// SMS fingerprinting dedupes if a file is somehow processed twice. Returns
  /// the number of transactions ingested.
  Future<int> drainInbox({bool notifyUser = true}) async {
    if (_draining) return 0;
    _draining = true;
    var ingested = 0;
    try {
      final dropDir = await dropDirectory();
      final failed = Directory('${dropDir.path}/$_failedDirName');

      // Retry previously-quarantined messages first, in case the user has since
      // added the account they belong to. Successes clear; still-unmatched files
      // stay in `failed` for the next drain. Do this before the new drops so a
      // fresh failure isn't retried twice in the same pass.
      if (await failed.exists()) {
        ingested += await _drainFolder(failed,
            failedDir: failed, isRetry: true, notifyUser: notifyUser);
      }

      // Drain the App-Intent queue (the "Log SMS Entry" Shortcut action).
      ingested += await _drainQueue(dropDir, failed, notifyUser: notifyUser);

      // Then process new drops sitting in the Totals folder.
      ingested += await _drainFolder(dropDir,
          failedDir: failed, isRetry: false, notifyUser: notifyUser);
    } finally {
      _draining = false;
      syncing.value = false;
    }
    return ingested;
  }

  /// Drains the queue written by the native App Intent. Crash-safe without
  /// racing concurrent appends: the queue is atomically RENAMED to a claim file
  /// first (a new SMS arriving mid-drain recreates a fresh queue untouched by
  /// us), parsed, and deleted only after every entry was handled. A crash
  /// leaves the claim file behind; the next drain re-runs it and the parser's
  /// SMS fingerprinting skips rows that were already saved — so entries are
  /// neither lost nor double-inserted.
  Future<int> _drainQueue(Directory dropDir, Directory failed,
      {required bool notifyUser}) async {
    var ingested = 0;
    final pending = <File>[];
    // Crash leftovers from a previous drain first.
    for (final e in await dropDir.list().toList()) {
      if (e is File &&
          e.uri.pathSegments.last.startsWith(_queueProcessingPrefix)) {
        pending.add(e);
      }
    }
    final queue = File('${dropDir.path}/$queueFileName');
    try {
      if (await queue.exists() && (await queue.length()) > 0) {
        final claimPath =
            '${dropDir.path}/$_queueProcessingPrefix${DateTime.now().millisecondsSinceEpoch}.txt';
        pending.add(await queue.rename(claimPath));
      }
    } catch (_) {/* queue vanished or claim raced; nothing to do */}

    for (final file in pending) {
      try {
        final entries = parseQueueEntries(await file.readAsString());
        var failures = 0;
        for (final e in entries) {
          syncing.value = true;
          // Yield a frame so a large backlog can't freeze the UI mid-drain.
          await Future<void>.delayed(Duration.zero);
          try {
            final result = await SmsService.processMessageResult(
              e.body,
              '',
              messageDate: e.receivedAt,
              notifyUser: notifyUser,
            );
            if (result.status == ParseStatus.success) ingested++;
            if (result.status == ParseStatus.noBank) {
              await _quarantineQueueEntry(failed, e, ++failures);
            }
          } catch (_) {
            await _quarantineQueueEntry(failed, e, ++failures);
          }
        }
        await _deleteQuietly(file);
      } catch (_) {
        // Whole file unreadable — quarantine it for inspection.
        await _quarantine(file, failed);
      }
    }
    return ingested;
  }

  /// Re-files an unmatched queue entry as a single-message `.txt` in `failed/`,
  /// in the same header format the quarantine retry loop already re-reads —
  /// so it self-heals once the user registers the missing bank.
  Future<void> _quarantineQueueEntry(
    Directory failed,
    ({DateTime? receivedAt, String body}) entry,
    int n,
  ) async {
    try {
      if (!await failed.exists()) await failed.create(recursive: true);
      final name = 'queue-${DateTime.now().millisecondsSinceEpoch}-$n.txt';
      final header = entry.receivedAt != null
          ? 'date: ${entry.receivedAt!.toIso8601String()}\n---\n'
          : '';
      await File('${failed.path}/$name').writeAsString('$header${entry.body}');
    } catch (_) {/* best-effort */}
  }

  /// Splits the raw queue file into entries (see LogSMSIntent.swift for the
  /// writer). Tolerant: an entry without the `---` header becomes body-only;
  /// blank chunks, unparseable timestamps and empty bodies are handled without
  /// throwing.
  static List<({DateTime? receivedAt, String body})> parseQueueEntries(
      String raw) {
    final out = <({DateTime? receivedAt, String body})>[];
    for (final chunk
        in raw.split(RegExp(r'^===[ \t]*\r?$', multiLine: true))) {
      final c = chunk.trim();
      if (c.isEmpty) continue;
      final lines = c.split('\n');
      final sep = lines.indexWhere((l) => l.trimRight() == '---');
      if (sep < 0) {
        out.add((receivedAt: null, body: c));
        continue;
      }
      final ts = DateTime.tryParse(lines.sublist(0, sep).join(' ').trim());
      final body = lines.sublist(sep + 1).join('\n').trim();
      if (body.isNotEmpty) out.add((receivedAt: ts, body: body));
    }
    return out;
  }

  /// Processes every message file in [dir]. On the first pass (`isRetry:false`)
  /// an unmatched file is moved to [failedDir]; on the retry pass it's left in
  /// place. Handled files (stored/deduped/failed-parse-logged) are deleted.
  /// Returns transactions ingested from this folder.
  Future<int> _drainFolder(
    Directory dir, {
    required Directory failedDir,
    required bool isRetry,
    required bool notifyUser,
  }) async {
    var ingested = 0;
    for (final entry in await dir.list().toList()) {
      if (entry is! File) continue; // skip subdirectories (incl. `failed`)
      final name = entry.uri.pathSegments.last;
      if (name.startsWith('.')) continue; // skip hidden / partial writes
      if (name.startsWith('sms_queue')) {
        continue; // App-Intent queue files are drained by _drainQueue
      }
      if (!_messageExtensions.any(name.toLowerCase().endsWith)) {
        continue; // ignore the app's own files (DB, etc.)
      }

      syncing.value = true;
      // Yield a frame so a large backlog can't freeze the UI mid-drain.
      await Future<void>.delayed(Duration.zero);

      ParseStatus status;
      try {
        final record = await _readRecord(entry);
        final body = record?.body.trim() ?? '';
        if (record == null || body.isEmpty) {
          status = ParseStatus.noBank; // unreadable → treat as unmatched
        } else {
          // No sender needed: processMessageResult falls back to identifying the
          // bank from the body (registered banks' patterns) when sender is empty.
          final result = await SmsService.processMessageResult(
            record.body,
            record.sender,
            messageDate: record.receivedAt,
            notifyUser: notifyUser,
          );
          status = result.status;
        }
      } catch (_) {
        status = ParseStatus.noBank; // threw while reading/parsing
      }

      if (status == ParseStatus.success) ingested++;
      if (status == ParseStatus.noBank) {
        // Couldn't tell which bank this is (bank not registered yet, new format,
        // or a non-bank "ETB" message). Never silently drop it.
        if (!isRetry) await _quarantine(entry, failedDir);
        // On retry: leave it in `failed` for a future drain.
      } else {
        // Stored, deduped, unregistered, or logged as a failed parse in the DB —
        // the raw file is now redundant.
        await _deleteQuietly(entry);
      }
    }
    return ingested;
  }

  Future<_IngestRecord?> _readRecord(File file) async {
    final raw = await file.readAsString();
    // Header format (Shortcut-friendly, no escaping needed):
    //   sender: CBE
    //   receivedAt: 1720440000000        (optional)
    //   ---
    //   <raw message body, verbatim — may contain anything, including newlines>
    // Everything after the first line that is exactly `---` is the body, so the
    // body never needs quoting. Without a `---` separator the whole file is the
    // body (a plain paste), and the sender is left empty.
    final lines = raw.split('\n');
    final sepIndex = lines.indexWhere((l) => l.trimRight() == '---');
    if (sepIndex < 0) {
      return _IngestRecord(body: raw, sender: '', receivedAt: null);
    }
    String sender = '';
    DateTime? receivedAt;
    for (var i = 0; i < sepIndex; i++) {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      switch (key) {
        case 'sender':
        case 'from':
        case 'address':
          sender = value;
          break;
        case 'receivedat':
        case 'date':
          receivedAt = _parseDate(value);
          break;
      }
    }
    return _IngestRecord(
      body: lines.sublist(sepIndex + 1).join('\n'),
      sender: sender,
      receivedAt: receivedAt,
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(value);
    }
    return null;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Best-effort; a leftover successfully-parsed file just dedupes next drain.
    }
  }

  /// Moves an un-parseable file into `inbox/failed` for inspection so it stops
  /// being retried on every drain. Created on demand to avoid an empty folder
  /// cluttering Files when there's nothing to quarantine.
  Future<void> _quarantine(File file, Directory failed) async {
    try {
      if (!await failed.exists()) {
        await failed.create(recursive: true);
      }
      await file.rename('${failed.path}/${file.uri.pathSegments.last}');
    } catch (_) {
      // Rename can fail across volumes; copy-then-delete as a fallback.
      try {
        await file.copy('${failed.path}/${file.uri.pathSegments.last}');
        await file.delete();
      } catch (_) {
        // Leave it in place if even that fails; extremely unlikely on-device.
      }
    }
  }
}

class _IngestRecord {
  final String body;
  final String sender;
  final DateTime? receivedAt;
  _IngestRecord({required this.body, required this.sender, this.receivedAt});
}
