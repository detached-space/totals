import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/message_ingest_service.dart';

/// The queue format contract with ios/Runner/LogSMSIntent.swift:
///   <ISO8601>\n---\n<raw text>\n===\n   (appended per SMS)
void main() {
  test('parses well-formed multi-entry queue', () {
    const raw = '2026-07-11T10:00:00Z\n---\n'
        'Dear Customer, your account has been credited with ETB 1,000.\n===\n'
        '2026-07-11T10:05:00Z\n---\n'
        'You have transferred ETB 500.00\nto someone.\n===\n';
    final entries = MessageIngestService.parseQueueEntries(raw);
    expect(entries.length, 2);
    expect(entries[0].receivedAt, DateTime.utc(2026, 7, 11, 10));
    expect(entries[0].body, contains('credited with ETB 1,000'));
    // Multi-line bodies survive intact.
    expect(entries[1].body, 'You have transferred ETB 500.00\nto someone.');
  });

  test('malformed entries are tolerated, not dropped or crashing', () {
    const raw = 'no header at all, just a pasted message with ETB 50\n===\n'
        'not-a-date\n---\nbody with a bad timestamp\n===\n'
        '\n===\n' // blank chunk
        '2026-07-11T10:00:00Z\n---\n\n===\n'; // empty body
    final entries = MessageIngestService.parseQueueEntries(raw);
    expect(entries.length, 2);
    expect(entries[0].receivedAt, isNull); // headerless → body-only
    expect(entries[0].body, startsWith('no header'));
    expect(entries[1].receivedAt, isNull); // unparseable timestamp
    expect(entries[1].body, 'body with a bad timestamp');
  });

  test('trailing partial entry (crash mid-append) is still returned', () {
    const raw = '2026-07-11T10:00:00Z\n---\nfull entry\n===\n'
        '2026-07-11T10:01:00Z\n---\npartial entry without delimiter';
    final entries = MessageIngestService.parseQueueEntries(raw);
    expect(entries.length, 2);
    expect(entries[1].body, 'partial entry without delimiter');
  });

  test('=== inside a body line does not split when not alone on the line', () {
    const raw = '2026-07-11T10:00:00Z\n---\nbalance === ETB 5 ===ok\n===\n';
    final entries = MessageIngestService.parseQueueEntries(raw);
    expect(entries.length, 1);
    expect(entries[0].body, 'balance === ETB 5 ===ok');
  });

  test('CRLF line endings from Shortcuts are handled', () {
    const raw = '2026-07-11T10:00:00Z\r\n---\r\nwindows-style body\r\n===\r\n';
    final entries = MessageIngestService.parseQueueEntries(raw);
    expect(entries.length, 1);
    expect(entries[0].body, 'windows-style body');
    expect(entries[0].receivedAt, isNotNull);
  });
}
