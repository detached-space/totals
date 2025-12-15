import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/transaction_repository.dart';

/// Handler for summary-related API endpoints
class SummaryHandler {
  final AccountRepository _accountRepo = AccountRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();

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

  /// GET /api/summary
  /// Returns aggregated summary across all accounts
  Future<Response> _getSummary(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();
      final transactions = await _transactionRepo.getTransactions();

      // Calculate totals
      double totalBalance = 0;
      double totalSettledBalance = 0;
      double totalPendingCredit = 0;

      for (var account in accounts) {
        totalBalance += account.balance;
        totalSettledBalance += account.settledBalance ?? 0;
        totalPendingCredit += account.pendingCredit ?? 0;
      }

      // Calculate credit/debit totals from transactions
      double totalCredit = 0;
      double totalDebit = 0;

      for (var t in transactions) {
        if (t.type == 'CREDIT') {
          totalCredit += t.amount.abs();
        } else if (t.type == 'DEBIT') {
          totalDebit += t.amount.abs();
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
      final transactions = await _transactionRepo.getTransactions();

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
      final bankSummaries = accountsByBank.entries.map((entry) {
        final bankId = entry.key;
        final bankAccounts = entry.value;
        final bankTransactions = transactionsByBank[bankId] ?? [];
        final bank = _getBankById(bankId);

        // Account totals
        double totalBalance = 0;
        double settledBalance = 0;
        double pendingCredit = 0;

        for (var account in bankAccounts) {
          totalBalance += account.balance;
          settledBalance += account.settledBalance ?? 0;
          pendingCredit += account.pendingCredit ?? 0;
        }

        // Transaction totals
        double totalCredit = 0;
        double totalDebit = 0;

        for (var t in bankTransactions) {
          if (t.type == 'CREDIT') {
            totalCredit += t.amount.abs();
          } else if (t.type == 'DEBIT') {
            totalDebit += t.amount.abs();
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
      }).toList();

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
      final transactions = await _transactionRepo.getTransactions();

      final accountSummaries = accounts.map((account) {
        final bank = _getBankById(account.bank);

        // Find transactions for this account
        final accountTransactions = transactions.where((t) {
          if (t.bankId != account.bank) return false;

          // Match by account number (handling partial matches for different banks)
          if (t.accountNumber == null) {
            // Include transactions with no account number if this is the only account for the bank
            final bankAccountCount =
                accounts.where((a) => a.bank == account.bank).length;
            return bankAccountCount == 1;
          }

          // Different banks use different matching logic
          switch (account.bank) {
            case 1: // CBE - match last 4 digits
              if (account.accountNumber.length >= 4 &&
                  t.accountNumber!.length >= 4) {
                return t.accountNumber!
                        .substring(t.accountNumber!.length - 4) ==
                    account.accountNumber
                        .substring(account.accountNumber.length - 4);
              }
              break;
            case 4: // Dashen - match last 3 digits
              if (account.accountNumber.length >= 3 &&
                  t.accountNumber!.length >= 3) {
                return t.accountNumber!
                        .substring(t.accountNumber!.length - 3) ==
                    account.accountNumber
                        .substring(account.accountNumber.length - 3);
              }
              break;
            case 3: // Bank of Abyssinia - match last 2 digits
              if (account.accountNumber.length >= 2 &&
                  t.accountNumber!.length >= 2) {
                return t.accountNumber!
                        .substring(t.accountNumber!.length - 2) ==
                    account.accountNumber
                        .substring(account.accountNumber.length - 2);
              }
              break;
            default:
              return t.bankId == account.bank;
          }

          return t.bankId == account.bank;
        }).toList();

        // Calculate transaction totals
        double totalCredit = 0;
        double totalDebit = 0;

        for (var t in accountTransactions) {
          if (t.type == 'CREDIT') {
            totalCredit += t.amount.abs();
          } else if (t.type == 'DEBIT') {
            totalDebit += t.amount.abs();
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
          'totalCredit': totalCredit,
          'totalDebit': totalDebit,
          'transactionCount': accountTransactions.length,
        };
      }).toList();

      return Response.ok(
        jsonEncode(accountSummaries),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch account summaries: $e', 500);
    }
  }

  /// Finds a bank by ID from AppConstants
  Bank? _getBankById(int bankId) {
    try {
      return AppConstants.banks.firstWhere((b) => b.id == bankId);
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
