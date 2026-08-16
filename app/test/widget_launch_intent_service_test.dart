import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/widget_launch_intent_service.dart';

void main() {
  group('WidgetLaunchTarget.fromWireValue', () {
    test('parses every supported launch target', () {
      expect(
        WidgetLaunchTarget.fromWireValue('budget'),
        WidgetLaunchTarget.budget,
      );
      expect(
        WidgetLaunchTarget.fromWireValue('add_expense'),
        WidgetLaunchTarget.addExpense,
      );
      expect(
        WidgetLaunchTarget.fromWireValue('add_income'),
        WidgetLaunchTarget.addIncome,
      );
      expect(
        WidgetLaunchTarget.fromWireValue('quick_accounts'),
        WidgetLaunchTarget.quickAccounts,
      );
      expect(
        WidgetLaunchTarget.fromWireValue('verify_payments'),
        WidgetLaunchTarget.verifyPayments,
      );
    });

    test('normalizes whitespace and casing', () {
      expect(
        WidgetLaunchTarget.fromWireValue('  ADD_EXPENSE  '),
        WidgetLaunchTarget.addExpense,
      );
    });

    test('rejects missing and unknown targets', () {
      expect(WidgetLaunchTarget.fromWireValue(null), isNull);
      expect(WidgetLaunchTarget.fromWireValue(''), isNull);
      expect(WidgetLaunchTarget.fromWireValue('unknown'), isNull);
    });
  });
}
