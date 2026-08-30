import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/widgets/saved_location_editor_sheet.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  testWidgets('creates a named saved location from the map sheet',
      (tester) async {
    SavedLocationEditorResult? result;
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showSavedLocationEditorSheet(
                    context: context,
                    approximateName: 'Bole, Addis Ababa',
                  );
                },
                child: const Text('Drop pin'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Drop pin'));
    await tester.pumpAndSettle();
    expect(find.text('Save this location'), findsOneWidget);
    expect(find.text('Bole, Addis Ababa'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('saved-location-name-field')),
      'Home',
    );
    await tester.pump();
    final saveButton = find.byKey(
      const ValueKey<String>('saved-location-save'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(
      saveButton,
    );
    await tester.pumpAndSettle();

    expect(result?.action, SavedLocationEditorAction.save);
    expect(result?.name, 'Home');
  });
}
