import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/widgets/category_filter_chip.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('category chips show clear flow and selection states', (
    tester,
  ) async {
    final themeProvider = ThemeProvider(initialThemeMode: ThemeMode.light);
    addTearDown(themeProvider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Scaffold(
            body: Row(
              children: [
                CategoryFilterChip(
                  key: const ValueKey<String>('income-category-filter'),
                  label: 'Salary',
                  flow: 'income',
                  selected: false,
                  onTap: () {},
                ),
                CategoryFilterChip(
                  key: const ValueKey<String>('expense-category-filter'),
                  label: 'Groceries',
                  flow: 'expense',
                  selected: false,
                  onTap: () {},
                ),
                CategoryFilterChip(
                  key: const ValueKey<String>(
                    'selected-income-category-filter',
                  ),
                  label: 'Bonus',
                  flow: 'income',
                  selected: true,
                  onTap: () {},
                ),
                CategoryFilterChip(
                  key: const ValueKey<String>(
                    'selected-expense-category-filter',
                  ),
                  label: 'Rent',
                  flow: 'expense',
                  selected: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    BoxDecoration decorationFor(String key) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    expect(
      decorationFor('income-category-filter').color,
      AppColors.incomeSuccess.withValues(alpha: 0.08),
    );
    expect(
      decorationFor('expense-category-filter').color,
      AppColors.red.withValues(alpha: 0.08),
    );
    expect(
      decorationFor('selected-income-category-filter').color,
      const Color(0xFF047857),
    );
    expect(
      decorationFor('selected-expense-category-filter').color,
      const Color(0xFFB91C1C),
    );

    Text textFor(String key) {
      return tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(Text),
        ),
      );
    }

    expect(
      textFor('selected-income-category-filter').style?.color,
      AppColors.white,
    );
    expect(
      textFor('selected-expense-category-filter').style?.color,
      AppColors.white,
    );
  });
}
