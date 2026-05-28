import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/constants/cash_constants.dart';

class BankConfigService {
  static const String _banksAssetPath = 'assets/banks.json';
  static const int _mpesaBankId = 8;
  static const int _apolloBankId = 36;
  static const int _cbeBirrBankId = 37;
  static const Set<int> _retiredBankIds = {35, 38};
  static const Map<int, String> _canonicalLocalBankImages = {
    _apolloBankId: 'assets/images/apollo.png',
    _cbeBirrBankId: 'assets/images/cbe_birr.png',
  };
  List<Bank>? _assetBanksCache;

  List<Bank> _filterCashBanks(List<Bank> banks) {
    return banks
        .where((bank) =>
            bank.id != CashConstants.bankId &&
            !_retiredBankIds.contains(bank.id))
        .toList();
  }

  bool _isMpesaBank(Bank bank) {
    final token =
        '${bank.name} ${bank.shortName} ${bank.codes.join(' ')} ${bank.image}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return token.contains('mpesa');
  }

  Bank _canonicalMpesaBank() {
    return Bank(
      id: _mpesaBankId,
      name: 'M Pesa',
      shortName: 'MPESA',
      codes: const ['MPESA'],
      image: 'assets/images/mpesa.png',
      maskPattern: 0,
      uniformMasking: false,
      simBased: true,
      colors: const ['#00a859', '#ffffff'],
    );
  }

  Bank _withCanonicalLocalBankImage(Bank bank) {
    final canonicalImage = _canonicalLocalBankImages[bank.id];
    if (canonicalImage == null || bank.image == canonicalImage) return bank;
    return Bank(
      id: bank.id,
      name: bank.name,
      shortName: bank.shortName,
      codes: bank.codes,
      image: canonicalImage,
      maskPattern: bank.maskPattern,
      uniformMasking: bank.uniformMasking,
      simBased: bank.simBased,
      colors: bank.colors,
    );
  }

  List<Bank> _applyCanonicalLocalBankImages(List<Bank> banks) {
    return banks.map(_withCanonicalLocalBankImage).toList(growable: false);
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _mergeStringLists(List<String> primary, List<String> fallback) {
    final merged = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (merged.any((item) => item.toLowerCase() == trimmed.toLowerCase())) {
        return;
      }
      merged.add(trimmed);
    }

    for (final value in primary) {
      add(value);
    }
    for (final value in fallback) {
      add(value);
    }
    return merged;
  }

  Bank _mergeBankDefinition(Bank existing, Bank asset) {
    return Bank(
      id: existing.id,
      name: existing.name.trim().isNotEmpty ? existing.name : asset.name,
      shortName: existing.shortName.trim().isNotEmpty
          ? existing.shortName
          : asset.shortName,
      codes: _mergeStringLists(existing.codes, asset.codes),
      image: existing.image.trim().isNotEmpty ? existing.image : asset.image,
      maskPattern: existing.maskPattern ?? asset.maskPattern,
      uniformMasking: existing.uniformMasking ?? asset.uniformMasking,
      simBased: existing.simBased ?? asset.simBased,
      colors: existing.colors ?? asset.colors,
    );
  }

  List<Bank> _mergeAssetBankDefinitions(
    List<Bank> banks,
    List<Bank> assetBanks,
  ) {
    final mergedById = <int, Bank>{for (final bank in banks) bank.id: bank};
    for (final assetBank in assetBanks) {
      final existing = mergedById[assetBank.id];
      mergedById[assetBank.id] = existing == null
          ? assetBank
          : _mergeBankDefinition(existing, assetBank);
    }
    return mergedById.values.toList(growable: false);
  }

  bool _sameBanks(Bank a, Bank b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.shortName == b.shortName &&
        _sameStringList(a.codes, b.codes) &&
        a.image == b.image &&
        a.maskPattern == b.maskPattern &&
        a.uniformMasking == b.uniformMasking &&
        a.simBased == b.simBased &&
        _sameStringList(a.colors ?? const [], b.colors ?? const []);
  }

  bool _sameBankLists(List<Bank> a, List<Bank> b) {
    if (a.length != b.length) return false;
    final banksByIdA = <int, Bank>{for (final bank in a) bank.id: bank};
    final banksByIdB = <int, Bank>{for (final bank in b) bank.id: bank};
    if (banksByIdA.length != banksByIdB.length) return false;
    for (final entry in banksByIdA.entries) {
      final other = banksByIdB[entry.key];
      if (other == null || !_sameBanks(entry.value, other)) return false;
    }
    return true;
  }

  List<Bank> _normalizeKnownBankAliases(List<Bank> banks) {
    if (banks.isEmpty) return banks;
    final normalized = List<Bank>.from(banks);
    final mpesaByIdIndex =
        normalized.indexWhere((bank) => bank.id == _mpesaBankId);
    if (mpesaByIdIndex == -1) {
      return _applyCanonicalLocalBankImages(normalized);
    }

    final bankAtMpesaId = normalized[mpesaByIdIndex];
    if (_isMpesaBank(bankAtMpesaId)) {
      return _applyCanonicalLocalBankImages(normalized);
    }

    final mpesaAliasIndex = normalized.indexWhere(
      (bank) => bank.id != _mpesaBankId && _isMpesaBank(bank),
    );
    final source = mpesaAliasIndex >= 0
        ? normalized[mpesaAliasIndex]
        : _canonicalMpesaBank();

    normalized[mpesaByIdIndex] = Bank(
      id: _mpesaBankId,
      name: source.name,
      shortName: source.shortName,
      codes: source.codes,
      image: source.image,
      maskPattern: source.maskPattern,
      uniformMasking: source.uniformMasking,
      simBased: source.simBased,
      colors: source.colors,
    );

    return _applyCanonicalLocalBankImages(normalized);
  }

  Future<List<Bank>> _loadAssetBanks() async {
    if (_assetBanksCache != null) {
      return _assetBanksCache!;
    }

    try {
      final body = await rootBundle.loadString(_banksAssetPath);
      final banks = _normalizeKnownBankAliases(
          _filterCashBanks(_parseBanksFromJson(body)));
      _assetBanksCache = banks;
      print("debug: Loaded ${banks.length} banks from assets");
      return banks;
    } catch (e) {
      print("debug: Error loading asset banks: $e");
      return [];
    }
  }

  Future<List<Bank>> getBanks({bool allowRemoteFetch = true}) async {
    final db = await DatabaseHelper.instance.database;

    // First, try to load from database
    final List<Map<String, dynamic>> maps = await db.query('banks');
    if (maps.isNotEmpty) {
      try {
        final parsedBanks = maps.map((map) {
          return Bank.fromJson({
            'id': map['id'],
            'name': map['name'],
            'shortName': map['shortName'],
            'codes': jsonDecode(map['codes'] as String),
            'image': map['image'],
            'maskPattern': map['maskPattern'],
            'uniformMasking': map['uniformMasking'] == null
                ? null
                : (map['uniformMasking'] == 1),
            'simBased': map['simBased'] == null ? null : (map['simBased'] == 1),
            'colors': map['colors'] != null
                ? List<String>.from(jsonDecode(map['colors'] as String))
                : null,
          });
        }).toList();
        final filteredBanks = _filterCashBanks(parsedBanks);
        final normalizedBanks = _normalizeKnownBankAliases(filteredBanks);
        final assetBanks = await _loadAssetBanks();
        final banks = _normalizeKnownBankAliases(
          _mergeAssetBankDefinitions(normalizedBanks, assetBanks),
        );
        if (!_sameBankLists(filteredBanks, banks) ||
            filteredBanks.length != parsedBanks.length) {
          await saveBanks(banks);
        }
        print("debug: Loaded ${banks.length} banks from database");
        return banks;
      } catch (e) {
        print("debug: Error parsing stored banks: $e");
        // Fall through to fetch from remote
      }
    }

    if (allowRemoteFetch) {
      // If not in database, try to fetch from remote (only if internet available)
      final hasInternet = await _hasInternetConnection();
      if (hasInternet) {
        try {
          final banks = await _fetchRemoteBanks();
          if (banks.isNotEmpty) {
            await saveBanks(banks);
            return banks;
          }
        } catch (e) {
          print("debug: Error fetching remote banks: $e");
        }
      } else {
        print("debug: No internet connection, cannot fetch remote banks");
      }
    }

    // Fallback to asset list if no banks found
    print("debug: No banks available, using assets");
    final assetBanks = await _loadAssetBanks();
    if (assetBanks.isNotEmpty) {
      await saveBanks(assetBanks);
    }
    return assetBanks;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      // Check if we have any connection (mobile, wifi, ethernet, etc.)
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }
      // Additional check: try to reach a known server
      try {
        final response = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));
        return response.statusCode == 200;
      } catch (e) {
        return false;
      }
    } catch (e) {
      print("debug: Error checking connectivity: $e");
      return false;
    }
  }

  List<Bank> _parseBanksFromJson(String body) {
    String normalizedBody = body.trim();
    if (normalizedBody.startsWith('export') ||
        normalizedBody.startsWith('const') ||
        normalizedBody.startsWith('var') ||
        normalizedBody.startsWith('let')) {
      final jsonMatch =
          RegExp(r'(\[[\s\S]*\])|(\{[\s\S]*\})').firstMatch(normalizedBody);
      if (jsonMatch != null) {
        normalizedBody = jsonMatch.group(0)!;
      }
    }

    final dynamic jsonData = jsonDecode(normalizedBody);
    if (jsonData is List) {
      return jsonData
          .map((item) => Bank.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    if (jsonData is Map && jsonData.containsKey('banks')) {
      final banksList = jsonData['banks'] as List;
      return banksList
          .map((item) => Bank.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<Bank>> _fetchRemoteBanks() async {
    const String url = "https://sms-parsing-visualizer.vercel.app/banks.json";

    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final banks = _normalizeKnownBankAliases(
          _filterCashBanks(_parseBanksFromJson(response.body)),
        );
        print("debug: Fetched ${banks.length} banks from remote");
        return banks;
      } else {
        print("debug: Remote fetch failed with status ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("debug: Exception fetching remote banks: $e");
      return [];
    }
  }

  Future<void> saveBanks(List<Bank> banks) async {
    final db = await DatabaseHelper.instance.database;

    // Clear existing banks and insert new ones
    await db.delete('banks');

    final batch = db.batch();
    for (var bank in banks) {
      batch.insert(
          'banks',
          {
            'id': bank.id,
            'name': bank.name,
            'shortName': bank.shortName,
            'codes': jsonEncode(bank.codes),
            'image': bank.image,
            'maskPattern': bank.maskPattern,
            'uniformMasking': bank.uniformMasking == null
                ? null
                : (bank.uniformMasking! ? 1 : 0),
            'simBased': bank.simBased == null ? null : (bank.simBased! ? 1 : 0),
            'colors': bank.colors != null ? jsonEncode(bank.colors) : null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    print("debug: Saved ${banks.length} banks to database");
  }

  // Method to force fetch remote config (background sync)
  Future<void> syncRemoteConfig({bool showError = false}) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      print("debug: No internet connection, skipping remote sync");
      return;
    }

    try {
      final banks = await _fetchRemoteBanks();
      if (banks.isNotEmpty) {
        await saveBanks(banks);
        print("debug: Successfully synced remote banks config");
      } else {
        print("debug: Remote sync returned empty banks");
      }
    } catch (e) {
      print("debug: Error syncing remote banks config: $e");
      if (showError) {
        rethrow;
      }
    }
  }

  // Initialize banks on app launch
  // Returns true if internet is needed but not available
  // Only fetches if banks don't exist (no background sync)
  Future<bool> initializeBanks() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('banks');

    // If banks exist, return (no sync - sync only happens on explicit refresh)
    if (maps.isNotEmpty) {
      return false; // No internet needed, we have cached banks
    }

    // No banks stored, need to fetch
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      final assetBanks = await _loadAssetBanks();
      if (assetBanks.isNotEmpty) {
        await saveBanks(assetBanks);
      }
      return false;
    }

    // Fetch and save banks
    try {
      final banks = await _fetchRemoteBanks();
      if (banks.isNotEmpty) {
        await saveBanks(banks);
        return false; // Success
      } else {
        final assetBanks = await _loadAssetBanks();
        if (assetBanks.isNotEmpty) {
          await saveBanks(assetBanks);
        }
        return false;
      }
    } catch (e) {
      print("debug: Error initializing banks: $e");
      final assetBanks = await _loadAssetBanks();
      if (assetBanks.isNotEmpty) {
        await saveBanks(assetBanks);
      }
      return false;
    }
  }
}
