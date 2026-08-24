import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/sms_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String databasePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DataSyncSettingsService.cachedEnabled = false;
    await DatabaseHelper.instance.close();
    databasePath = '${await databaseFactoryFfi.getDatabasesPath()}/totals.db';
    await databaseFactoryFfi.deleteDatabase(databasePath);
    db = await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    if (db.isOpen) await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('bundled Dashen fix overrides an older imported parser', () async {
    await db.delete('sms_patterns');
    await db.insert('sms_patterns', <String, Object?>{
      'bankId': 4,
      'senderId': 'Dashen',
      'regex': r'received\s+ETB\s+(?<amount>[\d,.]+).*?'
          r'on\s+(?<date>\d{2}\/\d{2}\/\d{4})\s+\d{2}:\d{2}:\d{2}',
      'type': 'CREDIT',
      'description': 'Dashen Telebirr Credit',
      'refRequired': 0,
      'hasAccount': 1,
    });

    final patterns = await SmsConfigService().getPatterns(
      allowRemoteFetch: false,
    );
    final dashen = patterns.singleWhere(
      (pattern) =>
          pattern.bankId == 4 &&
          pattern.description == 'Dashen Telebirr Credit',
    );
    const body = '''Dear Customer, You have received ETB 51,450.00 from
telebirr account number 251943685872 Ref No:2603092000308528 on 09/03/2026
at 08:23:58 AM to your bank account '5107******011'. Your account balance
is ETB 51,509.06.''';

    expect(
      RegExp(
        dashen.regex,
        caseSensitive: false,
        multiLine: true,
        dotAll: true,
      ).hasMatch(body),
      isTrue,
    );
  });

  test('bundled Endekise fix does not treat outstanding as wallet balance',
      () async {
    await db.delete('sms_patterns');
    await db.insert('sms_patterns', <String, Object?>{
      'bankId': 6,
      'senderId': 'telebirr',
      'regex':
          r'endekise[\s\S]*?ETB\s*(?<amount>-?[\d,.]+)\s+credit\s+amount[\s\S]*?outstanding\s+amount\s+is\s+ETB\s*(?<balance>-?[\d,.]+)',
      'type': 'CREDIT',
      'description': 'Fallback Telebirr endekise',
      'refRequired': 0,
      'hasAccount': 0,
    });

    final patterns = await SmsConfigService().getPatterns(
      allowRemoteFetch: false,
    );
    final endekise = patterns.singleWhere(
      (pattern) =>
          pattern.bankId == 6 &&
          pattern.description == 'Fallback Telebirr endekise',
    );

    expect(endekise.type, 'DEBIT');
    expect(endekise.regex.contains('?<outstanding>'), isTrue);
    expect(endekise.regex.contains('?<balance>'), isFalse);
  });
}
