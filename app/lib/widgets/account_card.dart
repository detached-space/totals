import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart'; 
import 'package:totals/data/consts.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/utils/gradients.dart';
import 'package:totals/utils/text_utils.dart';

class AccountCard extends StatefulWidget {
  final AccountSummary account;
  final VoidCallback? onTap;
  final Widget? expandedContent; // Content to show when expanded

  const AccountCard({
    super.key,
    required this.account,
    this.onTap,
    this.expandedContent,
  });

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool isHidden = false;
  bool copied = false;

  void _toggleVisibility() {
    setState(() {
      isHidden = !isHidden;
    });
  }

  void _copyAccountNumber() {
    Clipboard.setData(ClipboardData(text: widget.account.accountNumber));
    setState(() {
      copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          copied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine Bank Info
    final bank = AppConstants.banks.firstWhere(
      (b) => b.id == widget.account.bankId,
      orElse: () => AppConstants.banks.isNotEmpty
          ? AppConstants.banks[0]
          : const Bank(
              id: 0,
              name: "Unknown",
              shortName: "?",
              codes: [],
              image: "assets/images/cbe.png"), 
    );

    final displayBalance = isHidden
        ? "*****"
        : "${formatNumberWithComma(widget.account.balance)} ETB";
    final displayAccount = isHidden
        ? "**** **** **** ****"
        : widget.account.accountNumber;
    
    final isExpanded = widget.expandedContent != null;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: GradientUtils.getGradient(widget.account.bankId),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Card Face (Preserve Aspect Ratio) ---
              AspectRatio(
                aspectRatio: 1.586,
                child: Stack(
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Row: Bank Name (Left) & Totals Logo (Right)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  bank.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        offset: Offset(0, 1),
                                        blurRadius: 2,
                                      )
                                    ],
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: 0.7,
                                // TOP LOGO IS TOTALS LOGO
                                child: SvgPicture.asset(
                                  'assets/images/logo.svg',
                                  width: 24, 
                                  height: 24,
                                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                ),
                              ),
                            ],
                          ),
          
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
                                  top: 0, bottom: 0, left: 14,
                                  child: Container(width: 1, color: Colors.yellow[500]!.withOpacity(0.1)),
                                ),
                                Positioned(
                                  top: 0, bottom: 0, right: 14,
                                  child: Container(width: 1, color: Colors.yellow[500]!.withOpacity(0.1)),
                                ),
                                Positioned(
                                  left: 0, right: 0, top: 10,
                                  child: Container(height: 1, color: Colors.yellow[500]!.withOpacity(0.1)),
                                ),
                                Positioned(
                                  left: 0, right: 0, bottom: 10,
                                  child: Container(height: 1, color: Colors.yellow[500]!.withOpacity(0.1)),
                                ),
                              ],
                            ),
                          ),
          
                          // Bottom Section
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Balance & Expansion Indicator
                              Row(
                                children: [
                                  Text(
                                    displayBalance,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                      onTap: _toggleVisibility,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          isHidden
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: Colors.white.withOpacity(0.7),
                                          size: 20,
                                        ),
                                      )),
                                  const SizedBox(width: 4),
                                  // Expansion chevron
                                  Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 20,
                                  )
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Account # & Copy & Bank Logo (Bottom)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "ACCOUNT NUMBER",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 10,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            displayAccount,
                                            style: TextStyle(
                                              fontFamily: 'Courier', 
                                              color: Colors.white,
                                              fontSize: 14,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: _copyAccountNumber,
                                            child: Container(
                                                padding: const EdgeInsets.all(4),
                                                child: copied
                                                    ? const Icon(Icons.check,
                                                        color: Colors.greenAccent,
                                                        size: 16)
                                                    : Icon(Icons.copy,
                                                        color: Colors.white
                                                            .withOpacity(0.7),
                                                        size: 16)),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                  Opacity(
                                    opacity: 0.7,
                                    // BOTTOM LOGO IS BANK LOGO
                                    child: Image.asset(bank.image,
                                        width: 32, height: 32),
                                  ),
                                ],
                              )
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
              
              // --- Expanded Content ---
              if (isExpanded && widget.expandedContent != null)
                 Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: widget.expandedContent!,
                 )
            ],
          ),
        ),
      ),
    );
  }
}
