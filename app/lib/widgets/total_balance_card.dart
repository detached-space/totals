import 'package:flutter/material.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/utils/gradients.dart';
import 'package:totals/utils/text_utils.dart';

class TotalBalanceCard extends StatefulWidget {
  final AllSummary? summary;
  final bool showBalance;
  final VoidCallback onToggleBalance;
  final String title;
  final String? subtitle;
  final int gradientId;
  final String logoAsset;

  const TotalBalanceCard({
    super.key,
    required this.summary,
    required this.showBalance,
    required this.onToggleBalance,
    this.title = "TOTAL BALANCE",
    this.subtitle,
    this.gradientId = 99,
    this.logoAsset = 'assets/images/logo.svg',
  });

  @override
  State<TotalBalanceCard> createState() => _TotalBalanceCardState();
}

class _TotalBalanceCardState extends State<TotalBalanceCard> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final displayBalance = widget.showBalance
        ? "${formatNumberWithComma(widget.summary?.totalBalance ?? 0.0)} ETB"
        : "******";

    return GestureDetector(
      onTap: () {
        setState(() {
          isExpanded = !isExpanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: GradientUtils.getGradient(widget.gradientId),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Card Face ---
              Stack(
                children: [
                  // Glossy Overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.1),
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(0.0),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Opacity(
                              opacity: 0.8,
                              child: widget.logoAsset.endsWith('.svg')
                                  ? const Icon(
                                      Icons.account_balance,
                                      color: Colors.white,
                                      size: 24,
                                    )
                                  : Image.asset(
                                      widget.logoAsset,
                                      width: 32,
                                      height: 32,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return const Icon(
                                          Icons.account_balance,
                                          color: Colors.white,
                                          size: 24,
                                        );
                                      },
                                    ),
                            )
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Chip
                        Container(
                          width: 44,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.yellow[200]!.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.yellow[200]!.withOpacity(0.3)),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: 14,
                                child: Container(
                                    width: 1,
                                    color:
                                        Colors.yellow[500]!.withOpacity(0.1)),
                              ),
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: 14,
                                child: Container(
                                    width: 1,
                                    color:
                                        Colors.yellow[500]!.withOpacity(0.1)),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 10,
                                child: Container(
                                    height: 1,
                                    color:
                                        Colors.yellow[500]!.withOpacity(0.1)),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 10,
                                child: Container(
                                    height: 1,
                                    color:
                                        Colors.yellow[500]!.withOpacity(0.1)),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Balance Row
                        Row(
                          children: [
                            Text(
                              displayBalance,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: widget.onToggleBalance,
                              child: Icon(
                                widget.showBalance
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.white.withOpacity(0.6),
                                size: 20,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Colors.white.withOpacity(0.6),
                            )
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Stats / Info
                        Text(
                          widget.subtitle ??
                              "${widget.summary?.banks ?? 0} Banks | ${widget.summary?.accounts ?? 0} Accounts",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // --- Expanded Details ---
              if (isExpanded)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      Divider(color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total Credit",
                            style: TextStyle(
                              color: Colors.white70,
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total Debit",
                            style: TextStyle(
                              color: Colors.white70,
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
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
