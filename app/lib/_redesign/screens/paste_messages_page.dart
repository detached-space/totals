import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/profile.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/sms_service.dart';

/// Manually paste one or more bank messages and run them through the same
/// ingestion pipeline as SMS/Shortcuts: bank detection from the body, pattern
/// parsing, duplicate checks, account matching, and profile stamping.
///
/// Parsing is a dry run — nothing is written until the user reviews the
/// previews and saves the ones they've selected.
class PasteMessagesPage extends StatefulWidget {
  const PasteMessagesPage({super.key});

  @override
  State<PasteMessagesPage> createState() => _PasteMessagesPageState();
}

class _PasteResult {
  final String body;
  final String excerpt;
  ParseResult result;
  String? detail;
  bool selected;
  bool saved = false;

  _PasteResult({
    required this.body,
    required this.excerpt,
    required this.result,
    this.detail,
    this.selected = false,
  });
}

class _PasteMessagesPageState extends State<PasteMessagesPage> {
  final TextEditingController _controller = TextEditingController();
  final List<_PasteResult> _results = [];
  List<Bank> _banks = const [];
  List<Profile> _profiles = const [];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _transactionDetail(ParseResult result) {
    final tx = result.transaction;
    if (result.status != ParseStatus.success || tx == null) return null;
    final bankName = _banks
        .where((b) => b.id == tx.bankId)
        .map((b) => b.shortName)
        .firstOrNull;
    final profileName = _profiles
        .where((p) => p.id == tx.profileId)
        .map((p) => p.name)
        .firstOrNull;
    return [
      if (bankName != null) bankName,
      '${tx.type} ${tx.amount.toStringAsFixed(2)}',
      if (profileName != null) '→ $profileName',
    ].join(' · ');
  }

  Future<void> _parse() async {
    final chunks = _controller.text
        .split(RegExp(r'\n\s*\n'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (chunks.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _results.clear();
    });

    _banks = await BankConfigService().getBanks(allowRemoteFetch: false);
    _profiles = await ProfileRepository().getProfiles();

    for (final chunk in chunks) {
      // Yield a frame between messages so the progress indicator keeps moving.
      await Future<void>.delayed(Duration.zero);
      // Empty sender routes through the same bank-from-body detection the iOS
      // Shortcuts ingest uses. No messageDate, so the date parsed out of the
      // message body is kept instead of being overwritten with "now". Dry run:
      // nothing is saved until the user confirms below.
      final result =
          await SmsService.processMessageResult(chunk, '', dryRun: true);

      if (!mounted) return;
      setState(() {
        _results.add(_PasteResult(
          body: chunk,
          excerpt: chunk.split('\n').first,
          result: result,
          detail: _transactionDetail(result),
          selected: result.status == ParseStatus.success,
        ));
      });
    }

    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _saveSelected() async {
    if (_busy) return;
    setState(() => _busy = true);

    var savedCount = 0;
    for (final r in _results) {
      if (!r.selected || r.saved || r.result.status != ParseStatus.success) {
        continue;
      }
      // Re-run for real; the pipeline repeats its duplicate checks, so a
      // message that was somehow ingested in the meantime just reports
      // "duplicate" instead of double-saving.
      final result = await SmsService.processMessageResult(r.body, '');
      if (!mounted) return;
      setState(() {
        r.result = result;
        r.detail = _transactionDetail(result) ?? r.detail;
        r.saved = result.status == ParseStatus.success;
        if (r.saved) savedCount++;
      });
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (savedCount > 0) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
    }
  }

  int get _pendingCount => _results
      .where((r) =>
          r.selected && !r.saved && r.result.status == ParseStatus.success)
      .length;

  (IconData, Color, String) _statusPresentation(_PasteResult r) {
    switch (r.result.status) {
      case ParseStatus.success:
        return r.saved
            ? (
                AppIcons.check_circle_rounded,
                AppColors.incomeSuccess,
                context.l10nText('Saved'),
              )
            : (
                AppIcons.schedule_rounded,
                AppColors.blue,
                context.l10nText('Ready to save'),
              );
      case ParseStatus.duplicate:
        return (
          AppIcons.copy,
          AppColors.amber,
          context.l10nText('Duplicate — already recorded'),
        );
      case ParseStatus.noBank:
        return (
          AppIcons.help_outline_rounded,
          AppColors.red,
          context.l10nText('Could not identify the bank'),
        );
      case ParseStatus.noPattern:
        return (
          AppIcons.info_outline_rounded,
          AppColors.red,
          context.l10nText('No pattern matched'),
        );
      case ParseStatus.unregisteredBank:
        return (
          AppIcons.account_balance_outlined,
          AppColors.red,
          context.l10nText('No registered account for this bank'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _pendingCount;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(AppIcons.arrow_back_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    context.l10nText('Paste Messages'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.l10nText(
                    'Paste bank messages below — separate multiple messages with a blank line. Parsing only previews; nothing is saved until you confirm.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                minLines: 6,
                maxLines: 12,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary(context),
                ),
                decoration: InputDecoration(
                  hintText: context.l10nText(
                      'Dear customer, your account 1***2345 has been debited…'),
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary(context),
                  ),
                  filled: true,
                  fillColor: AppColors.cardColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.borderColor(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.borderColor(context)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _parse,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10nText('Preview')),
                ),
              ),
              const SizedBox(height: 20),
              ..._results.map(_buildResultCard),
              if (pending > 0) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _saveSelected,
                    child: Text(
                      '${context.l10nText('Save')} $pending '
                      '${context.l10nText(pending == 1 ? 'transaction' : 'transactions')}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(_PasteResult r) {
    final theme = Theme.of(context);
    final (icon, color, label) = _statusPresentation(r);
    final selectable =
        r.result.status == ParseStatus.success && !r.saved && !_busy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: selectable
              ? () => setState(() => r.selected = !r.selected)
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.detail ?? label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      if (r.detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        r.excerpt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (r.result.status == ParseStatus.success && !r.saved)
                  Checkbox(
                    value: r.selected,
                    onChanged: selectable
                        ? (v) => setState(() => r.selected = v ?? false)
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
