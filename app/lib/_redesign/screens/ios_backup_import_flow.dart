import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/ios_migration_service.dart';

/// Picks the old Totals (Scriptable) export files, previews what will import,
/// confirms, and runs the migration.
///
/// Shared by Settings and the first-run setup sheet. The "you didn't select
/// every file" warning is the whole reason this lives in one place: a partial
/// selection imports silently and wrongly (no profiles, wrong multi-account
/// split), so the two entry points must not drift apart on that message.
///
/// Returns the migration result, or null when cancelled or nothing was picked.
Future<IosMigrationResult?> runIosBackupImport(
  BuildContext context, {
  VoidCallback? onImportStarted,
}) async {
  // On iOS, picking a *folder* returns a security-scoped URL that can't be read
  // afterward (and iCloud files may be placeholders). Picking the files makes
  // iOS copy/download them into an accessible location, so read them withData.
  final picked = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null; // cancelled

  final files = <String, String>{};
  for (final pf in picked.files) {
    String? content;
    if (pf.bytes != null) {
      content = utf8.decode(pf.bytes!, allowMalformed: true);
    } else if (pf.path != null) {
      try {
        content = await File(pf.path!).readAsString();
      } catch (_) {/* skip unreadable */}
    }
    if (content != null) files[pf.name] = content;
  }

  if (!context.mounted) return null;
  if (!files.containsKey('transactions.txt')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10nTextRead(
            'Select your old export files (include transactions.txt).')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return null;
  }

  // Preview (no DB write) so we can show exactly what will import and flag any
  // files that weren't selected — those silently degrade the result.
  final preview = IosMigrationService.instance.convert(files).result;
  if (!context.mounted) return null;

  final summary = StringBuffer()
    ..writeln('${preview.transactions} transactions, '
        '${preview.accounts} accounts, ${preview.profilesCreated} profiles, '
        '${preview.categories} categories, ${preview.budgets} budgets.');
  if (preview.missingFiles.isNotEmpty) {
    summary.writeln('\n⚠️ Not selected: ${preview.missingFiles.join(', ')}.\n'
        'For a complete migration (profiles, correct multi-account split), '
        'go back and select ALL files in the folder.');
  }
  summary.write('\nDuplicates are skipped, so this is safe to run again.');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardColor(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(ctx.l10nText('Import from iOS backup'),
          style: TextStyle(color: AppColors.textPrimary(ctx))),
      content: SingleChildScrollView(
        child: Text(summary.toString(),
            style: TextStyle(color: AppColors.textSecondary(ctx))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10nText('Cancel'),
              style: TextStyle(color: AppColors.textSecondary(ctx))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(ctx.l10nText('Import')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  onImportStarted?.call();
  final result = await IosMigrationService.instance.importFromFiles(files);
  if (!context.mounted) return result;

  Provider.of<TransactionProvider>(context, listen: false).loadData();
  // Profiles are created/activated during import; the running app must reload
  // to pick up the new profile list and active profile.
  final restartNote = result.profilesCreated > 0
      ? ' Restart the app to see your ${result.profilesCreated} profiles.'
      : '';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardColor(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(ctx.l10nText('Import complete'),
          style: TextStyle(color: AppColors.textPrimary(ctx))),
      content: Text(
        'Imported ${result.transactions} transactions.$restartNote',
        style: TextStyle(color: AppColors.textSecondary(ctx)),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(ctx.l10nText('OK')),
        ),
      ],
    ),
  );
  return result;
}
