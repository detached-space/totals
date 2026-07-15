import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/legacy_sms_direction_repair.dart';

void main() {
  final bank = Bank(
    id: 1,
    name: 'Commercial Bank of Ethiopia',
    shortName: 'CBE',
    codes: const <String>['CBE'],
    image: '',
  );
  final messageDate = DateTime.parse('2024-02-04T02:34:17.663');
  final parsed = Transaction(
    amount: 5,
    reference: '1_2024-02-04T02:34:17.663',
    type: 'DEBIT',
    bankId: 1,
    accountNumber: '027',
    currentBalance: '43.27',
    time: messageDate.toIso8601String(),
    sourceType: 'sms',
    sourceMessageId: '4524',
    sourceFingerprint: 'fingerprint',
  );

  test('finds an opposite-direction legacy row anchored to the same SMS', () {
    final legacy = _legacyTransaction(messageDate: messageDate);

    expect(
      findLegacySmsDirectionMismatch(
        bank: bank,
        parsed: parsed,
        messageDate: messageDate,
        candidates: <Transaction>[legacy],
      ),
      same(legacy),
    );
  });

  test('disabled legacy repair skips preparing the history index', () {
    expect(
      maybeCreateLegacySmsDirectionRepairIndex(
        enabled: false,
        bank: bank,
        candidates: <Transaction>[
          _legacyTransaction(messageDate: messageDate),
        ],
      ),
      isNull,
    );
  });

  test('does not treat a normal bank reference as a repair candidate', () {
    final legacy = _legacyTransaction(
      messageDate: messageDate,
      reference: 'FT24035ABC',
    );

    expect(
      findLegacySmsDirectionMismatch(
        bank: bank,
        parsed: parsed,
        messageDate: messageDate,
        candidates: <Transaction>[legacy],
      ),
      isNull,
    );
  });

  test('requires account, amount, balance, and time to agree', () {
    final wrongAccount = _legacyTransaction(
      messageDate: messageDate,
      accountNumber: '837',
    );
    final wrongAmount = _legacyTransaction(
      messageDate: messageDate,
      amount: 6,
    );
    final wrongBalance = _legacyTransaction(
      messageDate: messageDate,
      balance: '44.27',
    );
    final wrongTime = _legacyTransaction(
      messageDate: messageDate.add(const Duration(minutes: 3)),
    );

    for (final candidate in <Transaction>[
      wrongAccount,
      wrongAmount,
      wrongBalance,
      wrongTime,
    ]) {
      expect(
        findLegacySmsDirectionMismatch(
          bank: bank,
          parsed: parsed,
          messageDate: messageDate,
          candidates: <Transaction>[candidate],
        ),
        isNull,
      );
    }
  });

  test('refuses ambiguous and already source-backed candidates', () {
    final first = _legacyTransaction(messageDate: messageDate);
    final second = _legacyTransaction(messageDate: messageDate).copyWith(
      note: 'duplicate import',
    );
    final sourceBacked = _legacyTransaction(messageDate: messageDate).copyWith(
      sourceType: 'sms',
      sourceMessageId: 'old-source',
    );

    expect(
      findLegacySmsDirectionMismatch(
        bank: bank,
        parsed: parsed,
        messageDate: messageDate,
        candidates: <Transaction>[first, second],
      ),
      isNull,
    );
    expect(
      findLegacySmsDirectionMismatch(
        bank: bank,
        parsed: parsed,
        messageDate: messageDate,
        candidates: <Transaction>[sourceBacked],
      ),
      isNull,
    );
  });

  test('indexed lookup finds one match in a large imported history', () {
    final legacy = _legacyTransaction(messageDate: messageDate);
    final unrelated = List<Transaction>.generate(4000, (index) {
      final candidateDate = messageDate.add(Duration(minutes: index + 10));
      return _legacyTransaction(
        messageDate: candidateDate,
        accountNumber: '${1000 + index}',
        amount: 10 + index.toDouble(),
        balance: '${100 + index}.00',
      );
    });
    final index = LegacySmsDirectionRepairIndex(
      bank: bank,
      candidates: <Transaction>[...unrelated, legacy],
    );

    expect(
      index.findMismatch(parsed: parsed, messageDate: messageDate),
      same(legacy),
    );
  });

  test('indexed lookup removes a repaired candidate during the same run', () {
    final legacy = _legacyTransaction(messageDate: messageDate);
    final index = LegacySmsDirectionRepairIndex(
      bank: bank,
      candidates: <Transaction>[legacy],
    );

    expect(
      index.findMismatch(parsed: parsed, messageDate: messageDate),
      same(legacy),
    );
    index.remove(legacy);
    expect(
      index.findMismatch(parsed: parsed, messageDate: messageDate),
      isNull,
    );
  });
}

Transaction _legacyTransaction({
  required DateTime messageDate,
  String? reference,
  String accountNumber = '027',
  double amount = 5,
  String balance = '43.27',
}) {
  final time = messageDate.toIso8601String();
  return Transaction(
    amount: amount,
    reference: reference ?? '1_$time',
    type: 'CREDIT',
    bankId: 1,
    accountNumber: accountNumber,
    currentBalance: balance,
    time: time,
  );
}
