import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/widgets/place_name_editor_sheet.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  testWidgets('keeps place-name actions clear of the keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlaceNameEditorSheet(
                  context: context,
                  initialValue: 'Home',
                ),
                child: const Text('Edit place'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit place'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final actionRow = find.byKey(
      const ValueKey('place-name-editor-actions'),
    );
    final keyboardInset = find.byKey(
      const ValueKey('place-name-editor-keyboard-inset'),
    );
    expect(actionRow, findsOneWidget);
    expect(keyboardInset, findsOneWidget);

    final mediaQuery = MediaQuery.of(tester.element(actionRow));
    final viewportBottom =
        tester.getBottomRight(find.byType(Scaffold).first).dy;
    final keyboardTop = viewportBottom - mediaQuery.viewInsets.bottom;
    final appliedInset = tester
        .widget<AnimatedPadding>(keyboardInset)
        .padding
        .resolve(TextDirection.ltr)
        .bottom;

    expect(appliedInset, greaterThan(mediaQuery.viewInsets.bottom));
    expect(
      tester.getBottomRight(actionRow).dy,
      lessThanOrEqualTo(keyboardTop - 28),
    );
  });
}
