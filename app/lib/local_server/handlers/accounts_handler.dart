import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/bank_config_service.dart';

/// Handler for account-related API endpoints
class AccountsHandler {
  final AccountRepository _accountRepo = AccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  /// Returns a configured router with all account routes
  Router get router {
    final router = Router();

    // GET /api/accounts - List all accounts with bank info
    router.get('/', _getAccounts);

    // GET /api/accounts/<bankId>/<accountNumber> - Get single account
    router.get('/<bankId>/<accountNumber>', _getAccountByIdAndNumber);

    return router;
  }

  /// GET /api/accounts
  /// Returns all accounts enriched with bank information
  Future<Response> _getAccounts(Request request) async {
    try {
      final accounts = await _accountRepo.getAccounts();

      final enrichedAccounts = await Future.wait(
        accounts.map((account) => _enrichAccountWithBankInfo(account)),
      );

      return Response.ok(
        jsonEncode(enrichedAccounts),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch accounts: $e', 500);
    }
  }

  /// GET /api/accounts/:bankId/:accountNumber
  /// Returns a single account by bank ID and account number
  Future<Response> _getAccountByIdAndNumber(
    Request request,
    String bankId,
    String accountNumber,
  ) async {
    try {
      final parsedBankId = int.tryParse(bankId);
      if (parsedBankId == null) {
        return _errorResponse('Invalid bank ID', 400);
      }

      final accounts = await _accountRepo.getAccounts();

      final account = accounts.cast<Account?>().firstWhere(
            (a) => a!.bank == parsedBankId && a.accountNumber == accountNumber,
            orElse: () => null,
          );

      if (account == null) {
        return _errorResponse('Account not found', 404);
      }

      final enrichedAccount = await _enrichAccountWithBankInfo(account);

      return Response.ok(
        jsonEncode(enrichedAccount),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch account: $e', 500);
    }
  }

  /// Enriches an Account with bank name, short name, and image
  Future<Map<String, dynamic>> _enrichAccountWithBankInfo(
      Account account) async {
    final bank = await _getBankById(account.bank);

    return {
      'accountNumber': account.accountNumber,
      'bank': account.bank,
      'bankName': bank?.name ?? 'Unknown Bank',
      'bankShortName': bank?.shortName ?? 'N/A',
      'bankImage': bank?.image ?? '',
      'balance': account.balance,
      'accountHolderName': account.accountHolderName,
      'settledBalance': account.settledBalance,
      'pendingCredit': account.pendingCredit,
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
