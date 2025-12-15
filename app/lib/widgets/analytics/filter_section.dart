import 'package:flutter/material.dart';
import 'package:totals/data/consts.dart';

class FilterSection extends StatelessWidget {
  final List bankSummaries;
  final int? selectedBankFilter;
  final String? selectedAccountFilter;
  final List accounts;
  final ValueChanged<int?> onBankFilterChanged;
  final ValueChanged<String?> onAccountFilterChanged;

  const FilterSection({
    super.key,
    required this.bankSummaries,
    required this.selectedBankFilter,
    required this.selectedAccountFilter,
    required this.accounts,
    required this.onBankFilterChanged,
    required this.onAccountFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterChip(
                context,
                'All',
                selectedBankFilter == null,
                onTap: () => onBankFilterChanged(null),
              ),
              const SizedBox(width: 8),
              ...bankSummaries.map((bank) {
                final bankInfo = AppConstants.banks.firstWhere(
                  (b) => b.id == bank.bankId,
                  orElse: () => AppConstants.banks.first,
                );
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFilterChip(
                    context,
                    bankInfo.shortName,
                    selectedBankFilter == bank.bankId,
                    onTap: () => onBankFilterChanged(bank.bankId),
                  ),
                );
              }),
            ],
          ),
        ),
        if (selectedBankFilter != null) ...[
          const SizedBox(height: 16),
          _buildAccountFilterSection(context),
        ],
      ],
    );
  }

  Widget _buildAccountFilterSection(BuildContext context) {
    // Filter accounts by selected bank
    final bankAccounts = accounts.where((a) => a.bankId == selectedBankFilter).toList();
    
    // Only show if there are multiple accounts
    if (bankAccounts.length <= 1) {
      return const SizedBox.shrink();
    }
    
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            context,
            'All',
            selectedAccountFilter == null,
            onTap: () => onAccountFilterChanged(null),
          ),
          const SizedBox(width: 8),
          ...bankAccounts.map((account) {
            final accountDisplay = account.accountNumber.length > 4
                ? account.accountNumber.substring(account.accountNumber.length - 4)
                : account.accountNumber;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                context,
                accountDisplay,
                selectedAccountFilter == account.accountNumber,
                onTap: () => onAccountFilterChanged(account.accountNumber),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, bool isSelected, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

