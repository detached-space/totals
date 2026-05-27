import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/auto_categorization.dart';

Future<bool?> showAutoCategorizationPromptDialog({
  required BuildContext context,
  required AutoCategorizationPromptDecision decision,
  required String categoryName,
}) {
  final theme = Theme.of(context);
  final updatesExistingRule = decision.updatesExistingRule;

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardColor(dialogContext),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderColor(dialogContext)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: AppColors.isDark(dialogContext) ? 0.24 : 0.08,
                ),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  updatesExistingRule
                      ? Icons.autorenew_rounded
                      : Icons.auto_awesome_rounded,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                updatesExistingRule
                    ? dialogContext.l10nText('Update auto-categorization?')
                    : dialogContext.l10nText('Auto-categorize this address?'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(dialogContext),
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary(dialogContext),
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(text: '${dialogContext.l10nText('Use')} '),
                    TextSpan(
                      text: categoryName,
                      style: TextStyle(
                        color: AppColors.textPrimary(dialogContext),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' ${dialogContext.l10nText('automatically for future transactions from')} ',
                    ),
                    TextSpan(
                      text: decision.counterparty,
                      style: TextStyle(
                        color: AppColors.textPrimary(dialogContext),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary(dialogContext),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: AppColors.borderColor(dialogContext),
                          ),
                        ),
                      ),
                      child: Text(dialogContext.l10nText('No')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryLight,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(dialogContext.l10nText('Auto-categorize')),
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
}
