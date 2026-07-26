import 'package:flutter/material.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/services/data_export_import_service.dart';

Future<DataExportOptions?> showDataExportOptionsSheet({
  required BuildContext context,
  required List<ExportBankSummary> banks,
}) {
  return showModalBottomSheet<DataExportOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DataExportOptionsSheet(banks: banks),
  );
}

class DataExportOptionsSheet extends StatefulWidget {
  final List<ExportBankSummary> banks;

  const DataExportOptionsSheet({
    super.key,
    required this.banks,
  });

  @override
  State<DataExportOptionsSheet> createState() => _DataExportOptionsSheetState();
}

class _DataExportOptionsSheetState extends State<DataExportOptionsSheet> {
  late final Set<int> _selectedBankIds;
  DateTimeRange? _transactionRange;
  bool _includeBudgets = true;
  bool _includeAutoCategorization = true;
  bool _includeFailedParses = true;
  bool _includeSmsPatterns = true;
  bool _includeLoansAndDebts = true;
  bool _includeQuickAccessAccounts = true;

  @override
  void initState() {
    super.initState();
    _selectedBankIds = widget.banks.map((bank) => bank.id).toSet();
  }

  bool get _allBanksSelected => _selectedBankIds.length == widget.banks.length;

  Future<void> _pickTransactionRange() async {
    final now = DateTime.now();
    final initialRange = _transactionRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
    );
    if (picked == null || !mounted) return;
    setState(() => _transactionRange = picked);
  }

  void _submit() {
    if (widget.banks.isNotEmpty && _selectedBankIds.isEmpty) return;

    final start = _transactionRange?.start;
    final endDate = _transactionRange?.end;
    final end = endDate == null
        ? null
        : DateTime(
            endDate.year,
            endDate.month,
            endDate.day,
            23,
            59,
            59,
            999,
          );

    Navigator.of(context).pop(
      DataExportOptions(
        bankIds: _allBanksSelected ? null : Set<int>.from(_selectedBankIds),
        transactionStart: start,
        transactionEnd: end,
        includeBudgets: _includeBudgets,
        includeAutoCategorization: _includeAutoCategorization,
        includeFailedParses: _includeFailedParses,
        includeSmsPatterns: _includeSmsPatterns,
        includeLoansAndDebts: _includeLoansAndDebts,
        includeQuickAccessAccounts: _includeQuickAccessAccounts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final range = _transactionRange;
    final rangeLabel = range == null
        ? context.l10nText('All transaction dates')
        : '${localizations.formatMediumDate(range.start)} – '
            '${localizations.formatMediumDate(range.end)}';

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
                    context.l10nText('Customize export'),
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
                  context.l10nText('Banks and wallets'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10nText(
                    'Accounts and transactions from the selected institutions will be included.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (widget.banks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      context.l10nText('No bank or wallet data was found.'),
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
                  context.l10nText('Transaction history'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(rangeLabel),
                  subtitle: range == null
                      ? null
                      : Text(
                          context.l10nText(
                            'Transactions without a readable date are kept for safety.',
                          ),
                        ),
                  trailing: range == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          onPressed: () =>
                              setState(() => _transactionRange = null),
                          tooltip: context.l10nText('Use all dates'),
                          icon: const Icon(Icons.close),
                        ),
                  onTap: _pickTransactionRange,
                ),
                Text(
                  context.l10nText(
                    'Original source SMS messages available on this device are included with the selected transactions.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
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
                      'Includes saved accounts belonging to other people.',
                    ),
                  ),
                  value: _includeQuickAccessAccounts,
                  onChanged: (value) =>
                      setState(() => _includeQuickAccessAccounts = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Budgets')),
                  value: _includeBudgets,
                  onChanged: (value) => setState(() => _includeBudgets = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10nText('Auto-categorization rules'),
                  ),
                  subtitle: Text(
                    context.l10nText(
                      'Includes learned rules and dismissed suggestions.',
                    ),
                  ),
                  value: _includeAutoCategorization,
                  onChanged: (value) =>
                      setState(() => _includeAutoCategorization = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Loans and debts')),
                  value: _includeLoansAndDebts,
                  onChanged: (value) =>
                      setState(() => _includeLoansAndDebts = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('SMS parsing configuration')),
                  value: _includeSmsPatterns,
                  onChanged: (value) =>
                      setState(() => _includeSmsPatterns = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10nText('Failed message diagnostics')),
                  subtitle: Text(
                    context.l10nText(
                      'May contain the original text of messages that could not be parsed.',
                    ),
                  ),
                  value: _includeFailedParses,
                  onChanged: (value) =>
                      setState(() => _includeFailedParses = value),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.l10nText(
                      'Bank definitions and categories remain included so filtered and full backups use the same compatible backup structure.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
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
                  onPressed: widget.banks.isNotEmpty && _selectedBankIds.isEmpty
                      ? null
                      : _submit,
                  child: Text(context.l10nText('Continue')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
