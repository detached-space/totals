import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/pattern_parser.dart';
import 'package:totals/utils/text_utils.dart';

/// Returns true if paste SMS feature should be shown (iOS only)
bool get shouldShowPasteSmsFeature => Platform.isIOS;

/// Shows the paste SMS bottom sheet
Future<void> showPasteSmsSheet({
  required BuildContext context,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => const _PasteSmsContent(),
  );
}

class _PasteSmsContent extends StatefulWidget {
  const _PasteSmsContent();

  @override
  State<_PasteSmsContent> createState() => _PasteSmsContentState();
}

class _PasteSmsContentState extends State<_PasteSmsContent> {
  final TextEditingController _textController = TextEditingController();
  bool _isLoading = false;
  bool _isParsing = false;
  String? _errorMessage;
  Transaction? _parsedTransaction;
  Bank? _detectedBank;

  @override
  void initState() {
    super.initState();
    // Auto-paste from clipboard on open
    _pasteFromClipboard();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
        setState(() {
          _textController.text = clipboardData.text!;
          _errorMessage = null;
        });
        // Auto-parse after pasting
        await _parseSms();
      }
    } catch (e) {
      print("debug: Error reading clipboard: $e");
    }
  }

  Future<void> _parseSms() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = "Please paste an SMS message";
        _parsedTransaction = null;
        _detectedBank = null;
      });
      return;
    }

    setState(() {
      _isParsing = true;
      _errorMessage = null;
      _parsedTransaction = null;
      _detectedBank = null;
    });

    try {
      // Try to detect which bank this SMS is from
      final bankConfigService = BankConfigService();
      final banks = await bankConfigService.getBanks();

      Bank? matchedBank;
      for (var bank in banks) {
        for (var code in bank.codes) {
          // Check if the SMS text contains bank identifiers
          if (text.toLowerCase().contains(code.toLowerCase()) ||
              text.toLowerCase().contains(bank.name.toLowerCase()) ||
              text.toLowerCase().contains(bank.shortName.toLowerCase())) {
            matchedBank = bank;
            break;
          }
        }
        if (matchedBank != null) break;
      }

      if (matchedBank == null) {
        // Try to match based on common bank SMS patterns
        final lowerText = text.toLowerCase();
        for (var bank in banks) {
          if (lowerText.contains(bank.shortName.toLowerCase())) {
            matchedBank = bank;
            break;
          }
        }
      }

      if (matchedBank == null) {
        setState(() {
          _isParsing = false;
          _errorMessage =
              "Could not identify the bank from this SMS. Make sure you copied the complete bank SMS message.";
        });
        return;
      }

      _detectedBank = matchedBank;

      // Load patterns for this bank
      final configService = SmsConfigService();
      final patterns = await configService.getPatterns();
      final relevantPatterns =
          patterns.where((p) => p.bankId == matchedBank!.id).toList();

      if (relevantPatterns.isEmpty) {
        setState(() {
          _isParsing = false;
          _errorMessage =
              "No parsing patterns available for ${matchedBank!.name}. The app may not support this bank yet.";
        });
        return;
      }

      // Clean and parse the SMS text
      final cleanedText = configService.cleanSmsText(text);
      final details = await PatternParser.extractTransactionDetails(
        cleanedText,
        matchedBank.codes.first, // Use first bank code as sender
        DateTime.now(),
        relevantPatterns,
      );

      if (details == null) {
        setState(() {
          _isParsing = false;
          _errorMessage =
              "Could not parse transaction details from this SMS. The message format may not be recognized.";
        });
        return;
      }

      // Create transaction object for preview
      final transaction = Transaction.fromJson(details);

      setState(() {
        _isParsing = false;
        _parsedTransaction = transaction;
      });
    } catch (e) {
      setState(() {
        _isParsing = false;
        _errorMessage = "Error parsing SMS: $e";
      });
    }
  }

  Future<void> _saveTransaction() async {
    if (_parsedTransaction == null) return;

    setState(() => _isLoading = true);

    try {
      // Use the existing SMS processing logic to save
      final result = await SmsService.processMessage(
        _textController.text,
        _detectedBank?.codes.first ?? 'MANUAL',
        messageDate: DateTime.now(),
        notifyUser: false,
      );

      if (!mounted) return;

      if (result != null) {
        // Refresh transactions
        Provider.of<TransactionProvider>(context, listen: false).loadData();

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Transaction added: ETB ${formatNumberWithComma(result.amount)}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              "Transaction may already exist or could not be saved.";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error saving transaction: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.content_paste,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste Bank SMS',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Copy your bank SMS and paste here',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // SMS Text Field
          TextField(
            controller: _textController,
            maxLines: 5,
            minLines: 3,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'SMS Message',
              hintText: 'Paste your bank SMS here...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withOpacity(0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste),
                tooltip: 'Paste from clipboard',
                onPressed: _pasteFromClipboard,
              ),
            ),
            onChanged: (_) {
              // Clear previous parse results when text changes
              if (_parsedTransaction != null || _errorMessage != null) {
                setState(() {
                  _parsedTransaction = null;
                  _errorMessage = null;
                  _detectedBank = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),

          // Parse Button
          if (_parsedTransaction == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isParsing ? null : _parseSms,
                icon: _isParsing
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isParsing ? 'Parsing...' : 'Parse SMS'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          // Error Message
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Parsed Transaction Preview
          if (_parsedTransaction != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Transaction Found',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_detectedBank != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _detectedBank!.shortName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TransactionPreviewRow(
                    label: 'Type',
                    value: _parsedTransaction!.type == 'CREDIT'
                        ? 'Income'
                        : 'Expense',
                    valueColor: _parsedTransaction!.type == 'CREDIT'
                        ? Colors.green
                        : Colors.red,
                  ),
                  _TransactionPreviewRow(
                    label: 'Amount',
                    value:
                        'ETB ${formatNumberWithComma(_parsedTransaction!.amount)}',
                    valueColor: _parsedTransaction!.type == 'CREDIT'
                        ? Colors.green
                        : Colors.red,
                    isBold: true,
                  ),
                  if (_parsedTransaction!.creditor != null)
                    _TransactionPreviewRow(
                      label: 'From',
                      value: _parsedTransaction!.creditor!,
                    ),
                  if (_parsedTransaction!.receiver != null)
                    _TransactionPreviewRow(
                      label: 'To',
                      value: _parsedTransaction!.receiver!,
                    ),
                  if (_parsedTransaction!.reference.isNotEmpty)
                    _TransactionPreviewRow(
                      label: 'Reference',
                      value: _parsedTransaction!.reference,
                      isSmall: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Save Button
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _parsedTransaction = null;
                              _detectedBank = null;
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _saveTransaction,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Add Transaction'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TransactionPreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;
  final bool isSmall;

  const _TransactionPreviewRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: (isSmall
                      ? theme.textTheme.labelSmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                color: valueColor,
                fontWeight: isBold ? FontWeight.bold : null,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
