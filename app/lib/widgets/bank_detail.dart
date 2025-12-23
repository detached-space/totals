import 'package:flutter/material.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/widgets/accounts_summary.dart';
import 'package:totals/widgets/total_balance_card.dart';

class BankDetail extends StatefulWidget {
  final int bankId;
  final List<AccountSummary> accountSummaries;

  const BankDetail({
    Key? key,
    required this.bankId,
    required this.accountSummaries,
  }) : super(key: key);

  @override
  State<BankDetail> createState() => _BankDetailState();
}

class _BankDetailState extends State<BankDetail> {
  // isBankDetailExpanded is no longer needed as TotalBalanceCard handles its own expansion.
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];
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

  Bank? _getBankInfo() {
    try {
      return _banks.firstWhere((element) => element.id == widget.bankId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate totals for this bank
    double totalBalance = 0;
    double totalCredit = 0;
    double totalDebit = 0;

    for (var account in widget.accountSummaries) {
      totalBalance += account.balance;
      totalCredit += account.totalCredit;
      totalDebit += account.totalDebit;
    }

    final bankSummary = AllSummary(
      totalCredit: totalCredit,
      totalDebit: totalDebit,
      banks: 1,
      totalBalance: totalBalance,
      accounts: widget.accountSummaries.length,
    );

    final bankInfo = _getBankInfo();
    final bankName = bankInfo?.name ?? "Unknown Bank";
    final bankImage = bankInfo?.image ?? "assets/images/cbe.png";

    return Column(
      children: [
        const SizedBox(height: 12),
        // Replaced custom Card with TotalBalanceCard (Blue Gradient ID 99)
        TotalBalanceCard(
          summary: bankSummary,
          showBalance: showTotalBalance,
          title: bankName.toUpperCase(),
          logoAsset: bankImage,
          gradientId: widget.bankId,
          colors: bankInfo?.colors, // Use colors from bank data if available
          subtitle: "${widget.accountSummaries.length} Accounts",
          onToggleBalance: () {
            setState(() {
              showTotalBalance = !showTotalBalance;
              // Migrate logic: toggling main balance also toggles all sub-cards
              visibleTotalBalancesForSubCards = visibleTotalBalancesForSubCards
                      .isEmpty
                  ? widget.accountSummaries.map((e) => e.accountNumber).toList()
                  : [];
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AccountsSummaryList(
              accountSummaries: widget.accountSummaries,
              visibleTotalBalancesForSubCards: visibleTotalBalancesForSubCards),
        ),
      ],
    );
  }
}
