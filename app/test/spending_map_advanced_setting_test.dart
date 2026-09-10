import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/services/advanced_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Spending Map is opt-in and controls its Quick Access item', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = AdvancedSettingsService.instance;
    await service.reload();

    expect(service.spendingMapEnabled.value, isFalse);
    expect(
        service.toolsFabItems.value, isNot(contains(ToolsFabItem.spendingMap)));

    await service.setSpendingMapEnabled(true);
    expect(service.spendingMapEnabled.value, isTrue);
    expect(service.toolsFabItems.value, contains(ToolsFabItem.spendingMap));

    await service.setToolsFabItems(<ToolsFabItem>{ToolsFabItem.loans});
    expect(
      service.toolsFabItems.value,
      containsAll(<ToolsFabItem>{
        ToolsFabItem.loans,
        ToolsFabItem.spendingMap,
      }),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('advanced_spending_map_enabled'), isTrue);
    expect(
      prefs.getStringList('redesign_tools_fab_items'),
      contains('spending_map'),
    );

    await service.setSpendingMapEnabled(false);
    expect(service.spendingMapEnabled.value, isFalse);
    expect(
        service.toolsFabItems.value, isNot(contains(ToolsFabItem.spendingMap)));
    expect(
      prefs.getStringList('redesign_tools_fab_items'),
      isNot(contains('spending_map')),
    );
  });

  test('stale Spending Map tool is hidden while the feature is disabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'advanced_spending_map_enabled': false,
      'redesign_tools_fab_items': <String>[
        'quick_accounts',
        'spending_map',
      ],
    });

    await AdvancedSettingsService.instance.reload();

    expect(
      AdvancedSettingsService.instance.toolsFabItems.value,
      isNot(contains(ToolsFabItem.spendingMap)),
    );
  });
}
