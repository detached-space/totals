import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/repositories/transaction_repository.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/bank_config_service.dart';

/// Handler for transaction-related API endpoints
class TransactionsHandler {
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AccountRepository _accountRepo = AccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  /// Returns a configured router with all transaction routes
  Router get router {
    final router = Router();

    // GET /api/transactions - List all transactions with filtering/pagination
    router.get('/', _getTransactions);

    // GET /api/transactions/stats - Get transaction statistics by account
    router.get('/stats', _getTransactionStats);

    return router;
  }

  /// GET /api/transactions
  /// Returns transactions with optional filtering and pagination
  ///
  /// Query Parameters:
  /// - bankId: Filter by bank ID
  /// - type: Filter by CREDIT or DEBIT
  /// - status: Filter by PENDING, CLEARED, SYNCED
  /// - limit: Number of results (default: 20)
  /// - offset: Pagination offset (default: 0)
  /// - from: Start date (ISO 8601)
  /// - to: End date (ISO 8601)
  Future<Response> _getTransactions(Request request) async {
    try {
      final queryParams = request.url.queryParameters;

      // Parse query parameters
      final bankId = int.tryParse(queryParams['bankId'] ?? '');
      final accountNumber = queryParams['accountNumber'];
      final type = queryParams['type'];
      final status = queryParams['status'];
      final limit = int.tryParse(queryParams['limit'] ?? '20') ?? 20;
      final offset = int.tryParse(queryParams['offset'] ?? '0') ?? 0;
      final fromDate = queryParams['from'];
      final toDate = queryParams['to'];

      // If accountNumber is provided, validate that the account exists
      if (accountNumber != null && bankId != null) {
        final accountExists =
            await _accountRepo.accountExists(accountNumber, bankId);
        if (!accountExists) {
          return _errorResponse('Account not found', 404);
        }
      }

      // Fetch all transactions from database
      List<Transaction> transactions = await _transactionRepo.getTransactions();

      // Filter out orphaned transactions (transactions without matching accounts)
      transactions = await _filterOrphanedTransactions(transactions);

      // Apply filters
      transactions = await _applyFilters(
        transactions,
        bankId: bankId,
        accountNumber: accountNumber,
        type: type,
        status: status,
        fromDate: fromDate,
        toDate: toDate,
      );

      // Get total count before pagination
      final total = transactions.length;

      // Apply pagination
      transactions = transactions.skip(offset).take(limit).toList();

      // Enrich with bank info
      final enrichedTransactions = await Future.wait(
        transactions.map((t) => _enrichTransactionWithBankInfo(t)),
      );

      return Response.ok(
        jsonEncode({
          'data': enrichedTransactions,
          'total': total,
          'limit': limit,
          'offset': offset,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch transactions: $e', 500);
    }
  }

  /// GET /api/transactions/stats
  /// Returns transaction statistics grouped by bank account
  Future<Response> _getTransactionStats(Request request) async {
    try {
      final transactions = await _transactionRepo.getTransactions();

      // Group transactions by bankId
      final Map<int, List<Transaction>> groupedByBank = {};
      for (var t in transactions) {
        if (t.bankId != null) {
          groupedByBank.putIfAbsent(t.bankId!, () => []);
          groupedByBank[t.bankId!]!.add(t);
        }
      }

      // Calculate stats for each bank
      final byAccount = await Future.wait(
        groupedByBank.entries.map((entry) async {
          final bankId = entry.key;
          final bankTransactions = entry.value;
          final bank = await _getBankById(bankId);

          double volume = 0;
          for (var t in bankTransactions) {
            volume += t.amount.abs();
          }

          return {
            'bankId': bankId,
            'name': bank?.shortName ?? 'Unknown',
            'bankName': bank?.name ?? 'Unknown Bank',
            'volume': volume,
            'count': bankTransactions.length,
          };
        }),
      );

      // Calculate totals
      double totalVolume = 0;
      int totalCount = 0;
      for (var stat in byAccount) {
        totalVolume += stat['volume'] as double;
        totalCount += stat['count'] as int;
      }

      return Response.ok(
        jsonEncode({
          'byAccount': byAccount,
          'totals': {
            'totalVolume': totalVolume,
            'totalCount': totalCount,
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch transaction stats: $e', 500);
    }
  }

  /// Filter out orphaned transactions (transactions without matching accounts)
  Future<List<Transaction>> _filterOrphanedTransactions(
      List<Transaction> transactions) async {
    final accounts = await _accountRepo.getAccounts();
    final banks = await _bankConfigService.getBanks();

    return transactions.where((t) {
      if (t.bankId == null) return false;

      final bankAccounts = accounts.where((a) => a.bank == t.bankId).toList();
      if (bankAccounts.isEmpty) return false;

      if (t.accountNumber != null && t.accountNumber!.isNotEmpty) {
        for (var account in bankAccounts) {
          bool matches = false;
          final bank = banks.firstWhere((b) => b.id == t.bankId);

          if (bank.uniformMasking == true) {
            matches = t.accountNumber!
                    .substring(t.accountNumber!.length - bank.maskPattern!) ==
                account.accountNumber.substring(
                    account.accountNumber.length - bank.maskPattern!);
          } else if (bank.uniformMasking == false) {
            matches = true;
          } else {
            matches = t.accountNumber == account.accountNumber;
          }

          if (matches) return true;
        }
        return false;
      } else {
        return bankAccounts.length == 1;
      }
    }).toList();
  }

  /// Apply filters to the transaction list
  Future<List<Transaction>> _applyFilters(
    List<Transaction> transactions, {
    int? bankId,
    String? accountNumber,
    String? type,
    String? status,
    String? fromDate,
    String? toDate,
  }) async {
    final banks = await _bankConfigService.getBanks();
    return transactions.where((t) {
      // Filter by bankId
      if (bankId != null && t.bankId != bankId) {
        return false;
      }

      // Filter by accountNumber if provided
      if (accountNumber != null && bankId != null) {
        bool matchesAccount = false;
        // This will be validated against accounts, so we can use simple matching here
        if (t.accountNumber != null) {
          final bank = banks.firstWhere((b) => b.id == t.bankId);
          if (bank.uniformMasking == true) {
            matchesAccount = t.accountNumber!
                    .substring(t.accountNumber!.length - bank.maskPattern!) ==
                accountNumber
                    .substring(accountNumber.length - bank.maskPattern!);
          } else if (bank.uniformMasking == false) {
            matchesAccount = true;
          } else {
            matchesAccount = t.accountNumber == accountNumber;
          }
        }
        if (!matchesAccount) return false;
      }

      // Filter by type (CREDIT/DEBIT)
      if (type != null && t.type?.toUpperCase() != type.toUpperCase()) {
        return false;
      }

      // Filter by status
      if (status != null && t.status?.toUpperCase() != status.toUpperCase()) {
        return false;
      }

      // Filter by date range
      if (fromDate != null || toDate != null) {
        if (t.time == null) return false;

        try {
          final transactionDate = DateTime.parse(t.time!);

          if (fromDate != null) {
            final from = DateTime.parse(fromDate);
            if (transactionDate.isBefore(from)) return false;
          }

          if (toDate != null) {
            final to = DateTime.parse(toDate);
            if (transactionDate.isAfter(to)) return false;
          }
        } catch (e) {
          // If date parsing fails, exclude the transaction
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Enriches a Transaction with bank name
  Future<Map<String, dynamic>> _enrichTransactionWithBankInfo(
      Transaction transaction) async {
    final bank = transaction.bankId != null
        ? await _getBankById(transaction.bankId!)
        : null;

    return {
      'amount': transaction.amount,
      'reference': transaction.reference,
      'creditor': transaction.creditor,
      'receiver': transaction.receiver,
      'time': transaction.time,
      'status': transaction.status,
      'currentBalance': transaction.currentBalance,
      'bankId': transaction.bankId,
      'bankName': bank?.shortName ?? 'Unknown',
      'bankFullName': bank?.name ?? 'Unknown Bank',
      'bankImage': bank?.image ?? '',
      'type': transaction.type,
      'transactionLink': transaction.transactionLink,
      'accountNumber': transaction.accountNumber,
      'categoryId': transaction.categoryId,
    };
  }

  /// Finds a bank by ID from the database
  Future<Bank?> _getBankById(int bankId) async {
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
