import 'package:flutter_test/flutter_test.dart';
import 'package:totals/models/shared_expense_group.dart';
import 'package:totals/repositories/shared_expense_repository.dart';

void main() {
  group('originalDebtPlanFor', () {
    test('keeps repayment rows attached to the original payer', () {
      final group = _groupWithExpenses([
        _expense(
          id: 'eyos-aimen-3000',
          amount: 3000,
          paidBy: _eyos,
          splitAmong: [_aimen],
        ),
        _expense(
          id: 'hale-aimen-8000',
          amount: 8000,
          paidBy: _hale,
          splitAmong: [_aimen],
        ),
        _expense(
          id: 'hale-aimen-3500',
          amount: 3500,
          paidBy: _hale,
          splitAmong: [_aimen],
        ),
        _expense(
          id: 'hale-yohannes-11100',
          amount: 11100,
          paidBy: _hale,
          splitAmong: [_yohannes],
        ),
      ]);

      final optimizedDebts = settlementPlanFor(group).debts;
      expect(
        optimizedDebts.map(_debtLabel),
        containsAll([
          'aimen->hale:14500.0',
          'yohannes->hale:8100.0',
          'yohannes->eyos:3000.0',
        ]),
      );

      final originalDebts = originalDebtPlanFor(group).debts;
      expect(
        originalDebts.map(_debtLabel).toList(growable: false),
        [
          'aimen->hale:11500.0',
          'yohannes->hale:11100.0',
          'aimen->eyos:3000.0',
        ],
      );
    });

    test('settlements reduce the matching original debt', () {
      final group = _groupWithExpenses([
        _expense(
          id: 'eyos-aimen-3000',
          amount: 3000,
          paidBy: _eyos,
          splitAmong: [_aimen],
        ),
        _expense(
          id: 'aimen-settled-eyos-1000',
          amount: 1000,
          paidBy: _aimen,
          splitAmong: [_eyos],
          kind: 'settlement',
        ),
      ]);

      final originalDebts = originalDebtPlanFor(group).debts;
      expect(
        originalDebts.map(_debtLabel).toList(growable: false),
        ['aimen->eyos:2000.0'],
      );
    });
  });
}

const _eyos = 'eyos';
const _hale = 'hale';
const _aimen = 'aimen';
const _yohannes = 'yohannes';

SharedExpenseGroup _groupWithExpenses(List<SharedExpense> expenses) {
  return SharedExpenseGroup(
    id: 'group',
    name: 'Trip',
    myDisplayName: 'Eyos',
    createdAt: DateTime(2026),
    status: SharedExpenseGroupStatus.ready,
    members: const [
      SharedExpenseMember(devicePublicKey: _eyos),
      SharedExpenseMember(devicePublicKey: _hale),
      SharedExpenseMember(devicePublicKey: _aimen),
      SharedExpenseMember(devicePublicKey: _yohannes),
    ],
    approvedMemberKeys: const {_eyos, _hale, _aimen, _yohannes},
    expenses: expenses,
  );
}

SharedExpense _expense({
  required String id,
  required double amount,
  required String paidBy,
  required List<String> splitAmong,
  String kind = 'expense',
}) {
  return SharedExpense(
    id: id,
    amount: amount,
    currency: 'ETB',
    reason: id,
    paidBy: paidBy,
    splitAmong: splitAmong,
    timestamp: 0,
    kind: kind,
  );
}

String _debtLabel(SettlementDebt debt) {
  return '${debt.from}->${debt.to}:${debt.amount.toStringAsFixed(1)}';
}
