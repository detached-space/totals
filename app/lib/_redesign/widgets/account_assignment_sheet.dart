import 'package:flutter/material.dart';
import 'package:totals/models/account.dart';
import 'package:totals/providers/transaction_provider.dart';

/// Bottom sheet listing a bank's accounts across ALL profiles so the user can
/// pin one or more transactions to a specific account. Returns the chosen
/// account number, or null if dismissed.
///
/// Shared by the single-transaction move (transaction details sheet) and the
/// multi-select bulk move (money page). Only meaningful when the bank has two
/// or more accounts — callers gate on that. Each row shows the owning profile
/// so same-bank accounts split across profiles are unambiguous.
Future<String?> showAccountAssignmentSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required int bankId,
  String? currentOwner,
  String title = 'Assign to account',
}) {
  final accounts = provider.sameBankAccountsAcrossProfiles(bankId);
  final owner = currentOwner?.trim();
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final account in accounts)
              ListTile(
                title: Text(
                  account.accountHolderName.trim().isNotEmpty
                      ? account.accountHolderName
                      : account.accountNumber,
                ),
                subtitle: Text(_subtitleFor(provider, account)),
                trailing: account.accountNumber == owner
                    ? const Icon(Icons.check)
                    : null,
                onTap: () =>
                    Navigator.of(sheetContext).pop(account.accountNumber),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Account number plus its profile name (e.g. "01320…2500 · Business") so the
/// user can tell apart same-bank accounts that live in different profiles.
String _subtitleFor(TransactionProvider provider, Account account) {
  final profile = provider.profileLabelFor(account.profileId);
  if (profile.isEmpty) return account.accountNumber;
  return '${account.accountNumber} · $profile';
}
