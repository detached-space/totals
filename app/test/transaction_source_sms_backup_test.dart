import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/transaction_source_sms_repository.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/transaction_sms_source_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;
  late TransactionRepository transactionRepository;
  late TransactionSourceSmsRepository sourceSmsRepository;

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
    await DatabaseHelper.instance.database;
    transactionRepository = TransactionRepository();
    sourceSmsRepository = TransactionSourceSmsRepository();
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await databaseFactoryFfi.deleteDatabase(databasePath);
  });

  test('export and import round trip original transaction source SMS',
      () async {
    await transactionRepository.saveTransaction(
      Transaction(
        amount: 125,
        reference: 'source-sms-round-trip',
        bankId: 1,
        type: 'DEBIT',
        time: '2026-07-26T12:00:00.000',
        sourceType: 'sms',
        sourceMessageId: '42',
        sourceFingerprint: 'source-fingerprint',
      ),
      skipAutoCategorization: true,
    );
    await sourceSmsRepository.upsert(
      TransactionSourceSms(
        transactionReference: 'source-sms-round-trip',
        body: 'ETB 125.00 was paid to Example Store.',
        senderAddress: 'CBE',
        receivedAt: DateTime.parse('2026-07-26T12:00:00.000'),
        messageId: '42',
      ),
    );

    final exportService = DataExportImportService();
    final exported = await exportService.exportAllData();
    final payload = jsonDecode(exported) as Map<String, dynamic>;
    expect(payload['schemaVersion'], 11);
    expect(payload.containsKey('smsPatterns'), isFalse);
    final exportedSourceSms = (payload['transactionSourceSms'] as List<dynamic>)
        .single as Map<String, dynamic>;
    expect(
      exportedSourceSms['transactionReference'],
      'source-sms-round-trip',
    );
    expect(
      exportedSourceSms['body'],
      'ETB 125.00 was paid to Example Store.',
    );

    await transactionRepository.clearAll();
    expect(
      await sourceSmsRepository.getForTransaction('source-sms-round-trip'),
      isNull,
    );

    await exportService.importAllData(exported);

    final restoredTransaction =
        await transactionRepository.getTransactionByReference(
      'source-sms-round-trip',
    );
    expect(restoredTransaction, isNotNull);
    final restored =
        await sourceSmsRepository.getForTransaction('source-sms-round-trip');
    expect(restored, isNotNull);
    expect(restored!.body, 'ETB 125.00 was paid to Example Store.');
    expect(restored.senderAddress, 'CBE');
    expect(restored.messageId, '42');

    final resolved =
        await TransactionSmsSourceService().resolve(restoredTransaction!);
    expect(resolved, isNotNull);
    expect(resolved!.body, 'ETB 125.00 was paid to Example Store.');
  });

  test('filtered exports include source SMS only for selected transactions',
      () async {
    for (final transaction in [
      Transaction(
        amount: 10,
        reference: 'included-source',
        bankId: 1,
        type: 'DEBIT',
      ),
      Transaction(
        amount: 20,
        reference: 'excluded-source',
        bankId: 4,
        type: 'DEBIT',
      ),
    ]) {
      await transactionRepository.saveTransaction(
        transaction,
        skipAutoCategorization: true,
      );
      await sourceSmsRepository.upsert(
        TransactionSourceSms(
          transactionReference: transaction.reference,
          body: '${transaction.reference} message',
        ),
      );
    }

    final exported = await DataExportImportService().exportAllData(
      options: const DataExportOptions(bankIds: {1}),
    );
    final payload = jsonDecode(exported) as Map<String, dynamic>;
    final sourceMessages = payload['transactionSourceSms'] as List<dynamic>;

    expect(sourceMessages, hasLength(1));
    expect(
      (sourceMessages.single as Map)['transactionReference'],
      'included-source',
    );
  });
}
