import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/shared_expense_recovery_code.dart';
import 'package:totals/services/shared_expense_vault.dart';

void main() {
  group('SharedExpenseVaultCrypto', () {
    // Tiny KDF params so tests don't take 30s. The defaults are 64MB/3it,
    // which is correct for production but unbearably slow inside the test
    // VM. Use deliberately weak params here — these are unit tests, not
    // end-to-end security tests.
    const kdfParams = SharedExpenseVaultKdfParams(
      memoryKb: 1024,
      iterations: 1,
      parallelism: 1,
    );

    test('seal + unseal round-trip recovers identical content', () async {
      final crypto = SharedExpenseVaultCrypto();
      final content = SharedExpenseVaultContent(
        version: 1,
        seedHex: 'a' * 64,
        groupKeys: {
          'group-1': 'b' * 64,
          'group-2': 'c' * 64,
        },
        displayName: 'Khalid',
      );
      final sealed = await crypto.seal(
        pin: '123456',
        content: content,
        kdfParams: kdfParams,
      );
      final back = await crypto.unseal(pin: '123456', sealed: sealed);
      expect(back.seedHex, content.seedHex);
      expect(back.groupKeys, content.groupKeys);
      expect(back.displayName, content.displayName);
    });

    test('wrong pin throws SharedExpenseVaultWrongPinException', () async {
      final crypto = SharedExpenseVaultCrypto();
      final content = SharedExpenseVaultContent(
        version: 1,
        seedHex: 'd' * 64,
        groupKeys: {},
      );
      final sealed = await crypto.seal(
        pin: '111111',
        content: content,
        kdfParams: kdfParams,
      );
      await expectLater(
        () => crypto.unseal(pin: '222222', sealed: sealed),
        throwsA(isA<SharedExpenseVaultWrongPinException>()),
      );
    });

    test('different seals of same content produce different ciphertexts',
        () async {
      // Random salt + random nonce ⇒ two seals must differ.
      final crypto = SharedExpenseVaultCrypto();
      final content = SharedExpenseVaultContent(
        version: 1,
        seedHex: 'e' * 64,
        groupKeys: const {},
      );
      final a = await crypto.seal(
          pin: '424242', content: content, kdfParams: kdfParams);
      final b = await crypto.seal(
          pin: '424242', content: content, kdfParams: kdfParams);
      expect(a.encryptedBlobBase64, isNot(equals(b.encryptedBlobBase64)));
      expect(a.saltBase64, isNot(equals(b.saltBase64)));
    });

    test('SharedExpenseSealedVault json round-trip preserves all fields',
        () async {
      final crypto = SharedExpenseVaultCrypto();
      final content = SharedExpenseVaultContent(
        version: 1,
        seedHex: 'f' * 64,
        groupKeys: {'g': '1' * 64},
      );
      final sealed = await crypto.seal(
          pin: '555555', content: content, kdfParams: kdfParams);
      final json = sealed.toJson();
      final recovered = SharedExpenseSealedVault.fromJson(json);
      final back = await crypto.unseal(pin: '555555', sealed: recovered);
      expect(back.seedHex, content.seedHex);
      expect(back.groupKeys, content.groupKeys);
    });
  });

  group('SharedExpenseRecoveryCode', () {
    test('generated codes are well-formed', () {
      for (var i = 0; i < 100; i++) {
        final code = SharedExpenseRecoveryCode.generate();
        expect(SharedExpenseRecoveryCode.isWellFormed(code), isTrue,
            reason: 'should be well-formed: $code');
        expect(code.length, SharedExpenseRecoveryCode.wireLength);
      }
    });

    test('format adds dashes and uppercases', () {
      final code = SharedExpenseRecoveryCode.generate();
      final pretty = SharedExpenseRecoveryCode.format(code);
      expect(pretty,
          matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')));
    });

    test('format → normalize round-trip', () {
      final code = SharedExpenseRecoveryCode.generate();
      final pretty = SharedExpenseRecoveryCode.format(code);
      final normalized = SharedExpenseRecoveryCode.normalizeForWire(pretty);
      expect(normalized, code);
    });

    test('confusable chars are coerced (I→1, L→1, O→0)', () {
      // Generate a code, replace internal chars with confusables, expect
      // the normalized form to match the originals via coercion.
      final original = SharedExpenseRecoveryCode.generate();
      final pretty = SharedExpenseRecoveryCode.format(original).toUpperCase();
      final swapped = pretty.replaceAll('0', 'O').replaceAll('1', 'I');
      // Coercion should put it back exactly as before — and check char
      // should match because internal body is the same.
      final normalized = SharedExpenseRecoveryCode.normalizeForWire(swapped);
      expect(normalized, original);
    });

    test('flipped char fails validation', () {
      final code = SharedExpenseRecoveryCode.generate();
      // Flip a middle entropy char to a different alphabet char. The check
      // should no longer match.
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      const flipAt = 7;
      final original = code[flipAt];
      final replacement = alphabet
          .split('')
          .firstWhere((c) => c.toLowerCase() != original.toLowerCase());
      final tampered = '${code.substring(0, flipAt)}'
          '${replacement.toLowerCase()}'
          '${code.substring(flipAt + 1)}';
      expect(SharedExpenseRecoveryCode.isWellFormed(tampered), isFalse);
    });

    test('invalid characters fail validation', () {
      expect(SharedExpenseRecoveryCode.isWellFormed('not-a-code-12345'),
          isFalse);
      expect(SharedExpenseRecoveryCode.isWellFormed(''), isFalse);
      expect(SharedExpenseRecoveryCode.isWellFormed('UUUUUUUUUUUUUUUU'),
          isFalse,
          reason: 'U is excluded from Crockford base32');
    });
  });
}
