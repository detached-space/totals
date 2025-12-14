import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'network_utils.dart';
import 'handlers/accounts_handler.dart';
import 'handlers/transactions_handler.dart';
import 'handlers/summary_handler.dart';
import 'handlers/banks_handler.dart';

/// Log entry for request logging
class ServerLogEntry {
  final DateTime timestamp;
  final String method;
  final String path;
  final int statusCode;
  final String? message;
  final Duration? duration;

  ServerLogEntry({
    required this.timestamp,
    required this.method,
    required this.path,
    required this.statusCode,
    this.message,
    this.duration,
  });

  @override
  String toString() {
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final durationStr =
        duration != null ? ' (${duration!.inMilliseconds}ms)' : '';
    return '[$time] $method $path → $statusCode$durationStr';
  }
}

class ServerService {
  HttpServer? _server;
  String? _localIp;
  Directory? _webappDir;

  // Request logging
  final StreamController<ServerLogEntry> _logController =
      StreamController<ServerLogEntry>.broadcast();
  final List<ServerLogEntry> _logs = [];
  static const int _maxLogs = 100;

  /// Stream of log entries
  Stream<ServerLogEntry> get logStream => _logController.stream;

  /// Get all logs
  List<ServerLogEntry> get logs => List.unmodifiable(_logs);

  /// Add a log entry
  void _addLog(ServerLogEntry entry) {
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    _logController.add(entry);
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
  }

  // Shared random number state
  int _currentRandomNumber = 0;
  final Random _random = Random();
  final StreamController<int> _randomNumberController =
      StreamController<int>.broadcast();

  /// Stream of random number updates
  Stream<int> get randomNumberStream => _randomNumberController.stream;

  /// Current random number
  int get currentRandomNumber => _currentRandomNumber;

  /// Generate a new random number and notify listeners
  void generateRandomNumber() {
    _currentRandomNumber = _random.nextInt(10000);
    _randomNumberController.add(_currentRandomNumber);
  }

  bool get isRunning => _server != null;

  int get port => _server?.port ?? 0;

  String? get serverUrl {
    if (_server == null || _localIp == null) return null;
    return 'http://$_localIp:${_server!.port}';
  }

  String? get localUrl {
    if (_server == null) return null;
    return 'http://localhost:${_server!.port}';
  }

  Future<void> startServer({int port = 8080}) async {
    if (_server != null) {
      print('Server already running');
      return;
    }

    _localIp = await NetworkUtils.getLocalIpAddress();
    if (_localIp == null) {
      throw Exception('Could not determine local IP address');
    }

    // Extract assets to a temporary directory
    await _extractAssetsToTemp();

    if (_webappDir == null) {
      throw Exception('Failed to extract webapp assets');
    }

    final router = Router();

    // Mount API handlers
    final accountsHandler = AccountsHandler();
    final transactionsHandler = TransactionsHandler();
    final summaryHandler = SummaryHandler();
    final banksHandler = BanksHandler();

    router.mount('/api/accounts', accountsHandler.router.call);
    router.mount('/api/transactions', transactionsHandler.router.call);
    router.mount('/api/summary', summaryHandler.router.call);
    router.mount('/api/banks', banksHandler.router.call);

    // Health check endpoint
    router.get('/health', (Request request) {
      return Response.ok('OK');
    });

    // API endpoint example
    router.get('/api/info', (Request request) {
      return Response.ok(
        '{"status": "running", "version": "1.0.0"}',
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Get current random number endpoint
    router.get('/api/random', (Request request) {
      return Response.ok(
        jsonEncode({
          'number': _currentRandomNumber,
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Generate new random number endpoint
    router.post('/api/random/generate', (Request request) {
      generateRandomNumber();
      return Response.ok(
        jsonEncode({
          'number': _currentRandomNumber,
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Create static file handler using shelf_static
    final staticHandler = createStaticHandler(
      _webappDir!.path,
      defaultDocument: 'index.html',
      listDirectories: false,
    );

    // Cascade: try API routes first, then static files
    final cascade = Cascade()
        .add(router.call)
        .add(staticHandler)
        .add(_spaFallbackHandler); // SPA fallback for client-side routing

    final handler = const Pipeline()
        .addMiddleware(_loggingMiddleware())
        .addMiddleware(_corsMiddleware())
        .addHandler(cascade.handler);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('Server running at $serverUrl');
    print('Serving files from: ${_webappDir!.path}');
  }

  /// SPA fallback handler - serves index.html for unmatched routes
  Future<Response> _spaFallbackHandler(Request request) async {
    final indexFile = File('${_webappDir!.path}/index.html');
    if (await indexFile.exists()) {
      final content = await indexFile.readAsBytes();
      return Response.ok(
        content,
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }
    return Response.notFound('Not Found');
  }

  /// Extract Flutter assets to a temporary directory for shelf_static to serve
  Future<void> _extractAssetsToTemp() async {
    final tempDir = await getTemporaryDirectory();
    _webappDir = Directory('${tempDir.path}/flutter_server_webapp');

    // Clean up existing directory if it exists
    if (await _webappDir!.exists()) {
      await _webappDir!.delete(recursive: true);
    }
    await _webappDir!.create(recursive: true);

    // List of known asset files to extract
    // You may need to update this list based on your webapp structure
    final assetFiles = await _getAssetManifest();

    for (final assetPath in assetFiles) {
      if (assetPath.startsWith('assets/webapp/')) {
        await _extractAsset(assetPath);
      }
    }
  }

  /// Get list of assets from the asset manifest
  Future<List<String>> _getAssetManifest() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = jsonDecode(manifestContent);
      return manifest.keys.toList();
    } catch (e) {
      print('Failed to load asset manifest: $e');
      // Fallback: try common files
      return ['assets/webapp/index.html', 'assets/webapp/vite.svg'];
    }
  }

  /// Extract a single asset to the temp directory
  Future<void> _extractAsset(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // Remove 'assets/webapp/' prefix for the destination path
      final relativePath = assetPath.replaceFirst('assets/webapp/', '');
      final destFile = File('${_webappDir!.path}/$relativePath');

      // Create parent directories if needed
      await destFile.parent.create(recursive: true);

      // Write the file
      await destFile.writeAsBytes(bytes);
      print('Extracted: $assetPath -> ${destFile.path}');
    } catch (e) {
      print('Failed to extract asset $assetPath: $e');
    }
  }

  /// Logging middleware that emits to the log stream
  Middleware _loggingMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final stopwatch = Stopwatch()..start();

        try {
          final response = await handler(request);
          stopwatch.stop();

          // Log the request
          _addLog(ServerLogEntry(
            timestamp: DateTime.now(),
            method: request.method,
            path: '/${request.url.path}',
            statusCode: response.statusCode,
            duration: stopwatch.elapsed,
          ));

          return response;
        } catch (e) {
          stopwatch.stop();

          _addLog(ServerLogEntry(
            timestamp: DateTime.now(),
            method: request.method,
            path: '/${request.url.path}',
            statusCode: 500,
            message: e.toString(),
            duration: stopwatch.elapsed,
          ));

          rethrow;
        }
      };
    };
  }

  /// CORS middleware for development
  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        // Handle preflight requests
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers':
            'Origin, Content-Type, Accept, Authorization',
      };

  Future<void> stopServer() async {
    if (_server == null) {
      print('Server not running');
      return;
    }

    await _server!.close(force: true);
    _server = null;
    _localIp = null;

    // Clean up temp directory
    if (_webappDir != null && await _webappDir!.exists()) {
      try {
        await _webappDir!.delete(recursive: true);
        print('Cleaned up temp webapp directory');
      } catch (e) {
        print('Failed to clean up temp directory: $e');
      }
    }
    _webappDir = null;

    print('Server stopped');
  }

  void dispose() {
    _randomNumberController.close();
    _logController.close();
  }
}
