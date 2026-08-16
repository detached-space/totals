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
}
