import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_detection_service.dart';

void main() {
  final bank = Bank(
    id: 6,
    name: 'Telebirr',
    shortName: 'Telebirr',
    codes: const <String>['127'],
    image: '',
  );

  test('detected banks rank and cache holder-name suggestions', () async {
    final data = DetectedBankData(
      bank: bank,
      senderAddress: '127',
      messageCount: 3,
    )
      ..addHolderSuggestion('KIDIST')
      ..addHolderSuggestion('kidist')
      ..addHolderSuggestion('EYOSIAS');

    expect(data.accountHolderSuggestions, <String>['KIDIST', 'EYOSIAS']);

    final detected = DetectedBank(
      bank: bank,
      senderAddress: data.senderAddress,
      messageCount: data.messageCount,
      accountHolderSuggestions: data.accountHolderSuggestions,
      holderSuggestionsScanned: true,
    );
    final restored = await DetectedBank.fromJson(
      detected.toJson(),
      <Bank>[bank],
    );

    expect(restored, isNotNull);
    expect(restored!.suggestedAccountHolderName, 'KIDIST');
    expect(restored.holderSuggestionsScanned, isTrue);
  });

  test('legacy detected-bank cache requests one suggestion rescan', () async {
    final restored = await DetectedBank.fromJson(
      <String, dynamic>{
        'bankId': bank.id,
        'senderAddress': '127',
        'messageCount': 1,
        'lastMessageDate': null,
      },
      <Bank>[bank],
    );

    expect(restored, isNotNull);
    expect(restored!.accountHolderSuggestions, isEmpty);
    expect(restored.holderSuggestionsScanned, isFalse);
  });
}
