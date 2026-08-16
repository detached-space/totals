import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/data_export_import_service.dart';

void main() {
  test('default export options preserve the legacy full-backup behavior', () {
    const options = DataExportOptions();

    expect(options.isFullBackup, isTrue);
    expect(options.includesBank(1), isTrue);
    expect(options.includeQuickAccessAccounts, isTrue);
    expect(options.toJson()['scope'], 'full');
    expect(options.toJson()['includeQuickAccessAccounts'], isTrue);
    expect(options.toJson().containsKey('includeSmsPatterns'), isFalse);
  });

  test('custom export options filter banks and transaction dates safely', () {
    final options = DataExportOptions(
      bankIds: const {1},
      transactionStart: DateTime.utc(2026, 1, 1),
      transactionEnd: DateTime.utc(2026, 1, 31, 23, 59, 59, 999),
      includeAutoCategorization: false,
      includeQuickAccessAccounts: false,
    );

    Transaction transaction({
      required int bankId,
      required String time,
      required String reference,
    }) {
      return Transaction(
        amount: 10,
        reference: reference,
        bankId: bankId,
        time: time,
      );
    }

    expect(options.isFullBackup, isFalse);
    expect(options.toJson()['includeQuickAccessAccounts'], isFalse);
    expect(
      options.includesTransaction(
        transaction(
          bankId: 1,
          time: '2026-01-15T12:00:00.000Z',
          reference: 'included',
        ),
      ),
      isTrue,
    );
    expect(
      options.includesTransaction(
        transaction(
          bankId: 2,
          time: '2026-01-15T12:00:00.000Z',
          reference: 'wrong-bank',
        ),
      ),
      isFalse,
    );
    expect(
      options.includesTransaction(
        transaction(
          bankId: 1,
          time: '2026-02-01T00:00:00.000Z',
          reference: 'outside-range',
        ),
      ),
      isFalse,
    );
    expect(
      options.includesTransaction(
        transaction(
          bankId: 1,
          time: 'legacy-unreadable-date',
          reference: 'undated-safety-row',
        ),
      ),
      isTrue,
    );
  });

  test('custom export metadata is optional and import-compatible', () {
    final normalized = DataExportImportService.normalizeImportPayload(
      jsonEncode({
        'schemaVersion': 9,
        'exportOptions': {
          'scope': 'custom',
          'bankIds': [1, 4],
          'includeAutoCategorization': false,
        },
        'accounts': const [],
        'transactions': const [],
      }),
    );

    expect(normalized['schemaVersion'], 9);
    expect(
      (normalized['exportOptions'] as Map<String, dynamic>)['scope'],
      'custom',
    );
    expect(normalized['autoCategoryRules'], isEmpty);
    expect(normalized['banks'], isEmpty);
  });

  test('import selection filters bank data but keeps shared definitions', () {
    final prepared = DataExportImportService.prepareImportPayload(
      jsonEncode({
        'schemaVersion': 9,
        'banks': [
          {
            'id': 1,
            'name': 'CBE',
            'shortName': 'CBE',
            'codes': const [],
            'image': '',
          },
          {
            'id': 4,
            'name': 'Dashen',
            'shortName': 'Dashen',
            'codes': const [],
            'image': '',
          },
        ],
        'categories': [
          {'id': 10, 'name': 'Food', 'flow': 'expense'},
        ],
        'accounts': [
          {
            'accountNumber': '1000',
            'bank': 1,
            'balance': 10,
            'accountHolderName': 'One',
          },
          {
            'accountNumber': '4000',
            'bank': 4,
            'balance': 20,
            'accountHolderName': 'Four',
          },
        ],
        'transactions': [
          {
            'amount': 1,
            'reference': 'cbe-row',
            'bankId': 1,
          },
          {
            'amount': 4,
            'reference': 'dashen-row',
            'bankId': 4,
          },
        ],
        'transactionSourceSms': [
          {
            'transactionReference': 'cbe-row',
            'body': 'CBE source message',
          },
          {
            'transactionReference': 'dashen-row',
            'body': 'Dashen source message',
          },
        ],
        'budgets': [
          {'name': 'Monthly'},
        ],
        'autoCategoryRules': [
          {'counterparty': 'Shop', 'categoryId': 10},
        ],
      }),
      options: const DataImportOptions(
        bankIds: {1},
        includeBudgets: false,
        includeAutoCategorization: false,
      ),
    );

    expect(prepared['banks'], hasLength(2));
    expect(prepared['categories'], hasLength(1));
    expect(
      ((prepared['accounts'] as List).single as Map)['bank'],
      1,
    );
    expect(
      ((prepared['transactions'] as List).single as Map)['reference'],
      'cbe-row',
    );
    expect(
      ((prepared['transactionSourceSms'] as List).single
          as Map)['transactionReference'],
      'cbe-row',
    );
    expect(prepared['budgets'], isEmpty);
    expect(prepared['autoCategoryRules'], isEmpty);
  });

  test('backup inspection supports filtered and legacy-compatible payloads',
      () {
    final summary = DataExportImportService.inspectImportPayload(
      jsonEncode({
        'schemaVersion': 9,
        'exportDate': '2026-07-24T12:00:00.000Z',
        'exportOptions': {'scope': 'custom'},
        'banks': [
          {
            'id': 1,
            'name': 'Commercial Bank of Ethiopia',
            'shortName': 'CBE',
            'codes': const [],
            'image': '',
          },
        ],
        'accounts': [
          {
            'accountNumber': '1000',
            'bank': 1,
            'balance': 10,
            'accountHolderName': 'One',
          },
        ],
        'userAccounts': [
          {
            'accountNumber': '1000',
            'bankId': 1,
            'accountHolderName': 'One',
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ],
        'transactions': [
          {
            'amount': 1,
            'reference': 'cbe-row',
            'bankId': 1,
          },
        ],
      }),
    );

    expect(summary.schemaVersion, 9);
    expect(summary.isFilteredExport, isTrue);
    expect(summary.banks, hasLength(1));
    expect(summary.banks.single.name, 'Commercial Bank of Ethiopia');
    expect(summary.banks.single.accountCount, 1);
    expect(summary.banks.single.transactionCount, 1);
  });

  test('backup inspection labels the synthetic cash bank as Cash Wallet', () {
    final summary = DataExportImportService.inspectImportPayload(
      jsonEncode({
        'schemaVersion': 9,
        'accounts': [
          {
            'accountNumber': 'CASH',
            'bank': 100,
            'balance': 25,
            'accountHolderName': 'Cash Wallet',
          },
        ],
        'transactions': [
          {
            'amount': 5,
            'reference': 'cash-row',
            'bankId': 100,
          },
        ],
      }),
    );

    expect(summary.banks, hasLength(1));
    expect(summary.banks.single.id, 100);
    expect(summary.banks.single.name, 'Cash Wallet');
    expect(summary.banks.single.shortName, 'Cash Wallet');
  });

  test('v9 backup keeps durable owner and strips device-local SIM metadata',
      () {
    final normalized = DataExportImportService.normalizeImportPayload(
      jsonEncode({
        'schemaVersion': 9,
        'accounts': [
          {
            'accountNumber': '0911000001',
            'bank': 6,
            'accountHolderName': 'First owner',
            'balance': 10,
            'smsSubscriptionId': 2,
            'isDefault': true,
          },
        ],
        'transactions': [
          {
            'amount': 5,
            'reference': 'portable-owner',
            'bankId': 6,
            'accountNumber': '251911000002',
            'ownerAccountNumber': '0911000001',
            'ownerAssignmentSource': Transaction.manualOwnerAssignment,
            'sourceSubscriptionId': 2,
          },
        ],
      }),
    );

    expect(DataExportImportService.currentSchemaVersion, 11);
    expect(normalized['schemaVersion'], 9);

    final account = Map<String, dynamic>.from(
      (normalized['accounts'] as List).single as Map,
    );
    expect(account['accountNumber'], '0911000001');
    expect(account['isDefault'], isTrue);
    expect(account.containsKey('smsSubscriptionId'), isFalse);

    final transaction = Map<String, dynamic>.from(
      (normalized['transactions'] as List).single as Map,
    );
    expect(transaction['ownerAccountNumber'], '0911000001');
    expect(
      transaction['ownerAssignmentSource'],
      Transaction.manualOwnerAssignment,
    );
    expect(transaction['accountNumber'], '251911000002');
    expect(transaction.containsKey('sourceSubscriptionId'), isFalse);
  });

  test('schema-less ownership payload is recognized as the current schema', () {
    final normalized = DataExportImportService.normalizeImportPayload(
      jsonEncode({
        'transactions': [
          {
            'amount': 1,
            'reference': 'implicit-v9',
            'ownerAccountNumber': '0911000001',
          },
        ],
      }),
    );

    expect(normalized['schemaVersion'], 11);
    expect(
      ((normalized['transactions'] as List).single
          as Map)['ownerAccountNumber'],
      '0911000001',
    );
  });

  test('source SMS aliases normalize as portable schema v11 records', () {
    final normalized = DataExportImportService.normalizeImportPayload(
      jsonEncode({
        'transactions': [
          {
            'amount': 1,
            'reference': 'source-row',
          },
        ],
        'transaction_source_sms': [
          {
            'transactionReference': 'source-row',
            'body': 'Original SMS body',
            'senderAddress': 'BANK',
          },
        ],
      }),
    );

    expect(normalized['schemaVersion'], 11);
    final sourceSms =
        (normalized['transactionSourceSms'] as List<dynamic>).single as Map;
    expect(sourceSms['transactionReference'], 'source-row');
    expect(sourceSms['body'], 'Original SMS body');
  });

  test(
      'reimbursement links are normalized and kept only with both transactions',
      () {
    final prepared = DataExportImportService.prepareImportPayload(
      jsonEncode({
        'schemaVersion': 10,
        'transactions': [
          {
            'amount': 500,
            'reference': 'reimbursement',
            'bankId': 1,
            'type': 'CREDIT',
          },
          {
            'amount': 1000,
            'reference': 'included-expense',
            'bankId': 1,
            'type': 'DEBIT',
          },
          {
            'amount': 1000,
            'reference': 'excluded-expense',
            'bankId': 4,
            'type': 'DEBIT',
          },
        ],
        'reimbursement_allocations': [
          {
            'reimbursementTransactionReference': 'reimbursement',
            'expenseTransactionReference': 'included-expense',
            'appliedAmount': 400,
          },
          {
            'reimbursementTransactionReference': 'reimbursement',
            'expenseTransactionReference': 'excluded-expense',
            'appliedAmount': 100,
          },
        ],
      }),
      options: const DataImportOptions(bankIds: {1}),
    );

    expect(prepared['schemaVersion'], 10);
    expect(prepared['transactions'], hasLength(2));
    final allocations = prepared['reimbursementAllocations'] as List<dynamic>;
    expect(allocations, hasLength(1));
    expect(
      (allocations.single as Map)['expenseTransactionReference'],
      'included-expense',
    );
  });
}
