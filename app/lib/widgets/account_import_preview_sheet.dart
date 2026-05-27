import 'package:flutter/material.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/l10n/app_localizations.dart';

class _AccountPreviewItem {
  final AccountShareEntry entry;
  final Bank? bank;
  final bool exists;

  const _AccountPreviewItem({
    required this.entry,
    required this.bank,
    required this.exists,
  });
}

class AccountImportPreviewSheet extends StatefulWidget {
  final AccountSharePayload payload;
  final VoidCallback onConfirm;

  const AccountImportPreviewSheet({
    super.key,
    required this.payload,
    required this.onConfirm,
  });

  @override
  State<AccountImportPreviewSheet> createState() =>
      _AccountImportPreviewSheetState();
}

class _AccountImportPreviewSheetState extends State<AccountImportPreviewSheet> {
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  List<_AccountPreviewItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreviewData();
  }

  Future<void> _loadPreviewData() async {
    final banks = AllBanksFromAssets.getAllBanks();
    final items = <_AccountPreviewItem>[];

    for (final entry in widget.payload.accounts) {
      final bank = banks.firstWhere(
        (b) => b.id == entry.bankId,
        orElse: () => Bank(
          id: entry.bankId,
          name: 'Unknown Bank',
          shortName: 'Unknown',
          codes: [],
          image: '',
        ),
      );

      final exists = await _userAccountRepo.userAccountExists(
        entry.accountNumber,
        entry.bankId,
      );

      items.add(_AccountPreviewItem(
        entry: entry,
        bank: bank,
        exists: exists,
      ));
    }

    // Sort: new accounts first
    items.sort((a, b) {
      if (a.exists == b.exists) return 0;
      return a.exists ? 1 : -1;
    });

    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    final newCount = _items.where((item) => !item.exists).length;
    final existsCount = _items.where((item) => item.exists).length;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Accounts',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'From ${widget.payload.name}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // Summary
            _buildSummary(theme, colorScheme, newCount, existsCount),

            const SizedBox(height: 8),

            // Account List
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return _buildAccountItem(
                    theme,
                    colorScheme,
                    _items[index],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Actions
            _buildActions(
              context,
              theme,
              colorScheme,
              newCount,
              bottomSafeArea,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(
    ThemeData theme,
    ColorScheme colorScheme,
    int newCount,
    int existsCount,
  ) {
    String summaryText;
    IconData summaryIcon;
    Color summaryColor;

    if (newCount == 0) {
      summaryText =
          'All $existsCount account${existsCount == 1 ? '' : 's'} already exist';
      summaryIcon = Icons.info_outline;
      summaryColor = colorScheme.tertiary;
    } else if (existsCount == 0) {
      summaryText =
          '$newCount new account${newCount == 1 ? '' : 's'} will be added';
      summaryIcon = Icons.check_circle_outline;
      summaryColor = Colors.green;
    } else {
      summaryText = '$newCount new, $existsCount already exist';
      summaryIcon = Icons.info_outline;
      summaryColor = colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: summaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: summaryColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(summaryIcon, color: summaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              summaryText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountItem(
    ThemeData theme,
    ColorScheme colorScheme,
    _AccountPreviewItem item,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.exists
              ? colorScheme.outline.withOpacity(0.2)
              : colorScheme.primary.withOpacity(0.3),
          width: item.exists ? 1 : 2,
        ),
      ),
      child: Row(
        children: [
          // Bank logo
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: item.bank != null && item.bank!.image.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      item.bank!.image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.account_balance,
                          color: colorScheme.onSurfaceVariant,
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.account_balance,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),

          const SizedBox(width: 12),

          // Bank name and account number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.bank?.shortName ?? item.bank?.name ?? 'Unknown Bank',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.entry.accountNumber,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Status badge
          _buildStatusBadge(theme, !item.exists),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, bool isNew) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isNew ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isNew ? 'NEW' : 'EXISTS',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: isNew ? Colors.green.shade700 : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    int newCount,
    double bottomSafeArea,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomSafeArea),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(context.l10nText('Cancel')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: newCount > 0 ? widget.onConfirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                newCount == 0
                    ? context.l10nText('Nothing to Import')
                    : '${context.l10nText('Import')} $newCount',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
