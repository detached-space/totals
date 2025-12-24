import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_config_service.dart';

/// Handler for bank-related API endpoints
class BanksHandler {
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  /// Returns a configured router with all bank routes
  Router get router {
    final router = Router();

    // GET /api/banks - List all supported banks
    router.get('/', _getBanks);

    // GET /api/banks/<id> - Get single bank by ID
    router.get('/<id>', _getBankById);

    return router;
  }

  /// GET /api/banks
  /// Returns all supported banks
  Future<Response> _getBanks(Request request) async {
    try {
      // Fetch banks from database (with caching)
      if (_cachedBanks == null) {
        _cachedBanks = await _bankConfigService.getBanks();
      }

      final banks = _cachedBanks!
          .map((bank) => {
                'id': bank.id,
                'name': bank.name,
                'shortName': bank.shortName,
                'codes': bank.codes,
                'image': bank.image,
                'maskPattern': bank.maskPattern,
                'uniformMasking': bank.uniformMasking,
                'simBased': bank.simBased,
              })
          .toList();

      return Response.ok(
        jsonEncode(banks),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse('Failed to fetch banks: $e', 500);
    }
  }

  /// GET /api/banks/:id
  /// Returns a single bank by ID
  Future<Response> _getBankById(Request request, String id) async {
    try {
      final parsedId = int.tryParse(id);
      if (parsedId == null) {
        return _errorResponse('Invalid bank ID', 400);
      }

      // Fetch banks from database (with caching)
      if (_cachedBanks == null) {
        _cachedBanks = await _bankConfigService.getBanks();
      }

      final bank = _cachedBanks!.firstWhere(
        (b) => b.id == parsedId,
        orElse: () => throw Exception('Bank not found'),
      );

      return Response.ok(
        jsonEncode({
          'id': bank.id,
          'name': bank.name,
          'shortName': bank.shortName,
          'codes': bank.codes,
          'image': bank.image,
          'maskPattern': bank.maskPattern,
          'uniformMasking': bank.uniformMasking,
          'simBased': bank.simBased,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      if (e.toString().contains('Bank not found')) {
        return _errorResponse('Bank not found', 404);
      }
      return _errorResponse('Failed to fetch bank: $e', 500);
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
