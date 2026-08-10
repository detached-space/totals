import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/finance_lock_surface.dart';
import 'package:totals/bootstrap/app_bootstrap.dart';

void main() {
  testWidgets('startup status replaces the locked message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinanceLockSurface(
          statusText: BootstrapPhase.preparing.label,
          showProgressIndicator: true,
        ),
      ),
    );

    expect(find.text('Preparing your finances...'), findsOneWidget);
    expect(find.text('Your finances are locked'), findsNothing);
    expect(find.text('Tap to unlock'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<GestureDetector>(find.byType(GestureDetector)).onTap,
      isNull,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceLockSurface(
          statusText: BootstrapPhase.openingDatabase.label,
          showProgressIndicator: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Updating your finances...'), findsOneWidget);
    expect(find.text('Preparing your finances...'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('interactive lock presentation keeps the unlock action', (
    tester,
  ) async {
    var unlockCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FinanceLockSurface(
          statusText: 'Your finances are locked',
          unlockPromptText: 'Tap to unlock',
          onTap: () => unlockCount += 1,
        ),
      ),
    );

    expect(find.text('Your finances are locked'), findsOneWidget);
    expect(find.text('Tap to unlock'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Tap to unlock'));
    expect(unlockCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bootstrap lock screen applies the saved dark theme', (
    tester,
  ) async {
    final startupCompletion = Completer<void>();

    await tester.pumpWidget(
      AppBootstrapGate(
        appBuilder: (_, initialThemeMode) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: initialThemeMode,
          home: const Text('Ready'),
        ),
        themeModeLoader: () async => ThemeMode.dark,
        bootstrapInitializer: ({required onPhaseChanged}) async {
          onPhaseChanged(BootstrapPhase.openingDatabase);
          await startupCompletion.future;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final bootstrapApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(bootstrapApp.themeMode, ThemeMode.dark);
    expect(scaffold.backgroundColor, AppColors.darkBg);
    expect(find.text('Updating your finances...'), findsOneWidget);

    startupCompletion.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
