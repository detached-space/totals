import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/data_clear_service.dart';
import 'package:totals/services/data_export_import_service.dart';

Future<ClearDataSelection?> showClearDataOptionsSheet({
  required BuildContext context,
  required List<ExportBankSummary> banks,
}) {
  return showModalBottomSheet<ClearDataSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ClearDataOptionsSheet(banks: banks),
  );
}

Future<void> showClearDatabaseDialog(BuildContext context) async {
  final parentContext = context;

  late final List<ExportBankSummary> banks;
  try {
    banks = await DataExportImportService().getExportBankSummaries(
      includeQuickAccessAccounts: false,
    );
  } catch (error) {
    if (!parentContext.mounted) return;
    ScaffoldMessenger.of(parentContext).showSnackBar(
      SnackBar(
        content: Text(
          '${parentContext.l10nTextRead('Error clearing data')}: $error',
        ),
      ),
    );
    return;
  }

  if (!parentContext.mounted) return;
  final selection = await showClearDataOptionsSheet(
    context: parentContext,
    banks: banks,
  );
  if (selection == null || !parentContext.mounted) return;

  try {
    final transactionProvider = Provider.of<TransactionProvider>(
      parentContext,
      listen: false,
    );
    BudgetProvider? budgetProvider;
    if (selection.financialData || selection.budgets) {
      try {
        budgetProvider = Provider.of<BudgetProvider>(
          parentContext,
          listen: false,
        );
      } catch (_) {}
    }

    await DataClearService().clear(selection);
    await transactionProvider.loadData();
    await budgetProvider?.loadBudgets();
    if (!parentContext.mounted) return;

    ScaffoldMessenger.of(parentContext).showSnackBar(
      SnackBar(
        content: Text(
          parentContext.l10nTextRead('Data cleared successfully'),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  } catch (error) {
    if (!parentContext.mounted) return;
    ScaffoldMessenger.of(parentContext).showSnackBar(
      SnackBar(
        content: Text(
          '${parentContext.l10nTextRead('Error clearing data')}: $error',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class ClearDataOptionsSheet extends StatefulWidget {
  final List<ExportBankSummary> banks;

  const ClearDataOptionsSheet({
    super.key,
    required this.banks,
  });

  @override
  State<ClearDataOptionsSheet> createState() => _ClearDataOptionsSheetState();
}

class _ClearDataOptionsSheetState extends State<ClearDataOptionsSheet> {
  final Set<int> _selectedBankIds = <int>{};
  bool _clearQuickAccessAccounts = false;
  bool _clearBudgets = false;
  bool _clearAutoCategorization = false;
  bool _clearLoansAndDebts = false;
  bool _clearFailedParses = false;

  bool get _allBanksSelected =>
      widget.banks.isNotEmpty &&
      _selectedBankIds.length == widget.banks.length;

  ClearDataSelection get _selection {
    return ClearDataSelection(
      financialData: _selectedBankIds.isNotEmpty,
      bankIds: _allBanksSelected
          ? null
          : Set<int>.unmodifiable(_selectedBankIds),
      quickAccessAccounts: _clearQuickAccessAccounts,
      budgets: _clearBudgets,
      autoCategorization: _clearAutoCategorization,
      loansAndDebts: _clearLoansAndDebts,
      failedParses: _clearFailedParses,
    );
  }

  void _submit() {
    final selection = _selection;
    if (!selection.hasSelection) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = _selection;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Clear Data'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: context.l10nText('Close'),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                Text(
                  context.l10nText(
                    'Select what you want to clear. This action cannot be undone.',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  context.l10nText('Banks and wallets'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10nText(
                    'Transactions and accounts from selected institutions will be permanently deleted.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.banks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      context.l10nText(
                        'No bank or wallet data was found.',
                      ),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          if (_allBanksSelected) {
                            _selectedBankIds.clear();
                          } else {
                            _selectedBankIds
                              ..clear()
                              ..addAll(widget.banks.map((bank) => bank.id));
                          }
                        });
                      },
                      child: Text(
                        context.l10nText(
                          _allBanksSelected ? 'Clear all' : 'Select all',
                        ),
                      ),
                    ),
                  ),
                  ...widget.banks.map(
                    (bank) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _selectedBankIds.contains(bank.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(bank.name),
                      subtitle: Text(
                        '${bank.accountCount} ${context.l10nText('accounts')}'
                        ' · ${bank.transactionCount} '
                        '${context.l10nText('transactions')}',
                      ),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedBankIds.add(bank.id);
                          } else {
                            _selectedBankIds.remove(bank.id);
                          }
                        });
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  context.l10nText('Additional data'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Quick Access accounts')),
                  subtitle: Text(
                    context.l10nText(
                      'Saved accounts belonging to other people',
                    ),
                  ),
                  value: _clearQuickAccessAccounts,
                  onChanged: (value) =>
                      setState(() => _clearQuickAccessAccounts = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Budgets')),
                  value: _clearBudgets,
                  onChanged: (value) =>
                      setState(() => _clearBudgets = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10nText('Auto-categorization rules'),
                  ),
                  subtitle: Text(
                    context.l10nText(
                      'Learned rules and dismissed suggestions',
                    ),
                  ),
                  value: _clearAutoCategorization,
                  onChanged: (value) =>
                      setState(() => _clearAutoCategorization = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Loans and debts')),
                  subtitle: Text(
                    context.l10nText(
                      'Loan, debt, and repayment tracking',
                    ),
                  ),
                  value: _clearLoansAndDebts,
                  onChanged: (value) =>
                      setState(() => _clearLoansAndDebts = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10nText('Failed message diagnostics'),
                  ),
                  subtitle: Text(
                    context.l10nText('Failed SMS parsing records'),
                  ),
                  value: _clearFailedParses,
                  onChanged: (value) =>
                      setState(() => _clearFailedParses = value),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selection.hasSelection ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: Text(context.l10nText('Clear selected')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
