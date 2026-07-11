import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/ios_migration_service.dart';

/// END-TO-END: converts the real ios-files/ export, runs the REAL
/// [DataExportImportService.importAllData] against a REAL sqlite DB (ffi),
/// then asserts what the UI would show — this is the test that would have
/// caught `normalizeImportPayload` dropping the `profiles` section.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const exportDir = '/Users/yewe/W/totals/totals-staging/ios-files';

  test('real import: profiles created, Awash accounts split, no duplication',
      () async {
    if (!Directory(exportDir).existsSync()) return; // sample data not present

    // Real sqlite on the host + mock prefs (active-profile id lives there).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final dbPath = p.join(await getDatabasesPath(), 'totals.db');
    await deleteDatabase(dbPath); // clean slate

    // Convert the real export.
    final files = <String, String>{};
    for (final f in Directory(exportDir).listSync().whereType<File>()) {
      final n = f.uri.pathSegments.last;
      if (n.endsWith('.txt') || n.endsWith('.json')) {
        files[n] = f.readAsStringSync();
      }
    }
    final payload = IosMigrationService.instance.convert(files).payload;

    // Sanity: the payload survives the importer's normalization step. This is
    // the exact spot the profiles section was previously dropped.
    final normalized = DataExportImportService.normalizeImportPayload(
        jsonEncode(payload));
    expect((normalized['profiles'] as List).length, 2,
        reason: 'normalizeImportPayload must pass the profiles section through');

    // REAL import.
    await DataExportImportService().importAllData(jsonEncode(payload));

    final db = await databaseFactory.openDatabase(dbPath);

    // Profiles exist.
    final profiles = await db.query('profiles');
    final byName = {for (final r in profiles) r['name'] as String: r['id'] as int};
    expect(byName.keys.toSet().containsAll({'Yew', 'Synergy'}), isTrue,
        reason: 'Yew + Synergy must be created, got: ${byName.keys}');
    final yewId = byName['Yew']!, synergyId = byName['Synergy']!;

    // The two Awash accounts landed in DIFFERENT profiles.
    final awashAccounts =
        await db.query('accounts', where: 'bank = 2', orderBy: 'accountNumber');
    expect(awashAccounts.length, 2);
    final acct2500 = awashAccounts
        .firstWhere((a) => (a['accountNumber'] as String).endsWith('2500'));
    final acct9200 = awashAccounts
        .firstWhere((a) => (a['accountNumber'] as String).endsWith('9200'));
    expect(acct2500['profileId'], yewId, reason: '2500 belongs to Yew');
    expect(acct9200['profileId'], synergyId, reason: '9200 belongs to Synergy');

    // What the UI shows per profile for a non-uniform bank (Awash): all bank-2
    // transactions in that profile. Must be a real split, not 90/90.
    Future<int> awashTxCount(int profileId) async {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) c FROM transactions WHERE bankId = 2 AND profileId = ?',
          [profileId]);
      return rows.first['c'] as int;
    }

    // 59/31: overrides (44/9) + masked-string matches ("01320xxxxxx2500" → 2500)
    // rescue 22 txns the old app dumped on the default account. Never disagrees
    // with the user's manual overrides in this dataset.
    final yewAwash = await awashTxCount(yewId);
    final synergyAwash = await awashTxCount(synergyId);
    expect(yewAwash, 59, reason: 'Yew profile shows only its Awash txns');
    expect(synergyAwash, 31, reason: 'Synergy profile shows only its Awash txns');
    expect(yewAwash + synergyAwash, 90, reason: 'no Awash txn lost or duplicated');

    // Reconstructed balances land on the right accounts (old app showed 75.82
    // for 2500 because its newest txns were mis-assigned to the default acct).
    expect((acct2500['balance'] as num).toDouble(), closeTo(10074.97, 0.01));
    expect((acct9200['balance'] as num).toDouble(), closeTo(5068.97, 0.01));

    // Overall: transactions are distributed across the two profiles.
    final dist = await db.rawQuery(
        'SELECT profileId, COUNT(*) c FROM transactions GROUP BY profileId');
    final counts = {for (final r in dist) r['profileId']: r['c'] as int};
    expect(counts[yewId], greaterThan(1000));
    expect(counts[synergyId], greaterThan(800));

    // Active profile switched to the first imported profile (Yew) so the user
    // sees data immediately after import.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('active_profile_id'), yewId,
        reason: 'import must activate the first imported profile (Yew)');

    // Typeless rows (454 in this export — deposits especially) must be typed
    // via the old app's heuristic (receiver → DEBIT, none → CREDIT), never null:
    // null-typed rows vanish from credit/debit totals and render as expenses.
    final nullTyped = (await db.rawQuery(
        "SELECT COUNT(*) c FROM transactions WHERE type IS NULL OR type = ''"))[0]['c'] as int;
    expect(nullTyped, 0, reason: 'every imported transaction must be typed');
    // Aba sums after typeless-heuristic + mis-bank repair: 9 ghost rows joined
    // bank 9 (4 chain-proven debits, 5 flagged credits) and 2 mis-banked rows
    // (26,000 + 6 credits) left for CBE.
    final abaSums = await db.rawQuery(
        "SELECT type, SUM(amount) s FROM transactions WHERE bankId = 9 GROUP BY type");
    final abaByType = {for (final r in abaSums) r['type']: (r['s'] as num).toDouble()};
    expect(abaByType['CREDIT'], closeTo(2752359.58, 5),
        reason: 'Aba credits must include typeless deposits (was 1.63M when null-typed)');
    expect(abaByType['DEBIT'], closeTo(1679425.64, 5));

    // Mis-banked repair placement: the 9 Amhara rows stored as CBE are re-filed
    // to bank 9 / account 3508 (Yew), and 2 Aba-filed rows return to CBE 5678 —
    // so Yew's CBE shows exactly its 7 + 2 rows and Synergy's its 11. No ghosts.
    final cbeCount = (await db
        .rawQuery('SELECT COUNT(*) c FROM transactions WHERE bankId = 1'))[0]['c'] as int;
    expect(cbeCount, 20, reason: '27 claimed − 9 ghosts + 2 returned');
    final cbeYew = (await db.rawQuery(
        'SELECT COUNT(*) c FROM transactions WHERE bankId = 1 AND profileId = ?',
        [yewId]))[0]['c'] as int;
    expect(cbeYew, 9, reason: "Yew CBE = 7 original + 2 re-banked (…5678 mask)");
    final cbeSynergy = (await db.rawQuery(
        'SELECT COUNT(*) c FROM transactions WHERE bankId = 1 AND profileId = ?',
        [synergyId]))[0]['c'] as int;
    expect(cbeSynergy, 11, reason: 'Synergy CBE = its 11 (…2009 mask) rows');

    // Idempotency: importing the same payload again must not duplicate
    // profiles (or transactions — dedup by reference).
    await DataExportImportService().importAllData(jsonEncode(payload));
    final profilesAfter = await db.query('profiles');
    expect(profilesAfter.where((r) => r['name'] == 'Yew').length, 1,
        reason: 're-import must reuse the existing Yew profile');
    expect(profilesAfter.where((r) => r['name'] == 'Synergy').length, 1,
        reason: 're-import must reuse the existing Synergy profile');
    final txCount = (await db
        .rawQuery('SELECT COUNT(*) c FROM transactions'))[0]['c'] as int;
    expect(txCount, 2199, reason: 're-import must not duplicate transactions');

    await db.close();
  });
}
