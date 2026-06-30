import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/account_reparse_result_service.dart';
import 'package:totals/utils/text_utils.dart';

class AccountReparseResultPage extends StatelessWidget {
  final AccountReparseDebugResult result;

  const AccountReparseResultPage({
    super.key,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: const Text('Reparse details'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _ResultHeader(result: result),
          const SizedBox(height: 16),
          _TransactionSection(
            title: 'Imported',
            emptyText: 'No transactions were imported.',
            transactions: result.importedTransactions,
            accentColor: AppColors.incomeSuccess,
          ),
          const SizedBox(height: 16),
          _TransactionSection(
            title: 'Removed duplicates',
            emptyText: 'No duplicates were removed.',
            transactions: result.removedDuplicateTransactions,
            accentColor: AppColors.red,
          ),
        ],
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final AccountReparseDebugResult result;

  const _ResultHeader({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.completionMessage,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _MetaLine(
            label: 'Account',
            value:
                '${result.bankLabel} ${_maskAccountNumber(result.accountNumber)}',
          ),
          _MetaLine(
            label: 'Completed',
            value: DateFormat('MMM d, y HH:mm').format(result.completedAt),
          ),
        ],
      ),
    );
  }
}

class _TransactionSection extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Transaction> transactions;
  final Color accentColor;

  const _TransactionSection({
    required this.title,
    required this.emptyText,
    required this.transactions,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$title (${transactions.length})',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (transactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Text(
              emptyText,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
              ),
            ),
          )
        else
          ...transactions.map(
            (transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TransactionDebugTile(
                transaction: transaction,
                accentColor: accentColor,
              ),
            ),
          ),
      ],
    );
  }
}

class _TransactionDebugTile extends StatelessWidget {
  final Transaction transaction;
  final Color accentColor;

  const _TransactionDebugTile({
    required this.transaction,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final type = (transaction.type ?? '').trim().toUpperCase();
    final amountPrefix = type == 'CREDIT'
        ? '+'
        : type == 'DEBIT'
            ? '-'
            : '';
    final sourceLabel = _sourceLabel(transaction);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _counterparty(transaction),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$amountPrefix ETB ${formatNumberWithComma(transaction.amount)}',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _DebugChip(label: type.isEmpty ? 'UNKNOWN' : type),
              _DebugChip(label: _formatTransactionTime(transaction.time)),
              if (_hasText(transaction.currentBalance))
                _DebugChip(label: 'Balance ${transaction.currentBalance}'),
              if (_hasText(transaction.accountNumber))
                _DebugChip(label: 'Acct ${transaction.accountNumber}'),
            ],
          ),
          const SizedBox(height: 8),
          _MetaLine(label: 'Reference', value: transaction.reference),
          if (sourceLabel != null)
            _MetaLine(label: 'SMS source', value: sourceLabel),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            height: 1.3,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _DebugChip extends StatelessWidget {
  final String label;

  const _DebugChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.mutedFill(context).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _counterparty(Transaction transaction) {
  final receiver = transaction.receiver?.trim();
  if (receiver != null && receiver.isNotEmpty) return receiver;
  final creditor = transaction.creditor?.trim();
  if (creditor != null && creditor.isNotEmpty) return creditor;
  final note = transaction.note?.trim();
  if (note != null && note.isNotEmpty) return note;
  return 'Transaction';
}

String _formatTransactionTime(String? raw) {
  final parsed = DateTime.tryParse(raw ?? '');
  if (parsed == null) return 'No time';
  return DateFormat('MMM d, HH:mm').format(parsed);
}

String? _sourceLabel(Transaction transaction) {
  final messageId = transaction.sourceMessageId?.trim();
  if (messageId != null && messageId.isNotEmpty) {
    return 'message $messageId';
  }

  final fingerprint = transaction.sourceFingerprint?.trim();
  if (fingerprint == null || fingerprint.isEmpty) return null;
  return 'fingerprint ${_shorten(fingerprint)}';
}

String _shorten(String value) {
  if (value.length <= 14) return value;
  return '${value.substring(0, 14)}...';
}

String _maskAccountNumber(String accountNumber) {
  final trimmed = accountNumber.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length <= 4) return trimmed;
  return '****${trimmed.substring(trimmed.length - 4)}';
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
