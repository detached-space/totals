import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/feature_discovery_page.dart';
import 'package:totals/_redesign/widgets/feature_preview_sheet.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString:
          '$tutorialsBucketUrlEnvironmentKey=https://tutorials.example.invalid',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('lists tutorials and opens the selected preview', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(initialThemeMode: ThemeMode.system),
        child: const MaterialApp(home: FeatureDiscoveryPage()),
      ),
    );

    expect(find.text('Discover Totals'), findsOneWidget);
    expect(find.text('Auto-Categorization'), findsOneWidget);
    expect(
      find.text('Future transactions matched automatically'),
      findsOneWidget,
    );
    expect(find.text('Quick Account Access'), findsOneWidget);
    expect(
      find.text('Long-press Shared to find and copy accounts'),
      findsOneWidget,
    );
    expect(find.text('Link Reimbursements'), findsOneWidget);
    expect(
      find.text('Track returned money against past spending'),
      findsOneWidget,
    );
    expect(find.text('Telegram Backup'), findsOneWidget);
    expect(
      find.text('Encrypted backups in your private bot chat'),
      findsOneWidget,
    );
    expect(find.text('New'), findsNWidgets(2));
    expect(
      find.byKey(
        const ValueKey<String>(
          'feature-discovery-new-tutorials/v1/reimbursement.mp4',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'feature-discovery-new-tutorials/v1/telegram-backup.mp4',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Subscribe'), findsNothing);

    final cards = <Material>[
      tester.widget<Material>(
        find.byKey(
          const ValueKey<String>(
            'feature-discovery-card-tutorials/v1/auto-categorization.mp4',
          ),
        ),
      ),
      tester.widget<Material>(
        find.byKey(
          const ValueKey<String>(
            'feature-discovery-card-tutorials/v1/quick-access-account.mp4',
          ),
        ),
      ),
      tester.widget<Material>(
        find.byKey(
          const ValueKey<String>(
            'feature-discovery-card-tutorials/v1/reimbursement.mp4',
          ),
        ),
      ),
      tester.widget<Material>(
        find.byKey(
          const ValueKey<String>(
            'feature-discovery-card-tutorials/v1/telegram-backup.mp4',
          ),
        ),
      ),
    ];
    for (final card in cards) {
      expect(card.borderRadius, BorderRadius.circular(12));
    }

    await tester.tap(find.text('Quick Account Access'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(quickAccessAccountPreviewDescription), findsOneWidget);
    expect(find.text('Okay'), findsOneWidget);
  });
}
