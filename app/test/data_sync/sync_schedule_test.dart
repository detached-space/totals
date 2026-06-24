import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/data_sync/sync_models.dart';

SyncRule _rule({
  SyncScheduleMode scheduleMode = SyncScheduleMode.off,
  int? interval,
  List<String> times = const [],
  DateTime? lastScheduledAt,
  bool onNewTxn = false,
  bool onConnectivity = false,
}) {
  final t = DateTime.parse('2024-01-01T00:00:00');
  return SyncRule(
    destinationId: 1,
    name: 'r',
    entity: SyncEntity.transactions,
    pathTemplate: '/x',
    scheduleMode: scheduleMode,
    scheduleIntervalMinutes: interval,
    scheduleTimes: times,
    lastScheduledAt: lastScheduledAt,
    triggerOnNewTxn: onNewTxn,
    triggerOnConnectivity: onConnectivity,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  group('syncScheduleDue · interval', () {
    final now = DateTime.parse('2024-06-01T12:00:00');

    test('never run → due', () {
      expect(
        syncScheduleDue(
            _rule(scheduleMode: SyncScheduleMode.interval, interval: 30), now),
        isTrue,
      );
    });

    test('ran recently → not due', () {
      expect(
        syncScheduleDue(
          _rule(
            scheduleMode: SyncScheduleMode.interval,
            interval: 30,
            lastScheduledAt: now.subtract(const Duration(minutes: 10)),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('interval elapsed → due', () {
      expect(
        syncScheduleDue(
          _rule(
            scheduleMode: SyncScheduleMode.interval,
            interval: 30,
            lastScheduledAt: now.subtract(const Duration(minutes: 31)),
          ),
          now,
        ),
        isTrue,
      );
    });
  });

  group('syncScheduleDue · daily', () {
    test('past a time today, not yet fired → due', () {
      final now = DateTime.parse('2024-06-01T09:05:00');
      expect(
        syncScheduleDue(
            _rule(scheduleMode: SyncScheduleMode.daily, times: ['09:00', '18:00']),
            now),
        isTrue,
      );
    });

    test('before the time → not due', () {
      final now = DateTime.parse('2024-06-01T08:00:00');
      expect(
        syncScheduleDue(
            _rule(scheduleMode: SyncScheduleMode.daily, times: ['09:00']), now),
        isFalse,
      );
    });

    test('already fired this slot → not due', () {
      final now = DateTime.parse('2024-06-01T09:05:00');
      expect(
        syncScheduleDue(
          _rule(
            scheduleMode: SyncScheduleMode.daily,
            times: ['09:00'],
            lastScheduledAt: DateTime.parse('2024-06-01T09:01:00'),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('fired yesterday → due again today', () {
      final now = DateTime.parse('2024-06-02T09:05:00');
      expect(
        syncScheduleDue(
          _rule(
            scheduleMode: SyncScheduleMode.daily,
            times: ['09:00'],
            lastScheduledAt: DateTime.parse('2024-06-01T09:01:00'),
          ),
          now,
        ),
        isTrue,
      );
    });

    test('mode off → never due', () {
      expect(
        syncScheduleDue(_rule(), DateTime.parse('2024-06-01T09:05:00')),
        isFalse,
      );
    });
  });

  group('syncRuleShouldSend', () {
    final now = DateTime.parse('2024-06-01T12:00:00');

    test('manual always flushes', () {
      expect(syncRuleShouldSend(_rule(), 'manual', now), isTrue);
    });

    test('write flushes only real-time rules', () {
      expect(syncRuleShouldSend(_rule(onNewTxn: true), 'write', now), isTrue);
      expect(syncRuleShouldSend(_rule(onNewTxn: false), 'write', now), isFalse);
    });

    test('connectivity flushes only connectivity rules', () {
      expect(
          syncRuleShouldSend(_rule(onConnectivity: true), 'connectivity', now),
          isTrue);
      expect(
          syncRuleShouldSend(_rule(onConnectivity: false), 'connectivity', now),
          isFalse);
    });

    test('periodic falls back to the time schedule', () {
      expect(
        syncRuleShouldSend(
            _rule(scheduleMode: SyncScheduleMode.interval, interval: 30),
            'periodic',
            now),
        isTrue,
      );
      expect(syncRuleShouldSend(_rule(), 'periodic', now), isFalse);
    });
  });
}
