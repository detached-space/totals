import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/profile.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_export_import_service.dart';

/// Backups carry a `profileId` per account/transaction, and those ids are
/// meaningless on the restoring device — profile 3 there is not profile 3 here.
/// Without a mapping the rows import successfully and then every
/// profile-filtered read hides them: data restored, app looks empty.
///
/// Runs against a REAL sqlite (ffi) database through [DatabaseHelper] so the
/// insert path (which falls back to the active profile when a row has no
/// profileId) is the real one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Opening the database reads prefs (_ensureProfileSchema), so the mock has
    // to exist before the first open, not just before each test.
    SharedPreferences.setMockInitialValues({});
    final dbPath = p.join(await getDatabasesPath(), 'totals.db');
    await deleteDatabase(dbPath);
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.delete('transactions');
    await db.delete('accounts');
    await db.delete('profiles');
    // A fresh install has exactly one profile.
    final personal = await ProfileRepository()
        .saveProfile(Profile(name: 'Personal', createdAt: DateTime.now()));
    await ProfileRepository().setActiveProfile(personal);
  });

  Map<String, dynamic> tx(String reference, int profileId) => {
        'reference': reference,
        'amount': 10.0,
        'type': 'expense',
        'bankId': 1,
        'time': '2026-08-18T10:00:00.000',
        'profileId': profileId,
      };

  Map<String, dynamic> account(String number, int profileId) => {
        'accountNumber': number,
        'bank': 1,
        'balance': 0.0,
        'accountHolderName': 'Holder $number',
        'profileId': profileId,
      };

  Future<Map<int, int>> txCountByProfile() async {
    final rows = await db.rawQuery(
      'SELECT profileId, COUNT(*) c FROM transactions GROUP BY profileId',
    );
    return {
      for (final r in rows) (r['profileId'] as int?) ?? -1: r['c'] as int,
    };
  }

  Future<Map<String, int>> profilesByName() async {
    final rows = await db.query('profiles');
    return {
      for (final r in rows) r['name'] as String: r['id'] as int,
    };
  }

  test('two nameless source profiles stay separate, never merged', () async {
    // Source ids 2 and 3. Neither exists locally; the local profile is id 1.
    final payload = {
      'schemaVersion': 8,
      'accounts': [
        account('1001', 2),
        account('1002', 3),
        account('1003', 3),
      ],
      'transactions': [
        for (var i = 0; i < 5; i++) tx('src2-$i', 2),
        for (var i = 0; i < 3; i++) tx('src3-$i', 3),
      ],
    };

    await DataExportImportService().importAllData(jsonEncode(payload));

    final names = await profilesByName();
    expect(names.keys, containsAll(['Restored profile 1', 'Restored profile 2']),
        reason: 'each nameless source profile needs its own placeholder');

    final p2 = names['Restored profile 1']!;
    final p3 = names['Restored profile 2']!;
    expect(p2, isNot(p3), reason: 'the two source profiles must not collapse');

    final counts = await txCountByProfile();
    expect(counts[p2], 5);
    expect(counts[p3], 3);
    expect(counts.values.fold<int>(0, (a, b) => a + b), 8,
        reason: 'every row must land somewhere');
  });

  test('placeholder id colliding with a later source id does not merge',
      () async {
    // Regression: the first placeholder gets a fresh autoincrement id that can
    // equal a source id not yet mapped. Treating that as "already exists here"
    // funnelled both source profiles into one.
    final payload = {
      'schemaVersion': 8,
      'transactions': [
        // 3 first so its placeholder is created first and claims a low id.
        for (var i = 0; i < 4; i++) tx('a-$i', 3),
        for (var i = 0; i < 6; i++) tx('b-$i', 2),
      ],
    };

    await DataExportImportService().importAllData(jsonEncode(payload));

    final counts = await txCountByProfile();
    expect(counts.length, 2,
        reason: 'expected two distinct profiles, got ${counts.length}');
    expect(counts.values.toSet(), {4, 6});
  });

  test('single nameless source profile lands on the active profile', () async {
    final before = await profilesByName();
    final active = before['Personal']!;

    final payload = {
      'schemaVersion': 8,
      'transactions': [for (var i = 0; i < 4; i++) tx('solo-$i', 7)],
    };

    await DataExportImportService().importAllData(jsonEncode(payload));

    final counts = await txCountByProfile();
    expect(counts[active], 4,
        reason: 'one profile in the backup belongs where the user is looking');
    expect((await profilesByName()).length, 1,
        reason: 'no placeholder profile should be invented');
  });

  test('named profiles map by name and re-import is idempotent', () async {
    final payload = {
      'schemaVersion': 8,
      'profiles': [
        {'id': 2, 'name': 'Yew', 'createdAt': '2026-01-01T00:00:00.000'},
        {'id': 3, 'name': 'Synergy', 'createdAt': '2026-01-01T00:00:00.000'},
      ],
      'transactions': [
        for (var i = 0; i < 2; i++) tx('yew-$i', 2),
        for (var i = 0; i < 3; i++) tx('syn-$i', 3),
      ],
    };

    await DataExportImportService().importAllData(jsonEncode(payload));
    await DataExportImportService().importAllData(jsonEncode(payload));

    final names = await profilesByName();
    expect(names.containsKey('Yew'), isTrue);
    expect(names.containsKey('Synergy'), isTrue);
    expect(names.length, 3, reason: 'Personal + Yew + Synergy, no duplicates');

    final counts = await txCountByProfile();
    expect(counts[names['Yew']], 2);
    expect(counts[names['Synergy']], 3);
  });

  test('export carries the profiles section', () async {
    await DataExportImportService().importAllData(jsonEncode({
      'schemaVersion': 8,
      'profiles': [
        {'id': 2, 'name': 'Yew', 'createdAt': '2026-01-01T00:00:00.000'},
      ],
      'transactions': [tx('x-1', 2)],
    }));

    final exported =
        jsonDecode(await DataExportImportService().exportAllData())
            as Map<String, dynamic>;
    final profiles = (exported['profiles'] as List).cast<Map<String, dynamic>>();
    expect(profiles.map((p) => p['name']), contains('Yew'),
        reason: 'without this the restore has no way to name a profile');
    expect(profiles.every((p) => p['id'] != null), isTrue,
        reason: 'rows reference profiles by id, so ids must be exported');
  });

  test('real device backup splits exactly as the file says', () async {
    // Opt-in: point TOTALS_BACKUP_FIXTURE at a real device export to check the
    // mapping against production data. Skipped everywhere else.
    final path = Platform.environment['TOTALS_BACKUP_FIXTURE'];
    if (path == null || path.isEmpty) {
      markTestSkipped('set TOTALS_BACKUP_FIXTURE to a device export to run');
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('backup fixture not found at $path');
      return;
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final expected = <int, int>{};
    for (final t in (decoded['transactions'] as List)) {
      final pid = (t as Map)['profileId'] as int?;
      if (pid != null) expected[pid] = (expected[pid] ?? 0) + 1;
    }

    await DataExportImportService().importAllData(raw);

    final counts = await txCountByProfile();
    expect(counts.values.fold<int>(0, (a, b) => a + b),
        (decoded['transactions'] as List).length,
        reason: 'no transaction may be dropped');
    expect(counts.values.toList()..sort(), expected.values.toList()..sort(),
        reason: 'the per-profile split must match the file exactly');
  });
}
