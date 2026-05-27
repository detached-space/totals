import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/budget_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/l10n/app_localizations.dart';

Future<void> showClearDatabaseDialog(BuildContext context) async {
  bool clearFinancialData = false;
  bool clearBudgets = false;
  bool clearFailedParses = false;
  final parentContext = context;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);

      return StatefulBuilder(
        builder: (context, setState) {
          final hasSelection =
              clearFinancialData || clearBudgets || clearFailedParses;

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              color: theme.colorScheme.surface,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          context.l10nText('Clear Data'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.l10nText(
                      'Select what you want to clear. This action cannot be undone.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildClearOption(
                    context: context,
                    icon: Icons.receipt_long,
                    title: 'Transactions & Accounts',
                    subtitle: 'All transaction history and bank accounts',
                    value: clearFinancialData,
                    onChanged: (value) {
                      setState(() {
                        clearFinancialData = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildClearOption(
                    context: context,
                    icon: Icons.pie_chart_outline,
                    title: 'Budgets',
                    subtitle: 'All budget rules and limits',
                    value: clearBudgets,
                    onChanged: (value) {
                      setState(() {
                        clearBudgets = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildClearOption(
                    context: context,
                    icon: Icons.error_outline,
                    title: 'Failed Parses',
                    subtitle: 'Failed SMS parsing records',
                    value: clearFailedParses,
                    onChanged: (value) {
                      setState(() {
                        clearFailedParses = value ?? false;
                      });
                    },
                  ),
                  if (!hasSelection)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context
                                .l10nText('Please select at least one option'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(context.l10nText('Cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: hasSelection
                              ? () async {
                                  try {
                                    if (clearFinancialData) {
                                      await TransactionRepository().clearAll();
                                      await AccountRepository().clearAll();
                                    }
                                    if (clearBudgets) {
                                      await BudgetRepository().clearAll();
                                    }
                                    if (clearFailedParses) {
                                      await FailedParseRepository().clear();
                                    }

                                    if (parentContext.mounted) {
                                      await Provider.of<TransactionProvider>(
                                        parentContext,
                                        listen: false,
                                      ).loadData();
                                      if (clearFinancialData || clearBudgets) {
                                        try {
                                          await Provider.of<BudgetProvider>(
                                            parentContext,
                                            listen: false,
                                          ).loadBudgets();
                                        } catch (_) {}
                                      }
                                      Navigator.pop(sheetContext);
                                      ScaffoldMessenger.of(parentContext)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            parentContext.l10nTextRead(
                                              'Data cleared successfully',
                                            ),
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (parentContext.mounted) {
                                      Navigator.pop(sheetContext);
                                      ScaffoldMessenger.of(parentContext)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${parentContext.l10nTextRead('Error clearing data')}: $e',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(context.l10nText('Clear')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildClearOption({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool?> onChanged,
}) {
  final theme = Theme.of(context);

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: value
              ? theme.colorScheme.error.withOpacity(0.1)
              : theme.colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? theme.colorScheme.error.withOpacity(0.3)
                : theme.colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: value
                    ? theme.colorScheme.error.withOpacity(0.2)
                    : theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color:
                    value ? theme.colorScheme.error : theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10nText(title),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10nText(subtitle),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.1,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: theme.colorScheme.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
