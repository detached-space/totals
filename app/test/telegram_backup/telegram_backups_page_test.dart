import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/telegram_backup_page.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';

void main() {
  Widget testApp(Widget home) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp(home: home),
    );
  }

  List<TelegramBackupEntry> createBackups(int count) {
    return List.generate(
      count,
      (index) => TelegramBackupEntry(
        id: 'backup-$index',
        createdAt: DateTime.utc(2026, 7, 24).subtract(Duration(days: index)),
        fileName: 'backup-$index.totals',
        fileSize: 100 + index,
        sha256: 'sha-$index',
        exportSchemaVersion: 1,
        fileId: 'file-$index',
        messageId: index + 1,
      ),
    );
  }

  testWidgets('overview shows four newest backups and a show more action',
      (tester) async {
    final backups = createBackups(6);
    var showMorePressed = false;

    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: TelegramBackupListPreview(
              backups: backups,
              restoringId: null,
              onRestore: (_) async {},
              onShowMore: () => showMorePressed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Restore'), findsNWidgets(4));
    expect(find.text('100 B · Schema v1'), findsOneWidget);
    expect(find.text('103 B · Schema v1'), findsOneWidget);
    expect(find.text('104 B · Schema v1'), findsNothing);
    expect(find.text('Show more backups'), findsOneWidget);

    await tester.tap(find.text('Show more backups'));
    expect(showMorePressed, isTrue);
  });

  testWidgets('full backups page shows every backup and supports restore',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backups = createBackups(6);
    String? restoredId;

    await tester.pumpWidget(
      testApp(
        TelegramBackupsPage(
          backups: backups,
          onRestore: (entry) async {
            restoredId = entry.id;
          },
        ),
      ),
    );

    expect(find.text('Backups in Telegram'), findsOneWidget);
    expect(find.text('Restore'), findsNWidgets(6));
    expect(find.text('105 B · Schema v1'), findsOneWidget);

    await tester.tap(find.text('Restore').last);
    await tester.pump();

    expect(restoredId, 'backup-5');
    expect(tester.takeException(), isNull);
  });
}
