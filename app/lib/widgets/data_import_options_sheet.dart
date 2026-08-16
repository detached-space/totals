import 'package:flutter/material.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/services/data_export_import_service.dart';

Future<DataImportOptions?> showDataImportOptionsSheet({
  required BuildContext context,
  required BackupImportSummary summary,
}) {
  return showModalBottomSheet<DataImportOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DataImportOptionsSheet(summary: summary),
  );
}

class DataImportOptionsSheet extends StatefulWidget {
  final BackupImportSummary summary;

  const DataImportOptionsSheet({
    super.key,
    required this.summary,
  });

  @override
  State<DataImportOptionsSheet> createState() => _DataImportOptionsSheetState();
}

class _DataImportOptionsSheetState extends State<DataImportOptionsSheet> {
  late final Set<int> _selectedBankIds;
  bool _includeBudgets = true;
  bool _includeAutoCategorization = true;
  bool _includeFailedParses = true;
  bool _includeSmsPatterns = true;
  bool _includeLoansAndDebts = true;

  @override
  void initState() {
    super.initState();
    _selectedBankIds = widget.summary.banks.map((bank) => bank.id).toSet();
  }

  bool get _allBanksSelected =>
      _selectedBankIds.length == widget.summary.banks.length;

  void _submit() {
    if (widget.summary.banks.isNotEmpty && _selectedBankIds.isEmpty) return;
    Navigator.of(context).pop(
      DataImportOptions(
        bankIds: _allBanksSelected ? null : Set<int>.from(_selectedBankIds),
        includeBudgets: _includeBudgets,
        includeAutoCategorization: _includeAutoCategorization,
        includeFailedParses: _includeFailedParses,
        includeSmsPatterns: _includeSmsPatterns,
        includeLoansAndDebts: _includeLoansAndDebts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exportDate = widget.summary.exportDate;
    final dateLabel = exportDate == null
        ? null
        : MaterialLocalizations.of(context).formatMediumDate(exportDate);

    return FractionallySizedBox(
      heightFactor: 0.9,
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
                    context.l10nText('Import backup'),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(
                      label: 'Schema v${widget.summary.schemaVersion}',
                    ),
                    if (dateLabel != null)
                      _SummaryChip(
                        label: '${context.l10nText('Exported')} $dateLabel',
                      ),
                    if (widget.summary.isFilteredExport)
                      _SummaryChip(
                        label: context.l10nText('Filtered backup'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10nText(
                    'Choose what to add to this device. Existing data is kept and duplicate transactions are skipped.',
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
                if (widget.summary.banks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      context.l10nText(
                        'This backup does not contain bank transaction data.',
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
                              ..addAll(
                                widget.summary.banks.map((bank) => bank.id),
                              );
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
                  ...widget.summary.banks.map(
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
                _ImportSectionSwitch(
                  title: context.l10nText('Budgets'),
                  count: widget.summary.budgetCount,
                  value: _includeBudgets,
                  onChanged: (value) => setState(() => _includeBudgets = value),
                ),
                _ImportSectionSwitch(
                  title: context.l10nText('Auto-categorization rules'),
                  count: widget.summary.autoCategorizationRuleCount,
                  value: _includeAutoCategorization,
                  onChanged: (value) =>
                      setState(() => _includeAutoCategorization = value),
                ),
                _ImportSectionSwitch(
                  title: context.l10nText('Loans and debts'),
                  count: widget.summary.loanDebtEntryCount,
                  value: _includeLoansAndDebts,
                  onChanged: (value) =>
                      setState(() => _includeLoansAndDebts = value),
                ),
                _ImportSectionSwitch(
                  title: context.l10nText('SMS parsing configuration'),
                  count: widget.summary.smsPatternCount,
                  value: _includeSmsPatterns,
                  onChanged: (value) =>
                      setState(() => _includeSmsPatterns = value),
                ),
                _ImportSectionSwitch(
                  title: context.l10nText('Failed message diagnostics'),
                  count: widget.summary.failedParseCount,
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
                      'Bank configuration and category definitions are handled automatically to keep imported data usable.',
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
                  onPressed: widget.summary.banks.isNotEmpty &&
                          _selectedBankIds.isEmpty
                      ? null
                      : _submit,
                  child: Text(context.l10nText('Import selected')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportSectionSwitch extends StatelessWidget {
  final String title;
  final int count;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ImportSectionSwitch({
    required this.title,
    required this.count,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text('$count ${context.l10nText('items')}'),
      value: count > 0 && value,
      onChanged: count == 0 ? null : onChanged,
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;

  const _SummaryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}
