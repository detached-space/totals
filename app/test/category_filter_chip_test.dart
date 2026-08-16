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

  testWidgets('only Self category chips use subtle flow colors', (
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
            body: Wrap(
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
                CategoryFilterChip(
                  key: const ValueKey<String>('self-income-category-filter'),
                  label: 'Self',
                  flow: 'income',
                  subtleFlowTint: true,
                  selected: false,
                  onTap: () {},
                ),
                CategoryFilterChip(
                  key: const ValueKey<String>('self-expense-category-filter'),
                  label: 'Self',
                  flow: 'expense',
                  subtleFlowTint: true,
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
      AppColors.surfaceColor(
        tester.element(find.byKey(
          const ValueKey<String>('income-category-filter'),
        )),
      ),
    );
    expect(
      decorationFor('expense-category-filter').color,
      AppColors.surfaceColor(
        tester.element(find.byKey(
          const ValueKey<String>('expense-category-filter'),
        )),
      ),
    );
    expect(
      decorationFor('selected-income-category-filter').color,
      AppColors.primaryDark,
    );
    expect(
      decorationFor('selected-expense-category-filter').color,
      AppColors.primaryDark,
    );
    expect(
      decorationFor('self-income-category-filter').color,
      AppColors.incomeSuccess.withValues(alpha: 0.08),
    );
    expect(
      decorationFor('self-expense-category-filter').color,
      AppColors.red.withValues(alpha: 0.16),
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
    expect(
      textFor('self-income-category-filter').style?.color,
      const Color(0xFF047857),
    );
    expect(
      textFor('self-expense-category-filter').style?.color,
      const Color(0xFFB91C1C),
    );
  });
}
