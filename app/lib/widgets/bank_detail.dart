import 'package:flutter/material.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/main.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/accounts_summary.dart';

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
  bool isBankDetailExpanded = false;
  bool showTotalBalance = false;
  List<String> visibleTotalBalancesForSubCards = [];

  @override
  Widget build(BuildContext context) {
    // Replace with your actual data fetching logic
    return Column(
      children: [
        GestureDetector(
            onTap: () {
              setState(() {
                isBankDetailExpanded = !isBankDetailExpanded;
              });
            },
            child: Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              elevation: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF172B6D),
                      Color(0xFF274AB9),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 28.0, 16.0, 28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            AppConstants.banks
                                .firstWhere(
                                    (element) => element.id == widget.bankId)
                                .image,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment
                              .spaceBetween, // Centers horizontally
                          children: [
                            Text(
                              AppConstants.banks
                                  .firstWhere(
                                      (element) => element.id == widget.bankId)
                                  .name,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFFF1F4FF),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Icon(
                              isBankDetailExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Color(0xFFF1F4FF),
                            ),
                          ]),
                      const SizedBox(
                        height: 4,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'ACCOUNT BALANCE',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9FABD2),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 8),
                          GestureDetector(
                              onTap: () {
                                setState(() {
                                  showTotalBalance = !showTotalBalance;
                                  visibleTotalBalancesForSubCards =
                                      visibleTotalBalancesForSubCards.length ==
                                              0
                                          ? widget.accountSummaries
                                              .map((e) => e.accountNumber)
                                              .toList()
                                          : [];
                                });
                              },
                              child: Icon(
                                  showTotalBalance == true
                                      ? Icons.visibility_off
                                      : Icons.remove_red_eye_outlined,
                                  color: Colors.grey[400],
                                  size: 20)),
                        ],
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Container(
                        width: double.infinity,
                        child: Text(
                          showTotalBalance
                              ? formatNumberWithComma(double.tryParse(widget
                                      .accountSummaries
                                      .fold(
                                          0.0,
                                          (sum, bank) =>
                                              sum +
                                              bank.balance) // Replace with your actual balance calculation logic
                                      .toString())) +
                                  " ETB"
                              : "******",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      isBankDetailExpanded
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment
                                  .spaceBetween, // Centers horizontally
                              children: [
                                Text(
                                  "Total Credit",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                    formatNumberWithComma(double.tryParse(widget
                                        .accountSummaries
                                        .fold(
                                            0.0,
                                            (sum, bank) =>
                                                sum + bank.totalCredit)
                                        .toString())),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    )),
                              ],
                            )
                          : Container(),
                      isBankDetailExpanded
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment
                                  .spaceBetween, // Centers horizontally
                              children: [
                                Text(
                                  "Total Debit",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                    formatNumberWithComma(double.tryParse(widget
                                        .accountSummaries
                                        .fold(
                                            0.0,
                                            (sum, bank) =>
                                                sum + bank.totalDebit)
                                        .toString())),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 14,
                                    )),
                              ],
                            )
                          : Container(),
                    ],
                  ),
                ),
              ),
            )),
        AccountsSummaryList(
            accountSummaries: widget.accountSummaries,
            visibleTotalBalancesForSubCards: visibleTotalBalancesForSubCards),
      ],
    );
  }
}
