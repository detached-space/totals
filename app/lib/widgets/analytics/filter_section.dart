import 'package:flutter/material.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';

class FilterSection extends StatefulWidget {
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
  State<FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends State<FilterSection> {
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (mounted) {
        setState(() {
          _banks = banks;
        });
      }
    } catch (e) {
      print("debug: Error loading banks: $e");
    }
  }

  Bank? _getBankInfo(int bankId) {
    try {
      return _banks.firstWhere((element) => element.id == bankId);
    } catch (e) {
      return _banks.isNotEmpty ? _banks.first : null;
    }
  }

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
                widget.selectedBankFilter == null,
                onTap: () => widget.onBankFilterChanged(null),
              ),
              const SizedBox(width: 8),
              ...widget.bankSummaries.map((bank) {
                final bankInfo = _getBankInfo(bank.bankId);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildFilterChip(
                    context,
                    bankInfo?.shortName ?? "Bank ${bank.bankId}",
                    widget.selectedBankFilter == bank.bankId,
                    onTap: () => widget.onBankFilterChanged(bank.bankId),
                  ),
                );
              }),
            ],
          ),
        ),
        if (widget.selectedBankFilter != null) ...[
          const SizedBox(height: 16),
          _buildAccountFilterSection(context),
        ],
      ],
    );
  }

  Widget _buildAccountFilterSection(BuildContext context) {
    // Filter accounts by selected bank
    final bankAccounts = widget.accounts
        .where((a) => a.bankId == widget.selectedBankFilter)
        .toList();

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
            widget.selectedAccountFilter == null,
            onTap: () => widget.onAccountFilterChanged(null),
          ),
          const SizedBox(width: 8),
          ...bankAccounts.map((account) {
            final accountDisplay = account.accountNumber.length > 4
                ? account.accountNumber
                    .substring(account.accountNumber.length - 4)
                : account.accountNumber;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                context,
                accountDisplay,
                widget.selectedAccountFilter == account.accountNumber,
                onTap: () =>
                    widget.onAccountFilterChanged(account.accountNumber),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, bool isSelected,
      {VoidCallback? onTap}) {
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
