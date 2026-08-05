import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/services/owned_account_transfer_service.dart';

/// Finds transactions whose notifications should be withdrawn because they
/// represent movement between the user's own accounts.
class SelfTransferNotificationResolver {
  final OwnedAccountTransferService _ownedAccountTransferService;

  SelfTransferNotificationResolver({
    OwnedAccountTransferService? ownedAccountTransferService,
  }) : _ownedAccountTransferService =
            ownedAccountTransferService ?? OwnedAccountTransferService();

  List<Transaction> transactionsToSuppress({
    required Transaction transaction,
    required Iterable<Transaction> transactions,
    required Iterable<Bank> banks,
    required Iterable<Account> accounts,
    required Iterable<Category> categories,
  }) {
    final reference = transaction.reference.trim();
    if (reference.isEmpty) return const <Transaction>[];

    final transactionList = transactions.toList(growable: false);
    final matches = _ownedAccountTransferService.findMatches(
      transactions: transactionList,
      banks: banks,
      accounts: accounts,
    );
    for (final match in matches) {
      if (match.debitTransaction.reference == reference ||
          match.creditTransaction.reference == reference) {
        return <Transaction>[
          match.debitTransaction,
          match.creditTransaction,
        ];
      }
    }

    final cashPair = _cashTransferPair(transaction, transactionList);
    if (cashPair.isNotEmpty) return cashPair;

    final selfCategoryIds = categories
        .where((category) => category.name.trim().toLowerCase() == 'self')
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
    if (transaction.selectedCategoryIds.any(selfCategoryIds.contains)) {
      return <Transaction>[transaction];
    }

    return const <Transaction>[];
  }

  List<Transaction> _cashTransferPair(
    Transaction transaction,
    List<Transaction> transactions,
  ) {
    final reference = transaction.reference;
    String linkedReference;
    if (transaction.bankId == CashConstants.bankId) {
      if (!reference.startsWith(CashConstants.atmReferencePrefix)) {
        return const <Transaction>[];
      }
      linkedReference =
          reference.substring(CashConstants.atmReferencePrefix.length);
    } else {
      linkedReference = '${CashConstants.atmReferencePrefix}$reference';
    }

    Transaction? linkedTransaction;
    for (final candidate in transactions) {
      final isExpectedCashSide = transaction.bankId == CashConstants.bankId
          ? candidate.bankId != CashConstants.bankId
          : candidate.bankId == CashConstants.bankId;
      if (candidate.reference == linkedReference && isExpectedCashSide) {
        linkedTransaction = candidate;
        break;
      }
    }
    if (linkedTransaction == null) return const <Transaction>[];
    return <Transaction>[transaction, linkedTransaction];
  }
}
