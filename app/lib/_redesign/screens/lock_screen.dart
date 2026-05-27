import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/bank_detection_startup_service.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';

class RedesignLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const RedesignLockScreen({super.key, required this.onUnlock});

  @override
  State<RedesignLockScreen> createState() => _RedesignLockScreenState();
}

class _RedesignLockScreenState extends State<RedesignLockScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    unawaited(BankDetectionStartupService.runOnAppOpen());

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final bankSummaries = provider.bankSummaries;
    final isPrimingHome = provider.dataVersion == 0 && provider.isLoading;

    // Resolve bank images (exclude cash wallet)
    final bankImages = <String>[];
    for (final bs in bankSummaries) {
      if (bs.bankId == CashConstants.bankId) continue;
      try {
        final bank = AppConstants.banks.firstWhere((b) => b.id == bs.bankId);
        bankImages.add(bank.image);
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onUnlock,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated logo with glow
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnim.value,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryLight
                                .withValues(alpha: _glowAnim.value * 0.18),
                            blurRadius: 28 + (_glowAnim.value * 14),
                            spreadRadius: _glowAnim.value * 6,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  );
                },
                child: Image.asset(
                  'assets/images/logo-text.png',
                  width: 120,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),

              // Subtitle
              Text(
                context.l10nText(
                  isPrimingHome
                      ? 'Preparing your latest totals...'
                      : 'Your finances are locked',
                ),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(context),
                ),
              ),

              // Bank icons row
              // if (bankImages.isNotEmpty) ...[
              //   const SizedBox(height: 20),
              //   Row(
              //     mainAxisSize: MainAxisSize.min,
              //     children: bankImages.map((image) {
              //       return Padding(
              //         padding: const EdgeInsets.symmetric(horizontal: 4),
              //         child: Container(
              //           width: 36,
              //           height: 36,
              //           decoration: BoxDecoration(
              //             color: AppColors.cardColor(context),
              //             borderRadius: BorderRadius.circular(10),
              //             border: Border.all(
              //                 color: AppColors.borderColor(context)),
              //           ),
              //           child: ClipRRect(
              //             borderRadius: BorderRadius.circular(9),
              //             child: Image.asset(
              //               image,
              //               fit: BoxFit.cover,
              //               errorBuilder: (_, __, ___) => Icon(
              //                 AppIcons.account_balance_rounded,
              //                 size: 18,
              //                 color: AppColors.textTertiary(context),
              //               ),
              //             ),
              //           ),
              //         ),
              //       );
              //     }).toList(),
              //   ),
              // ],

              const SizedBox(height: 60),

              // Unlock prompt
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      AppIcons.fingerprint_rounded,
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10nText('Tap to unlock'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
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
