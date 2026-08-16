import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:totals/_redesign/widgets/telegram_recovery_key_dialog.dart';

void main() {
  testWidgets(
    'validates locally and completes only after the dialog is removed',
    (tester) async {
      String? result;
      var completed = false;
      final recoveryKey = List.filled(16, '0123').join('-');

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showTelegramRecoveryKeyDialog(
                    context: context,
                    title: 'Recovery key needed',
                    description: 'Enter the key for the existing catalog.',
                    recoveryKeyLabel: 'Recovery key',
                    invalidKeyMessage: 'Invalid recovery key',
                    chooseFileLabel: 'Upload recovery key .txt',
                    invalidFileMessage: 'Invalid recovery key file',
                    fileReadErrorMessage: 'Could not read recovery key file',
                    cancelLabel: 'Cancel',
                    connectLabel: 'Connect',
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'not-a-key');
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(find.text('Invalid recovery key'), findsOneWidget);
      expect(find.byType(TelegramRecoveryKeyDialog), findsOneWidget);
      expect(completed, isFalse);

      await tester.enterText(find.byType(TextFormField), recoveryKey);
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(
        find.byType(TelegramRecoveryKeyDialog, skipOffstage: false),
        findsOneWidget,
      );
      expect(completed, isFalse);

      await tester.pumpAndSettle();

      expect(
        find.byType(TelegramRecoveryKeyDialog, skipOffstage: false),
        findsNothing,
      );
      expect(completed, isTrue);
      expect(result, recoveryKey);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a saved recovery key text file connects without manual entry',
      (tester) async {
    String? result;
    var completed = false;
    final recoveryKey = List.filled(16, 'ABCD').join('-');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showTelegramRecoveryKeyDialog(
                  context: context,
                  title: 'Recovery key needed',
                  description: 'Enter the key for the existing catalog.',
                  recoveryKeyLabel: 'Recovery key',
                  invalidKeyMessage: 'Invalid recovery key',
                  chooseFileLabel: 'Upload recovery key .txt',
                  invalidFileMessage: 'Invalid recovery key file',
                  fileReadErrorMessage: 'Could not read recovery key file',
                  cancelLabel: 'Cancel',
                  connectLabel: 'Connect',
                  pickRecoveryKeyFile: () async {
                    return 'Totals Telegram Backup recovery key\n\n'
                        '$recoveryKey\n\n'
                        'Keep this file private and separate from your phone.';
                  },
                );
                completed = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload recovery key .txt'));
    await tester.pump();

    expect(completed, isFalse);
    expect(
      find.byType(TelegramRecoveryKeyDialog, skipOffstage: false),
      findsOneWidget,
    );

    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, recoveryKey);
    expect(
      find.byType(TelegramRecoveryKeyDialog, skipOffstage: false),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid text file stays in the recovery prompt',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showTelegramRecoveryKeyDialog(
                  context: context,
                  title: 'Recovery key needed',
                  description: 'Enter the key for the existing catalog.',
                  recoveryKeyLabel: 'Recovery key',
                  invalidKeyMessage: 'Invalid recovery key',
                  chooseFileLabel: 'Upload recovery key .txt',
                  invalidFileMessage: 'Invalid recovery key file',
                  fileReadErrorMessage: 'Could not read recovery key file',
                  cancelLabel: 'Cancel',
                  connectLabel: 'Connect',
                  pickRecoveryKeyFile: () async => 'ordinary text',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload recovery key .txt'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid recovery key file'), findsOneWidget);
    expect(find.byType(TelegramRecoveryKeyDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('extracts only a valid recovery key from the saved text format', () {
    const key = '0123-4567-89AB-CDEF-0123-4567-89AB-CDEF-'
        '0123-4567-89AB-CDEF-0123-4567-89AB-CDEF';

    expect(
      extractTelegramRecoveryKeyFromText(
        'Totals Telegram Backup recovery key\n\n$key\n\nKeep this private.',
      ),
      key,
    );
    expect(
      extractTelegramRecoveryKeyFromText('not a recovery key'),
      isNull,
    );
  });
}
