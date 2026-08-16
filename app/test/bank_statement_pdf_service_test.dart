import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/bank_statement_description_service.dart';
import 'package:totals/services/bank_statement_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BankStatementData', () {
    test('filters the selected range and derives statement balances', () {
      final statement = BankStatementData.fromTransactions(
        bankName: 'Commercial Bank Of Ethiopia',
        bankShortName: 'CBE',
        bankIconAssetPath: 'assets/images/cbe.png',
        accountNumber: '1000399285678',
        accountHolderName: 'Yew',
        startDate: DateTime(2026, 1, 10),
        endDate: DateTime(2026, 1, 31),
        generatedAt: DateTime(2026, 3, 28),
        currentAccountBalance: 1065,
        descriptionsByReference: const {
          'debit-in-range': 'CBE Successful merchant payment',
        },
        transactions: [
          Transaction(
            amount: 100,
            reference: 'credit-before-range',
            creditor: 'Employer',
            time: DateTime(2026, 1, 1, 8).toIso8601String(),
            currentBalance: 'ETB 1,100.00',
            type: 'CREDIT',
          ),
          Transaction(
            amount: 50,
            serviceCharge: 3,
            vat: 2,
            reference: 'debit-in-range',
            receiver: 'Merchant',
            note: 'Groceries',
            time: DateTime(2026, 1, 15, 12).toIso8601String(),
            currentBalance: '1,045.00',
            type: 'DEBIT',
          ),
          Transaction(
            amount: 20,
            reference: 'credit-after-range',
            creditor: 'Friend',
            time: DateTime(2026, 2, 1, 9).toIso8601String(),
            currentBalance: '1,065.00',
            type: 'CREDIT',
          ),
        ],
      );

      expect(statement.entries, hasLength(1));
      expect(
        statement.entries.single.description,
        'CBE Successful merchant payment',
      );
      expect(statement.entries.single.reference, 'debit-in-range');
      expect(statement.openingBalance, 1100);
      expect(statement.totalDebit, 55);
      expect(statement.totalCredit, 0);
      expect(statement.closingBalance, 1045);
      expect(statement.fileName, 'statement-CBE-2026-03-28.pdf');
    });

    test('derives missing running balances from the current account balance',
        () {
      final statement = BankStatementData.fromTransactions(
        bankName: 'Awash Bank',
        bankShortName: 'Awash',
        bankIconAssetPath: 'assets/images/awash.png',
        accountNumber: '1234',
        accountHolderName: 'Account holder',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
        generatedAt: DateTime(2026, 2, 1),
        currentAccountBalance: 1080,
        transactions: [
          Transaction(
            amount: 100,
            reference: 'credit',
            time: DateTime(2026, 1, 1).toIso8601String(),
            type: 'CREDIT',
          ),
          Transaction(
            amount: 20,
            reference: 'debit',
            time: DateTime(2026, 1, 2).toIso8601String(),
            type: 'DEBIT',
          ),
        ],
      );

      expect(statement.openingBalance, 1000);
      expect(statement.entries.first.balance, 1100);
      expect(statement.entries.last.balance, 1080);
      expect(statement.entries.first.description, 'Credit transaction');
      expect(statement.entries.last.description, 'Debit transaction');
      expect(statement.closingBalance, 1080);
    });

    test('keeps balances unchanged for an empty selected period', () {
      final statement = BankStatementData.fromTransactions(
        bankName: 'Commercial Bank Of Ethiopia',
        bankShortName: 'CBE',
        bankIconAssetPath: 'assets/images/cbe.png',
        accountNumber: '1234',
        accountHolderName: 'Account holder',
        startDate: DateTime(2026, 2, 1),
        endDate: DateTime(2026, 2, 28),
        generatedAt: DateTime(2026, 3, 1),
        currentAccountBalance: 1100,
        transactions: [
          Transaction(
            amount: 100,
            reference: 'credit',
            time: DateTime(2026, 1, 1).toIso8601String(),
            currentBalance: '1,100.00',
            type: 'CREDIT',
          ),
        ],
      );

      expect(statement.entries, isEmpty);
      expect(statement.openingBalance, 1100);
      expect(statement.closingBalance, 1100);
    });
  });

  group('statement pattern descriptions', () {
    test('uses the first matching regex pattern name and removes fallback', () {
      final name = findBankStatementPatternName(
        bankId: 1,
        messageBody: 'Your account was debited with ETB 100.00.',
        patterns: [
          SmsPattern(
            bankId: 2,
            senderId: 'OTHER',
            regex: r'debited',
            type: 'DEBIT',
            description: 'Wrong bank',
          ),
          SmsPattern(
            bankId: 1,
            senderId: 'CBE',
            regex: r'debited with ETB \d+\.\d{2}',
            type: 'DEBIT',
            description: 'Fallback CBE account debit',
          ),
          SmsPattern(
            bankId: 1,
            senderId: 'CBE',
            regex: r'debited',
            type: 'DEBIT',
            description: 'Later matching pattern',
          ),
        ],
      );

      expect(name, 'CBE account debit');
    });

    test('returns null when the source message has no matching pattern', () {
      expect(
        findBankStatementPatternName(
          bankId: 1,
          messageBody: 'Unrelated message',
          patterns: [
            SmsPattern(
              bankId: 1,
              senderId: 'CBE',
              regex: r'credited',
              type: 'CREDIT',
              description: 'CBE account credit',
            ),
          ],
        ),
        isNull,
      );
    });

    test('reports completion when there are no descriptions to resolve',
        () async {
      final progress = <BankStatementDescriptionProgress>[];

      final result =
          await BankStatementDescriptionService().resolveDescriptions(
        const <Transaction>[],
        onProgress: progress.add,
      );

      expect(result, isEmpty);
      expect(progress, hasLength(1));
      expect(
        progress.single.stage,
        BankStatementDescriptionProgressStage.complete,
      );
      expect(progress.single.value, 1);
    });
  });

  test('generates a PDF containing the Totals destination link', () async {
    final statement = BankStatementData.fromTransactions(
      bankName: 'Commercial Bank Of Ethiopia',
      bankShortName: 'CBE',
      bankIconAssetPath: 'assets/images/cbe.png',
      accountNumber: '1000399285678',
      accountHolderName: 'Yew',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
      generatedAt: DateTime(2026, 3, 28),
      currentAccountBalance: 1100,
      transactions: [
        Transaction(
          amount: 100,
          reference: 'credit',
          creditor: 'Employer',
          time: DateTime(2026, 1, 1).toIso8601String(),
          currentBalance: '1,100.00',
          type: 'CREDIT',
        ),
      ],
    );

    final progress = <BankStatementPdfProgress>[];
    final bytes = await BankStatementPdfService().generate(
      statement,
      onProgress: progress.add,
    );
    final documentText = latin1.decode(bytes, allowInvalid: true);

    expect(progress, isNotEmpty);
    expect(
      progress.map((event) => event.value),
      orderedEquals(
        progress.map((event) => event.value).toList()..sort(),
      ),
    );
    expect(
      progress.any(
        (event) =>
            event.stage ==
                BankStatementPdfProgressStage.processingTransactions &&
            event.processed == 1 &&
            event.total == 1,
      ),
      isTrue,
    );
    expect(
      progress.any(
        (event) =>
            event.stage == BankStatementPdfProgressStage.layingOutPages &&
            event.processed == 1 &&
            event.total == 1,
      ),
      isTrue,
    );
    expect(progress.last.stage, BankStatementPdfProgressStage.complete);
    expect(progress.last.value, 1);
    expect(documentText.startsWith('%PDF-'), isTrue);
    expect(documentText, contains(totalsStatementUrl));
    expect(
      RegExp(r'/Subtype\s*/Image').allMatches(documentText).length,
      greaterThanOrEqualTo(2),
    );
    expect(bytes.length, greaterThan(10000));
  });
}
