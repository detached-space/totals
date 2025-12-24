import 'dart:convert';
import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/services/bank_config_service.dart';

/// Represents a bank detected from SMS messages
class DetectedBank {
  final Bank bank;
  final String senderAddress;
  final int messageCount;
  final DateTime? lastMessageDate;

  DetectedBank({
    required this.bank,
    required this.senderAddress,
    required this.messageCount,
    this.lastMessageDate,
  });

  /// Convert to JSON for caching
  Map<String, dynamic> toJson() {
    return {
      'bankId': bank.id,
      'senderAddress': senderAddress,
      'messageCount': messageCount,
      'lastMessageDate': lastMessageDate?.toIso8601String(),
    };
  }

  /// Create from JSON cache
  static Future<DetectedBank?> fromJson(
      Map<String, dynamic> json, List<Bank> banks) async {
    try {
      final bankId = json['bankId'] as int;
      final bank = banks.firstWhere(
        (b) => b.id == bankId,
        orElse: () => throw Exception('Bank not found'),
      );

      return DetectedBank(
        bank: bank,
        senderAddress: json['senderAddress'] as String,
        messageCount: json['messageCount'] as int,
        lastMessageDate: json['lastMessageDate'] != null
            ? DateTime.parse(json['lastMessageDate'] as String)
            : null,
      );
    } catch (e) {
      print("debug: Error parsing DetectedBank from JSON: $e");
      return null;
    }
  }
}

/// Service to detect banks from user's SMS inbox
class BankDetectionService {
  static const String _cacheKey = 'detected_banks_cache';
  static const String _cacheTimestampKey = 'detected_banks_cache_timestamp';

  final Telephony _telephony = Telephony.instance;
  final AccountRepository _accountRepo = AccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank>? _cachedBanks;

  /// Scans the SMS inbox and returns banks that the user has messages from
  /// but hasn't registered an account for yet.
  /// Uses cached results for faster loading. Scans SMS only when cache is empty
  /// or forceRefresh is true.
  Future<List<DetectedBank>> detectUnregisteredBanks({
    bool forceRefresh = false,
  }) async {
    try {
      // Get registered accounts first (needed for filtering)
      List<Account> registeredAccounts = await _accountRepo.getAccounts();
      Set<int> registeredBankIds =
          registeredAccounts.map((a) => a.bank).toSet();

      // Try to get cached data first (unless force refresh)
      if (!forceRefresh) {
        final cachedBanks = await _getCachedBanks();
        if (cachedBanks != null) {
          // Filter out already registered banks from cache
          final filtered = cachedBanks
              .where((db) => !registeredBankIds.contains(db.bank.id))
              .toList();

          return filtered;
        }
      }

      // No cache or force refresh - scan SMS
      // Force reload banks to ensure we have latest synced banks
      return await _scanAndCacheBanks(registeredBankIds, forceReloadBanks: forceRefresh);
    } catch (e) {
      print("debug: Error detecting banks from SMS: $e");
      // Try to return cached data on error
      final cachedBanks = await _getCachedBanks();
      if (cachedBanks != null) {
        List<Account> registeredAccounts = await _accountRepo.getAccounts();
        Set<int> registeredBankIds =
            registeredAccounts.map((a) => a.bank).toSet();
        return cachedBanks
            .where((db) => !registeredBankIds.contains(db.bank.id))
            .toList();
      }
      return [];
    }
  }

  /// Get cached detected banks if available
  Future<List<DetectedBank>?> _getCachedBanks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) return null;

      final List<dynamic> decoded = json.decode(cacheJson);

      // Fetch banks from database for deserialization
      if (_cachedBanks == null) {
        _cachedBanks = await _bankConfigService.getBanks();
      }

      // Ensure we have banks before deserializing
      if (_cachedBanks == null || _cachedBanks!.isEmpty) {
        print("debug: No banks available for deserialization, clearing cache");
        await clearCache();
        return null;
      }

      try {
        final List<DetectedBank> banks = (await Future.wait(
          decoded.map((item) => DetectedBank.fromJson(
              item as Map<String, dynamic>, _cachedBanks!)),
        ))
            .where((bank) => bank != null)
            .cast<DetectedBank>()
            .toList();

        print("debug: Loaded ${banks.length} banks from cache");
        return banks;
      } catch (e) {
        // If there's a type mismatch (e.g., old Bank type in cache), clear cache
        if (e.toString().contains('is not a subtype') ||
            e.toString().contains('Bank')) {
          print("debug: Type mismatch detected in cache, clearing: $e");
          await clearCache();
        }
        return null;
      }
    } catch (e) {
      print("debug: Error reading bank cache: $e");
      // Clear cache on any error to prevent stale data
      try {
        await clearCache();
      } catch (clearError) {
        print("debug: Error clearing cache: $clearError");
      }
      return null;
    }
  }

  /// Save detected banks to cache
  Future<void> _saveBanksToCache(List<DetectedBank> banks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = banks.map((b) => b.toJson()).toList();
      await prefs.setString(_cacheKey, json.encode(jsonList));
      await prefs.setString(
          _cacheTimestampKey, DateTime.now().toIso8601String());
      print("debug: Saved ${banks.length} banks to cache");
    } catch (e) {
      print("debug: Error saving bank cache: $e");
    }
  }

  /// Clear the cache (call when accounts change)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      // Also clear the in-memory bank cache to force reload
      _cachedBanks = null;
      print("debug: Cleared bank detection cache");
    } catch (e) {
      print("debug: Error clearing bank cache: $e");
    }
  }

  /// Scan SMS and cache results
  Future<List<DetectedBank>> _scanAndCacheBanks(
      Set<int> registeredBankIds, {bool forceReloadBanks = false}) async {
    // Fetch banks from database (reload if forced or not cached)
    if (_cachedBanks == null || forceReloadBanks) {
      _cachedBanks = await _bankConfigService.getBanks();
    }

    // Get SMS messages from inbox
    List<SmsMessage> messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    // Track ALL detected banks (for caching)
    Map<int, DetectedBankData> allDetectedBanksMap = {};

    for (var message in messages) {
      String? address = message.address;
      if (address == null) continue;

      // Check if this message is from a known bank
      Bank? matchedBank = _getMatchingBank(address);
      if (matchedBank == null) continue;

      // Update or create detection data
      if (allDetectedBanksMap.containsKey(matchedBank.id)) {
        allDetectedBanksMap[matchedBank.id]!.messageCount++;
      } else {
        DateTime? messageDate;
        if (message.date != null) {
          messageDate = DateTime.fromMillisecondsSinceEpoch(message.date!);
        }
        allDetectedBanksMap[matchedBank.id] = DetectedBankData(
          bank: matchedBank,
          senderAddress: address,
          messageCount: 1,
          lastMessageDate: messageDate,
        );
      }
    }

    // Convert to list of all detected banks
    List<DetectedBank> allBanks = allDetectedBanksMap.values
        .map((data) => DetectedBank(
              bank: data.bank,
              senderAddress: data.senderAddress,
              messageCount: data.messageCount,
              lastMessageDate: data.lastMessageDate,
            ))
        .toList();

    // Sort by message count
    allBanks.sort((a, b) => b.messageCount.compareTo(a.messageCount));

    // Cache ALL detected banks (not filtered)
    await _saveBanksToCache(allBanks);

    // Return only unregistered banks
    List<DetectedBank> unregisteredBanks = allBanks
        .where((db) => !registeredBankIds.contains(db.bank.id))
        .toList();

    return unregisteredBanks;
  }

  /// Checks if the address matches any known bank and returns it
  Bank? _getMatchingBank(String address) {
    if (_cachedBanks == null) {
      // Should not happen if called after _scanAndCacheBanks or detectAllBanks
      // but handle gracefully
      return null;
    }

    for (var bank in _cachedBanks!) {
      for (var code in bank.codes) {
        if (address.contains(code)) {
          return bank;
        }
      }
    }
    return null;
  }

  /// Gets all banks detected from SMS (including those already registered)
  Future<List<DetectedBank>> detectAllBanks({bool forceRefresh = false}) async {
    try {
      // Try cache first
      if (!forceRefresh) {
        final cachedBanks = await _getCachedBanks();
        if (cachedBanks != null) {
          return cachedBanks;
        }
      }

      // Fetch banks from database (with caching)
      if (_cachedBanks == null) {
        _cachedBanks = await _bankConfigService.getBanks();
      }

      // Scan all banks
      List<SmsMessage> messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      Map<int, DetectedBankData> detectedBanksMap = {};

      for (var message in messages) {
        String? address = message.address;
        if (address == null) continue;

        Bank? matchedBank = _getMatchingBank(address);
        if (matchedBank == null) continue;

        if (detectedBanksMap.containsKey(matchedBank.id)) {
          detectedBanksMap[matchedBank.id]!.messageCount++;
        } else {
          DateTime? messageDate;
          if (message.date != null) {
            messageDate = DateTime.fromMillisecondsSinceEpoch(message.date!);
          }
          detectedBanksMap[matchedBank.id] = DetectedBankData(
            bank: matchedBank,
            senderAddress: address,
            messageCount: 1,
            lastMessageDate: messageDate,
          );
        }
      }

      List<DetectedBank> result = detectedBanksMap.values
          .map((data) => DetectedBank(
                bank: data.bank,
                senderAddress: data.senderAddress,
                messageCount: data.messageCount,
                lastMessageDate: data.lastMessageDate,
              ))
          .toList();

      result.sort((a, b) => b.messageCount.compareTo(a.messageCount));

      // Cache results
      await _saveBanksToCache(result);

      return result;
    } catch (e) {
      print("debug: Error detecting all banks from SMS: $e");
      // Try cache on error
      final cachedBanks = await _getCachedBanks();
      return cachedBanks ?? [];
    }
  }
}

/// Internal helper class to track detection data while scanning
class DetectedBankData {
  final Bank bank;
  final String senderAddress;
  int messageCount;
  final DateTime? lastMessageDate;

  DetectedBankData({
    required this.bank,
    required this.senderAddress,
    required this.messageCount,
    this.lastMessageDate,
  });
}
