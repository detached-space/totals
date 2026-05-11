import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/widgets/account_import_preview_sheet.dart';

class AccountShareScanPage extends StatefulWidget {
  const AccountShareScanPage({super.key});

  @override
  State<AccountShareScanPage> createState() => _AccountShareScanPageState();
}

class _AccountShareScanPageState extends State<AccountShareScanPage> {
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;
      final payload = AccountSharePayload.decode(rawValue);
      if (payload == null) continue;

      setState(() {
        _isProcessing = true;
      });
      await _controller.stop();

      if (!mounted) return;

      // Show preview sheet
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => AccountImportPreviewSheet(
          payload: payload,
          onConfirm: () {
            Navigator.pop(context, true);
          },
        ),
      );

      if (confirmed == true) {
        await _importPayload(payload);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
  }

  Future<void> _importPayload(AccountSharePayload payload) async {
    final now = DateTime.now().toIso8601String();
    final seen = <String>{};
    var added = 0;
    var skipped = 0;

    for (final entry in payload.accounts) {
      final key = '${entry.bankId}:${entry.accountNumber}';
      if (!seen.add(key)) continue;
      final exists = await _userAccountRepo.userAccountExists(
        entry.accountNumber,
        entry.bankId,
      );

      if (exists) {
        skipped++;
      } else {
        await _userAccountRepo.saveUserAccount(
          UserAccount(
            accountNumber: entry.accountNumber,
            bankId: entry.bankId,
            accountHolderName: entry.name ?? payload.name,
            createdAt: now,
          ),
        );
        added++;
      }
    }

    if (!mounted) return;
    final message = _buildImportMessage(added, skipped);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _buildImportMessage(int added, int skipped) {
    if (added == 0 && skipped == 0) {
      return 'No accounts to import';
    } else if (skipped == 0) {
      return 'Added $added account${added == 1 ? '' : 's'}';
    } else if (added == 0) {
      return 'All accounts already exist ($skipped skipped)';
    } else {
      return 'Added $added account${added == 1 ? '' : 's'}, $skipped already existed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text('Scan Accounts'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable. Please enable permissions.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isProcessing
                          ? 'Importing accounts...'
                          : 'Point your camera at a Totals account QR.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
