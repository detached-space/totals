import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/sms_pattern.dart';

class SmsConfigService {
  static const String _patternsAssetPath = 'assets/sms_patterns.json';
  static Future<void>? _remoteConfigSyncInFlight;
  List<SmsPattern>? _assetPatternsCache;

  Future<List<SmsPattern>> _loadAssetPatterns() async {
    if (_assetPatternsCache != null) {
      return _assetPatternsCache!;
    }

    try {
      final body = await rootBundle.loadString(_patternsAssetPath);
      final patterns = _parsePatternsFromJson(body);
      _assetPatternsCache = patterns;
      print("debug: Loaded ${patterns.length} patterns from assets");
      return patterns;
    } catch (e) {
      print("debug: Error loading asset patterns: $e");
      return [];
    }
  }

  void debugSms(String smsText) {
    // Show invisible characters
    // print("Raw SMS (escaped): ${jsonEncode(smsText)}");

    // // Optionally show code units for each character
    // print("Code units: ${smsText.codeUnits}");
  }

  String cleanSmsText(String text) {
    try {
      // String jsonString = jsonEncode(text);
      // String cleaned = jsonDecode(jsonString);
      // cleaned = cleaned.replaceAll('\r', ' ');
      // cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      // cleaned = cleaned.replaceAll(RegExp(r'\.\s*([A-Z])'), ' \$1');
      return text.trim();
    } catch (e) {
      print("debug: JSON sanitization failed: $e");
      return text;
    }
  }

  Future<List<SmsPattern>> getPatterns({bool allowRemoteFetch = true}) async {
    final db = await DatabaseHelper.instance.database;

    // First, try to load from database
    final List<Map<String, dynamic>> maps = await db.query('sms_patterns');
    if (maps.isNotEmpty) {
      try {
        final patterns = maps.map((map) {
          return SmsPattern.fromJson({
            'bankId': map['bankId'],
            'senderId': map['senderId'],
            'regex': map['regex'],
            'type': map['type'],
            'description': map['description'],
            'refRequired':
                map['refRequired'] == null ? null : (map['refRequired'] == 1),
            'hasAccount':
                map['hasAccount'] == null ? null : (map['hasAccount'] == 1),
          });
        }).toList();
        print("debug: Loaded ${patterns.length} patterns from database");
        return patterns;
      } catch (e) {
        print("debug: Error parsing stored patterns: $e");
        // Fall through to fetch from remote
      }
    }

    if (allowRemoteFetch) {
      // If not in database, try to fetch from remote (only if internet available)
      final hasInternet = await _hasInternetConnection();
      if (hasInternet) {
        try {
          final patterns = await _fetchRemotePatterns();
          if (patterns.isNotEmpty) {
            await savePatterns(patterns);
            return patterns;
          }
        } catch (e) {
          print("debug: Error fetching remote patterns: $e");
        }
      } else {
        print("debug: No internet connection, cannot fetch remote patterns");
      }
    }

    // Fallback to asset patterns
    print("debug: Using asset patterns as fallback");
    final assetPatterns = await _loadAssetPatterns();
    if (assetPatterns.isNotEmpty) {
      await savePatterns(assetPatterns);
    }
    return assetPatterns;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      // Check if we have any connection (mobile, wifi, ethernet, etc.)
      if (connectivityResults.isEmpty ||
          connectivityResults.every(
            (result) => result == ConnectivityResult.none,
          )) {
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

  List<SmsPattern> _parsePatternsFromJson(String body) {
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
          .map((item) => SmsPattern.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    if (jsonData is Map && jsonData.containsKey('patterns')) {
      final patternsList = jsonData['patterns'] as List;
      return patternsList
          .map((item) => SmsPattern.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<List<SmsPattern>> _fetchRemotePatterns() async {
    const String url =
        "https://sms-parsing-visualizer.vercel.app/sms_patterns.json";

    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final patterns = _parsePatternsFromJson(response.body);
        print("debug: Fetched ${patterns.length} patterns from remote");
        return patterns;
      } else {
        print("debug: Remote fetch failed with status ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("debug: Exception fetching remote patterns: $e");
      return [];
    }
  }

  Future<void> savePatterns(List<SmsPattern> patterns) async {
    final db = await DatabaseHelper.instance.database;

    // Clear existing patterns and insert new ones
    await db.delete('sms_patterns');

    final batch = db.batch();
    for (var pattern in patterns) {
      batch.insert('sms_patterns', {
        'bankId': pattern.bankId,
        'senderId': pattern.senderId,
        'regex': pattern.regex,
        'type': pattern.type,
        'description': pattern.description,
        'refRequired':
            pattern.refRequired == null ? null : (pattern.refRequired! ? 1 : 0),
        'hasAccount':
            pattern.hasAccount == null ? null : (pattern.hasAccount! ? 1 : 0),
      });
    }
    await batch.commit(noResult: true);
    print("debug: Saved ${patterns.length} patterns to database");
  }

  // Method to force fetch remote config (background sync)
  Future<void> syncRemoteConfig({bool showError = false}) {
    final inFlight = _remoteConfigSyncInFlight;
    if (inFlight != null) return inFlight;

    final sync = _syncRemoteConfig(showError: showError);
    _remoteConfigSyncInFlight = sync;
    return sync.whenComplete(() {
      if (identical(_remoteConfigSyncInFlight, sync)) {
        _remoteConfigSyncInFlight = null;
      }
    });
  }

  Future<void> _syncRemoteConfig({bool showError = false}) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      print("debug: No internet connection, skipping remote sync");
      return;
    }

    try {
      final patterns = await _fetchRemotePatterns();
      if (patterns.isNotEmpty) {
        await savePatterns(patterns);
        print("debug: Successfully synced remote config");
      } else {
        print("debug: Remote sync returned empty patterns");
      }
    } catch (e) {
      print("debug: Error syncing remote config: $e");
      if (showError) {
        rethrow;
      }
    }
  }

  Future<int> refreshPatternsFromInternet() async {
    print("debug: Manual SMS pattern refresh started");
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      print("debug: Manual SMS pattern refresh failed - no internet");
      throw Exception('No internet connection. Connect and try again.');
    }

    final patterns = await _fetchRemotePatterns();
    if (patterns.isEmpty) {
      print(
          "debug: Manual SMS pattern refresh failed - remote returned 0 patterns");
      throw Exception('Could not download SMS patterns right now.');
    }

    await savePatterns(patterns);
    print(
        "debug: Manual SMS pattern refresh completed with ${patterns.length} patterns");
    return patterns.length;
  }

  // Initialize patterns on app launch
  // Returns true if internet is needed but not available
  // Only fetches if patterns don't exist (no background sync)
  Future<bool> initializePatterns() async {
    final db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('sms_patterns');

    // If patterns exist, return (no sync - sync only happens on explicit refresh)
    if (maps.isNotEmpty) {
      return false; // No internet needed, we have cached patterns
    }

    // No patterns stored, need to fetch
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      return true; // Internet needed but not available
    }

    // Fetch and save patterns
    try {
      final patterns = await _fetchRemotePatterns();
      if (patterns.isNotEmpty) {
        await savePatterns(patterns);
        return false; // Success
      } else {
        // Fallback to asset patterns
        final assetPatterns = await _loadAssetPatterns();
        if (assetPatterns.isNotEmpty) {
          await savePatterns(assetPatterns);
        }
        return false;
      }
    } catch (e) {
      print("debug: Error initializing patterns: $e");
      // Fallback to asset patterns
      final assetPatterns = await _loadAssetPatterns();
      if (assetPatterns.isNotEmpty) {
        await savePatterns(assetPatterns);
      }
      return false;
    }
  }
}
