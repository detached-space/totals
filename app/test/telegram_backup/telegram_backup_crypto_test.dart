import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/telegram_backup/telegram_backup_crypto.dart';

void main() {
  group('TelegramBackupCrypto', () {
    test('generates and formats a 256-bit recovery key', () {
      final crypto = TelegramBackupCrypto(random: Random(7));

      final key = crypto.generateRecoveryKey();
      final formatted = crypto.formatRecoveryKey(key);

      expect(key, hasLength(64));
      expect(
        key.codeUnits.every(
          (code) => (code >= 48 && code <= 57) || (code >= 65 && code <= 70),
        ),
        isTrue,
      );
      expect(formatted.split('-'), hasLength(16));
      expect(TelegramBackupCrypto.isRecoveryKeyFormatValid(formatted), isTrue);
      expect(
        TelegramBackupCrypto.isRecoveryKeyFormatValid('not-a-recovery-key'),
        isFalse,
      );
      expect(crypto.normalizeRecoveryKey(formatted), key);
    });

    test('round trips compressed backup bytes', () async {
      final crypto = TelegramBackupCrypto(random: Random(9));
      final key = crypto.generateRecoveryKey();
      final original = utf8.encode(
        jsonEncode({
          'schemaVersion': 9,
          'transactions': List.generate(
            100,
            (index) => {'reference': 'REF-$index', 'amount': index + 0.5},
          ),
        }),
      );

      final encrypted = await crypto.encrypt(
        original,
        recoveryKey: key,
        contentType: TelegramBackupCrypto.backupContentType,
      );
      final decrypted = await crypto.decrypt(
        encrypted,
        recoveryKey: key,
        expectedContentType: TelegramBackupCrypto.backupContentType,
      );

      expect(decrypted, original);
      expect(utf8.decode(encrypted), isNot(contains('REF-42')));
    });

    test('rejects a different recovery key', () async {
      final crypto = TelegramBackupCrypto(random: Random(11));
      final key = crypto.generateRecoveryKey();
      final wrongKey = TelegramBackupCrypto(
        random: Random(12),
      ).generateRecoveryKey();
      final encrypted = await crypto.encrypt(
        utf8.encode('private totals data'),
        recoveryKey: key,
        contentType: TelegramBackupCrypto.catalogContentType,
      );

      expect(
        () => crypto.decrypt(
          encrypted,
          recoveryKey: wrongKey,
          expectedContentType: TelegramBackupCrypto.catalogContentType,
        ),
        throwsA(
          isA<TelegramBackupCryptoException>().having(
            (error) => error.message,
            'message',
            contains('recovery key'),
          ),
        ),
      );
    });

    test('binds ciphertext to its declared content type', () async {
      final crypto = TelegramBackupCrypto(random: Random(13));
      final key = crypto.generateRecoveryKey();
      final encrypted = await crypto.encrypt(
        utf8.encode('catalog'),
        recoveryKey: key,
        contentType: TelegramBackupCrypto.catalogContentType,
      );

      expect(
        () => crypto.decrypt(
          encrypted,
          recoveryKey: key,
          expectedContentType: TelegramBackupCrypto.backupContentType,
        ),
        throwsA(isA<TelegramBackupCryptoException>()),
      );
    });
  });
}
