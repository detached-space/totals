import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/sms_message_classifier.dart';

void main() {
  test('classifies Telebirr ATM authorization notices as non-transactions', () {
    const body =
        'Dear Customer, Your ATM withdraw secret code is 671826 with amount '
        'of ETB 1,000.00.';

    expect(SmsMessageClassifier.isTelebirrAtmAuthorization(body), isTrue);
    expect(
      SmsMessageClassifier.telebirrAtmAuthorizationCode(body),
      '671826',
    );
  });

  test('does not classify the completed ATM withdrawal as authorization', () {
    expect(
      SmsMessageClassifier.isTelebirrAtmAuthorization(
        'Dear EYOSIAS The request to withdraw ETB 1,000.00 from your '
        'telebirr account 251957063583 via secret code 671826 using an ATM '
        'with transaction number CFS07I3GTC is successfully completed.',
      ),
      isFalse,
    );
  });

  test('classifies a Telebirr airtime receipt as a non-ledger message', () {
    const body = '''Dear Customer
You have received ETB 50.00 airtime from 251920945085 on 14/04/2026 11:13:19.
Your transaction number is DDE1UM6GVL.
Thank you for using telebirr''';

    expect(SmsMessageClassifier.isTelebirrAirtimeReceipt(body), isTrue);
    expect(
      SmsMessageClassifier.telebirrAirtimeReceiptReference(body),
      'DDE1UM6GVL',
    );
  });

  test('keeps the sender-side airtime recharge as a debit transaction', () {
    const body = '''Dear KIDIST
You have recharged ETB 50.00 airtime for 920945085 on 14/04/2026 11:13:19.
Your transaction number is DDE1UM6GVL. Your current balance is ETB 1,742.84.''';

    expect(SmsMessageClassifier.isTelebirrAirtimeReceipt(body), isFalse);
  });

  test('classifies a Telebirr Endekise notice as a non-ledger credit line', () {
    const body = '''Dear Yeabsira
Your transaction is successfully completed using Endekise.
You have used ETB 16.16 credit amount on this transaction.
The service fee is ETB 0.40 and the daily fee will be 22.95 depending on your credit limit.
Your outstanding amount is ETB 3168.62 with due date of 2026-09-22 00:00:00.
Your Contract number is 27825413.
Thank you for using telebirr Ethio telecom in partnership with Dashen Bank''';

    expect(SmsMessageClassifier.isTelebirrCreditLineNotice(body), isTrue);
    expect(SmsMessageClassifier.reportsLiabilityOutstanding(body), isTrue);
    expect(SmsMessageClassifier.isTelebirrNonLedgerNotice(body), isTrue);
  });

  test('does not treat an E-Money wallet SMS as Endekise credit', () {
    const body =
        'Dear Yeabsira Your current E-Money Account balance is ETB 0.00. '
        'To download your payment information please click this link: '
        'https://transactioninfo.ethiotelecom.et/receipt/DHO84EG3D8';

    expect(SmsMessageClassifier.isTelebirrCreditLineNotice(body), isFalse);
    expect(SmsMessageClassifier.reportsLiabilityOutstanding(body), isFalse);
    expect(SmsMessageClassifier.isTelebirrNonLedgerNotice(body), isFalse);
  });

  test('classifies Endekise repayment SMS as a debit, not income', () {
    const body =
        'You have successfully paid a credit amount of ETB 3260.71 on '
        '2026-08-20 09:54:23. Your current outstanding credit amount ETB 0.00 '
        'Thank you for using telebirr Ethio telecom';

    expect(SmsMessageClassifier.isTelebirrCreditLineRepayment(body), isTrue);
    expect(SmsMessageClassifier.isTelebirrCreditLineActivity(body), isTrue);
    expect(SmsMessageClassifier.reportsLiabilityOutstanding(body), isTrue);
    expect(SmsMessageClassifier.isTelebirrCreditLineNotice(body), isFalse);
    expect(SmsMessageClassifier.isTelebirrNonLedgerNotice(body), isFalse);
    expect(SmsMessageClassifier.extractCreditLineOutstanding(body), 0.00);
  });

  test('extracts Endekise outstanding from a draw notice', () {
    const body = '''Dear Yeabsira
Your transaction is successfully completed using Endekise.
You have used ETB 16.16 credit amount on this transaction.
Your outstanding amount is ETB 3168.62 with due date of 2026-09-22 00:00:00.''';

    expect(SmsMessageClassifier.extractCreditLineOutstanding(body), 3168.62);
  });

  test('does not treat a received transfer as a credit-line repayment', () {
    const body =
        'Dear Yeabsira, You have received ETB 5,000.00 by transaction number '
        'DHK00F419G on 2026-08-20 09:54:22 from Commercial Bank of Ethiopia '
        'to your telebirr Account 251942405303. Your current balance is ETB 5,000.00.';

    expect(SmsMessageClassifier.isTelebirrCreditLineRepayment(body), isFalse);
    expect(SmsMessageClassifier.isTelebirrCreditLineActivity(body), isFalse);
  });
}
