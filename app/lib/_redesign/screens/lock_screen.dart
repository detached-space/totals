import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/widgets/finance_lock_surface.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/bank_detection_startup_service.dart';

class RedesignLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const RedesignLockScreen({super.key, required this.onUnlock});

  @override
  State<RedesignLockScreen> createState() => _RedesignLockScreenState();
}

class _RedesignLockScreenState extends State<RedesignLockScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(BankDetectionStartupService.runOnAppOpen());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final isPrimingHome = provider.dataVersion == 0 && provider.isLoading;

    return FinanceLockSurface(
      statusText: context.l10nText(
        isPrimingHome
            ? 'Preparing your latest totals...'
            : 'Your finances are locked',
      ),
      onTap: widget.onUnlock,
      unlockPromptText: context.l10nText('Tap to unlock'),
    );
  }
}
