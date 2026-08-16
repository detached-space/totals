import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/repositories/reimbursement_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/utils/account_identity.dart';
import 'package:totals/utils/reimbursement_utils.dart';
import 'package:totals/utils/transaction_amounts.dart';

/// Handler for summary-related API endpoints
class SummaryHandler {
  final AccountRepository _accountRepo = AccountRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final ReimbursementRepository _reimbursementRepo = ReimbursementRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  Future<Set<String>> _reimbursementReferences(
    Iterable<Transaction> transactions,
  ) async {
    final references =
        await _reimbursementRepo.getLinkedReimbursementReferences(
      transactions.map((transaction) => transaction.reference),
    );
    final reimbursementCategoryIds =
        (await CategoryRepository().getCategories())
            .where(isReimbursementCategory)
            .map((category) => category.id)
            .whereType<int>()
            .toSet();
    for (final transaction in transactions) {
      if (transaction.selectedCategoryIds
          .any(reimbursementCategoryIds.contains)) {
        references.add(transaction.reference.trim());
      }
    }
    references.remove('');
    return references;
  }

  /// Returns a configured router with all summary routes
  Router get router {
    final router = Router();

    // GET /api/summary - Get overall summary
    router.get('/', _getSummary);

    // GET /api/summary/by-bank - Get summary grouped by bank
    router.get('/by-bank', _getSummaryByBank);

    // GET /api/summary/by-account - Get summary for each account
    router.get('/by-account', _getSummaryByAccount);

    return router;
  }

  /// Filter out orphaned transactions (transactions without matching accounts)
  Future<List<Transaction>> _filterOrphanedTransactions(
      List<Transaction> transactions) async {
    final accounts = await _accountRepo.getAccounts();

    return transactions.where((t) {
      if (t.bankId == null) return false;

      final bankAccounts = accounts.where((a) => a.bank == t.bankId).toList();
      if (bankAccounts.isEmpty) return false;

      if (t.bankId == CashConstants.bankId) {
        if (t.accountNumber == null || t.accountNumber!.isEmpty) {
          return true;
        }
        return bankAccounts
            .any((account) => account.accountNumber == t.accountNumber);
      }

      return true;
    }).toList();
  }

  /// GET /api/summary
  /// Returns aggregated summary across all accounts
  Future<Response> _getSummary(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final allTransactions = await _transactionRepo.getTransactions();
      final transactions = await _filterOrphanedTransactions(allTransactions);
      final reimbursementReferences =
          await _reimbursementReferences(transactions);
      final reimbursedExpenses =
          await _reimbursementRepo.getAppliedTotalsForExpenses(
        transactions.map((transaction) => transaction.reference),
      );

      // Calculate totals
      double totalBalance = 0;
      double totalSettledBalance = 0;
      double totalPendingCredit = 0;

      for (var account in accounts) {
        if (account.bank != CashConstants.bankId &&
            account.includeInTotals &&
            !account.isDormant) {
          totalBalance += account.balance;
        }
        totalSettledBalance += account.settledBalance ?? 0;
        totalPendingCredit += account.pendingCredit ?? 0;
      }

      // Calculate credit/debit totals from transactions
      double totalCredit = 0;
      double totalDebit = 0;

      for (var t in transactions) {
        if (t.type == 'CREDIT' &&
            !reimbursementReferences.contains(t.reference.trim())) {
          totalCredit += t.amount.abs();
        } else if (t.type == 'DEBIT') {
          totalDebit += expenseAmountAfterReimbursement(
            grossExpense: t.amount.abs(),
            reimbursedAmount: reimbursedExpenses[t.reference.trim()] ?? 0.0,
          );
        }
      }

      // Count unique banks
      final uniqueBanks = accounts.map((a) => a.bank).toSet();

      return Response.ok(
        jsonEncode({
          'totalBalance': totalBalance,
          'totalSettledBalance': totalSettledBalance,
          'totalPendingCredit': totalPendingCredit,
          'totalCredit': totalCredit,
          'totalDebit': totalDebit,
          'accountCount': accounts.length,
          'bankCount': uniqueBanks.length,
          'transactionCount': transactions.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch summary: $e', 500);
    }
  }

  /// GET /api/summary/by-bank
  /// Returns summary grouped by bank
  Future<Response> _getSummaryByBank(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final allTransactions = await _transactionRepo.getTransactions();
      final transactions = await _filterOrphanedTransactions(allTransactions);
      final reimbursementReferences =
          await _reimbursementReferences(transactions);
      final reimbursedExpenses =
          await _reimbursementRepo.getAppliedTotalsForExpenses(
        transactions.map((transaction) => transaction.reference),
      );

      // Group accounts by bank
      final Map<int, List<Account>> accountsByBank = {};
      for (var account in accounts) {
        accountsByBank.putIfAbsent(account.bank, () => []);
        accountsByBank[account.bank]!.add(account);
      }

      // Group transactions by bank
      final Map<int, List<Transaction>> transactionsByBank = {};
      for (var t in transactions) {
        if (t.bankId != null) {
          transactionsByBank.putIfAbsent(t.bankId!, () => []);
          transactionsByBank[t.bankId!]!.add(t);
        }
      }

      // Calculate summary for each bank
      final bankSummaries = await Future.wait(
        accountsByBank.entries.map((entry) async {
          final bankId = entry.key;
          final bankAccounts = entry.value;
          final bankTransactions = transactionsByBank[bankId] ?? [];
          final bank = await _getBankById(bankId);

          // Account totals
          double totalBalance = 0;
          double settledBalance = 0;
          double pendingCredit = 0;

          for (var account in bankAccounts) {
            if (account.includeInTotals && !account.isDormant) {
              totalBalance += account.balance;
            }
            settledBalance += account.settledBalance ?? 0;
            pendingCredit += account.pendingCredit ?? 0;
          }

          // Transaction totals
          double totalCredit = 0;
          double totalDebit = 0;

          for (var t in bankTransactions) {
            if (t.type == 'CREDIT' &&
                !reimbursementReferences.contains(t.reference.trim())) {
              totalCredit += t.amount.abs();
            } else if (t.type == 'DEBIT') {
              totalDebit += expenseAmountAfterReimbursement(
                grossExpense: t.amount.abs(),
                reimbursedAmount: reimbursedExpenses[t.reference.trim()] ?? 0.0,
              );
            }
          }

          return {
            'bankId': bankId,
            'bankName': bank?.name ?? 'Unknown Bank',
            'bankShortName': bank?.shortName ?? 'N/A',
            'bankImage': bank?.image ?? '',
            'totalBalance': totalBalance,
            'settledBalance': settledBalance,
            'pendingCredit': pendingCredit,
            'totalCredit': totalCredit,
            'totalDebit': totalDebit,
            'accountCount': bankAccounts.length,
            'transactionCount': bankTransactions.length,
          };
        }),
      );

      return Response.ok(
        jsonEncode(bankSummaries),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch bank summaries: $e', 500);
    }
  }

  /// GET /api/summary/by-account
  /// Returns summary for each individual account
  Future<Response> _getSummaryByAccount(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final allTransactions = await _transactionRepo.getTransactions();
      final transactions = await _filterOrphanedTransactions(allTransactions);
      final reimbursementReferences =
          await _reimbursementReferences(transactions);
      final reimbursedExpenses =
          await _reimbursementRepo.getAppliedTotalsForExpenses(
        transactions.map((transaction) => transaction.reference),
      );

      final accountSummaries = await Future.wait(
        accounts.map((account) async {
          final bank = await _getBankById(account.bank);

          // Find transactions for this account
          final accountTransactions = transactions.where((t) {
            if (t.bankId != account.bank) return false;
            if (account.bank == CashConstants.bankId) {
              return t.accountNumber == account.accountNumber;
            }
            if (bank == null) return false;
            return transactionBelongsToAccount(
              transaction: t,
              account: account,
              bank: bank,
              accounts: accounts,
            );
          }).toList();

          // Calculate transaction totals
          double totalCredit = 0;
          double totalDebit = 0;

          for (var t in accountTransactions) {
            if (t.type == 'CREDIT' &&
                !reimbursementReferences.contains(t.reference.trim())) {
              totalCredit += t.amount.abs();
            } else if (t.type == 'DEBIT') {
              totalDebit += expenseAmountAfterReimbursement(
                grossExpense: t.amount.abs(),
                reimbursedAmount: reimbursedExpenses[t.reference.trim()] ?? 0.0,
              );
            }
          }

          return {
            'accountNumber': account.accountNumber,
            'accountHolderName': account.accountHolderName,
            'bankId': account.bank,
            'bankName': bank?.name ?? 'Unknown Bank',
            'bankShortName': bank?.shortName ?? 'N/A',
            'bankImage': bank?.image ?? '',
            'balance': account.balance,
            'settledBalance': account.settledBalance,
            'pendingCredit': account.pendingCredit,
            'includeInTotals': account.includeInTotals,
            'isDormant': account.isDormant,
            'isDefault': account.isDefault,
            'totalCredit': totalCredit,
            'totalDebit': totalDebit,
            'transactionCount': accountTransactions.length,
          };
        }),
      );

      return Response.ok(
        jsonEncode(accountSummaries),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch account summaries: $e', 500);
    }
  }

  /// Finds a bank by ID from the database
  Future<Bank?> _getBankById(int bankId) async {
    if (bankId == CashConstants.bankId) {
      return Bank(
        id: CashConstants.bankId,
        name: CashConstants.bankName,
        shortName: CashConstants.bankShortName,
        codes: const [],
        image: CashConstants.bankImage,
        colors: CashConstants.bankColors,
      );
    }
    try {
      // Fetch banks from database (with caching)
      if (_cachedBanks == null) {
        _cachedBanks = await _bankConfigService.getBanks();
      }
      return _cachedBanks!.firstWhere((b) => b.id == bankId);
    } catch (e) {
      return null;
    }
  }

  /// Helper to create standardized error responses
  Response _errorResponse(String message, int statusCode) {
    return Response(
      statusCode,
      body: jsonEncode({
        'error': true,
        'message': message,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
