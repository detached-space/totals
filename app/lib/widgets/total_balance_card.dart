import 'package:flutter/material.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/utils/text_utils.dart';

class TotalBalanceCard extends StatefulWidget {
  final AllSummary? summary;
  final bool showBalance;
  final VoidCallback onToggleBalance;

  const TotalBalanceCard({
    super.key,
    required this.summary,
    required this.showBalance,
    required this.onToggleBalance,
  });

  @override
  State<TotalBalanceCard> createState() => _TotalBalanceCardState();
}

class _TotalBalanceCardState extends State<TotalBalanceCard> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          isExpanded = !isExpanded;
        });
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 28.0, 16.0, 28.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'TOTAL BALANCE',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9FABD2),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onToggleBalance,
                          child: Icon(
                            widget.showBalance
                                ? Icons.visibility_off
                                : Icons.remove_red_eye_outlined,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "${widget.showBalance ? (formatNumberWithComma(widget.summary?.totalBalance) ?? 0.0) : "******"} ETB",
                          style: const TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      child: Text(
                        "${widget.summary?.banks ?? 0} Banks | ${widget.summary?.accounts ?? 0} Accounts",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFF7F8FB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 28.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Total Credit",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                  "${formatNumberWithComma(widget.summary?.totalCredit)} ETB",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.white)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Total Debit",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                  "${formatNumberWithComma(widget.summary?.totalDebit)} ETB",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.white)),
                            ],
                          ),
                        ],
                      ))
                  : Container()
            ],
          ),
        ),
      ),
    );
  }
}
