import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/bank.dart';

class BankConfigService {
  static final List<Bank> _defaultBanks = [
    Bank(
      id: 1,
      name: "Commercial Bank Of Ethiopia",
      shortName: "CBE",
      codes: ["CBE"],
      image: "assets/images/cbe.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
    Bank(
      id: 2,
      name: "Awash Bank",
      shortName: "Awash",
      codes: ["Awash", "Awash Bank", "AwashBank"],
      image: "assets/images/awash.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
    Bank(
      id: 3,
      name: "Bank Of Abyssinia",
      shortName: "BOA",
      codes: ["BOA"],
      image: "assets/images/boa.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
    Bank(
      id: 4,
      name: "Dashen Bank",
      shortName: "Dashen",
      codes: ["Dashen", "DashenBank"],
      image: "assets/images/dashen.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
    Bank(
      id: 5,
      name: "Zemen Bank",
      shortName: "Zemen",
      codes: ["Zemen"],
      image: "assets/images/zemen.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
    Bank(
      id: 6,
      name: "Telebirr",
      shortName: "Telebirr",
      codes: ["telebirr", "Telebirr", "127"],
      image: "assets/images/telebirr.png",
      uniformMasking: false,
    ),
    Bank(
      id: 7,
      name: "Nib Bank",
      shortName: "NIB",
      codes: ["NIB"],
      image: "assets/images/nib.png",
      maskPattern: 4,
      uniformMasking: true,
    ),
  ];

  Future<List<Bank>> getBanks() async {
    final db = await DatabaseHelper.instance.database;

    // First, try to load from database
    final List<Map<String, dynamic>> maps = await db.query('banks');
    if (maps.isNotEmpty) {
      try {
        final banks = maps.map((map) {
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
        print("debug: Loaded ${banks.length} banks from database");
        return banks;
      } catch (e) {
        print("debug: Error parsing stored banks: $e");
        // Fall through to fetch from remote
      }
    }

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

    // Fallback to default list if no banks found
    print("debug: No banks available, using defaults");
    await saveBanks(_defaultBanks);
    return _defaultBanks;
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

  Future<List<Bank>> _fetchRemoteBanks() async {
    const String url = "https://sms-parsing-visualizer.vercel.app/banks.json";

    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        String body = response.body;

        // Handle JavaScript file that might export JSON
        // Remove any JavaScript wrapper if present
        body = body.trim();
        if (body.startsWith('export') ||
            body.startsWith('const') ||
            body.startsWith('var') ||
            body.startsWith('let')) {
          // Extract JSON from JS file
          final jsonMatch =
              RegExp(r'(\[[\s\S]*\])|(\{[\s\S]*\})').firstMatch(body);
          if (jsonMatch != null) {
            body = jsonMatch.group(0)!;
          }
        }

        // Parse JSON
        final dynamic jsonData = jsonDecode(body);
        List<Bank> banks = [];

        if (jsonData is List) {
          banks = jsonData
              .map((item) => Bank.fromJson(item as Map<String, dynamic>))
              .toList();
        } else if (jsonData is Map && jsonData.containsKey('banks')) {
          // Handle case where JSON has a 'banks' key
          final banksList = jsonData['banks'] as List;
          banks = banksList
              .map((item) => Bank.fromJson(item as Map<String, dynamic>))
              .toList();
        }

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
      return true; // Internet needed but not available
    }

    // Fetch and save banks
    try {
      final banks = await _fetchRemoteBanks();
      if (banks.isNotEmpty) {
        await saveBanks(banks);
        return false; // Success
      } else {
        return false;
      }
    } catch (e) {
      print("debug: Error initializing banks: $e");
      return false;
    }
  }
}
