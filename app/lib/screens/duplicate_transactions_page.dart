import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/duplicate_transaction_service.dart';

class DuplicateTransactionsPage extends StatefulWidget {
  const DuplicateTransactionsPage({super.key});

  @override
  State<DuplicateTransactionsPage> createState() =>
      _DuplicateTransactionsPageState();
}

class _DuplicateTransactionsPageState
    extends State<DuplicateTransactionsPage> {
  final DuplicateTransactionService _service = DuplicateTransactionService();
  List<SuspectedDuplicate> _duplicates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final results = _service.findDuplicates(provider.allTransactions);
    if (!mounted) return;
    setState(() {
      _duplicates = results;
      _isLoading = false;
    });
  }

  String _formatAmount(double amount) =>
      'ETB ${NumberFormat('#,##0.00').format(amount)}';

  String _formatTime(String? raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('MMM dd, yyyy • hh:mm:ss a').format(dt);
  }

  String _formatDelta(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s apart';
    return '${d.inMinutes}m ${d.inSeconds % 60}s apart';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _duplicates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 56,
                            color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                        const SizedBox(height: 16),
                        Text('No suspicious duplicates found',
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                          'Transactions with the same amount, account, and type within 60 seconds of each other will appear here.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _duplicates.length,
                  itemBuilder: (context, index) {
                    final d = _duplicates[index];
                    final isCredit = d.first.type == 'CREDIT';
                    final amountColor = isCredit
                        ? Colors.green
                        : theme.colorScheme.error;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: theme.colorScheme.error, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'Suspected duplicate',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _formatDelta(d.timeDelta),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _formatAmount(d.first.amount),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: amountColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _TxRow(
                              label: '1st',
                              reference: d.first.reference,
                              time: _formatTime(d.first.time),
                              theme: theme,
                            ),
                            const SizedBox(height: 4),
                            _TxRow(
                              label: '2nd',
                              reference: d.second.reference,
                              time: _formatTime(d.second.time),
                              theme: theme,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final String label;
  final String reference;
  final String time;
  final ThemeData theme;

  const _TxRow({
    required this.label,
    required this.reference,
    required this.time,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reference,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis),
              Text(time,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
