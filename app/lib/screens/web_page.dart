import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/local_server/server_service.dart';
import 'package:totals/local_server/network_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class WebPage extends StatefulWidget {
  const WebPage({super.key});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  final ServerService _serverService = ServerService();
  final ScrollController _scrollController = ScrollController();
  final List<_ConsoleEntry> _consoleEntries = [];
  StreamSubscription<ServerLogEntry>? _logSubscription;

  bool _isLoading = false;
  bool _isNerdMode = false; // Toggle between simple and console mode
  String? _networkIp;

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
    _addSystemLog('Console initialized. Ready to start server.');
  }

  Future<void> _loadNetworkInfo() async {
    final ip = await NetworkUtils.getLocalIpAddress();
    if (mounted) {
      setState(() {
        _networkIp = ip;
      });
    }
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    _serverService.stopServer();
    _serverService.dispose();
    super.dispose();
  }

  void _addSystemLog(String message,
      {bool isError = false, bool isSuccess = false}) {
    setState(() {
      _consoleEntries.add(_ConsoleEntry(
        timestamp: DateTime.now(),
        message: message,
        type: isError
            ? _ConsoleEntryType.error
            : isSuccess
                ? _ConsoleEntryType.success
                : _ConsoleEntryType.system,
      ));
    });
    _scrollToBottom();
  }

  void _addRequestLog(ServerLogEntry entry) {
    setState(() {
      _consoleEntries.add(_ConsoleEntry(
        timestamp: entry.timestamp,
        message: '${entry.method} ${entry.path}',
        type: _ConsoleEntryType.request,
        statusCode: entry.statusCode,
        duration: entry.duration,
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleServer() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_serverService.isRunning) {
        _addSystemLog('Stopping server...');
        _logSubscription?.cancel();
        await _serverService.stopServer();
        _addSystemLog('Server stopped.', isSuccess: true);
      } else {
        _addSystemLog('Starting server...');
        await _serverService.startServer();
        await _loadNetworkInfo();

        // Subscribe to log stream
        _logSubscription = _serverService.logStream.listen(_addRequestLog);

        _addSystemLog('Server started successfully!', isSuccess: true);
        _addSystemLog('Listening on ${_serverService.serverUrl}');
        _addSystemLog('API endpoints ready:');
        _addSystemLog('  → /api/accounts');
        _addSystemLog('  → /api/transactions');
        _addSystemLog('  → /api/summary');
        _addSystemLog('  → /api/banks');
      }
    } catch (e) {
      _addSystemLog('Error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearConsole() {
    setState(() {
      _consoleEntries.clear();
    });
    _addSystemLog('Console cleared.');
  }

  void _copyUrl() {
    if (_serverService.serverUrl != null) {
      Clipboard.setData(ClipboardData(text: _serverService.serverUrl!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('URL copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      _addSystemLog('URL copied to clipboard.');
    }
  }

  Future<void> _openDashboard() async {
    if (_serverService.serverUrl != null) {
      final uri = Uri.parse(_serverService.serverUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isNerdMode ? _buildConsoleMode() : _buildSimpleMode();
  }

  // ============ SIMPLE MODE (Layman-friendly) ============
  Widget _buildSimpleMode() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isRunning = _serverService.isRunning;

    // App theme colors
    final primaryColor = colorScheme.primary;
    final secondaryColor = colorScheme.secondary;
    final surfaceColor = colorScheme.surface;
    final surfaceVariantColor = colorScheme.surfaceVariant;
    final onSurfaceColor = colorScheme.onSurface;
    final onSurfaceVariantColor = colorScheme.onSurfaceVariant;

    // Status colors that complement the blue theme
    final runningColor = const Color(0xFF4CAF50); // Green for running

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0E1A) : colorScheme.background,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0A0E1A) : null,
        title: Text(
          'Web Dashboard',
          style: TextStyle(color: onSurfaceColor),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          // Nerd mode toggle
          TextButton.icon(
            onPressed: () => setState(() => _isNerdMode = true),
            icon: Icon(
              Icons.terminal,
              size: 18,
              color: onSurfaceVariantColor,
            ),
            label: Text(
              'For Nerds',
              style: TextStyle(
                color: onSurfaceVariantColor,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Main illustration/icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isRunning
                          ? [runningColor, runningColor.withOpacity(0.8)]
                          : [primaryColor, secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning ? runningColor : primaryColor)
                            .withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    isRunning ? Icons.cloud_done : Icons.cloud_off,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),

                // Status text
                Text(
                  isRunning ? 'Server is Running!' : 'Server is Stopped',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isRunning ? runningColor : onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    isRunning
                        ? 'Your web dashboard is ready! Open the link below in any browser on this network to view your financial data.'
                        : 'Start the server to access your financial dashboard from any browser on this network.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurfaceVariantColor,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Start/Stop Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _toggleServer,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(isRunning ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      _isLoading
                          ? (isRunning ? 'Stopping...' : 'Starting...')
                          : (isRunning ? 'Stop Server' : 'Start Server'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isRunning ? Colors.red.shade600 : primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),

                // URL Card (when running)
                if (isRunning && _serverService.serverUrl != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? surfaceVariantColor : surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: runningColor.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: runningColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.link,
                                color: runningColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dashboard URL',
                                    style: TextStyle(
                                      color: onSurfaceVariantColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _serverService.serverUrl!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: onSurfaceColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _copyUrl,
                                icon: Icon(Icons.copy,
                                    size: 18, color: primaryColor),
                                label: Text('Copy Link',
                                    style: TextStyle(color: primaryColor)),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(
                                      color: primaryColor.withOpacity(0.5)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _openDashboard,
                                icon:
                                    const Icon(Icons.open_in_browser, size: 18),
                                label: const Text('Open'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: primaryColor,
                                  foregroundColor: colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Instructions
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Open this link on any device connected to the same WiFi network',
                            style: TextStyle(
                              color: isDark
                                  ? primaryColor.withOpacity(0.9)
                                  : primaryColor.withOpacity(0.8),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Network info when not running
                if (!isRunning && _networkIp != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: surfaceVariantColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi,
                          size: 18,
                          color: onSurfaceVariantColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Your IP: $_networkIp',
                          style: TextStyle(
                            color: onSurfaceVariantColor,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ CONSOLE MODE (For Nerds) ============
  Widget _buildConsoleMode() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final consoleBackground =
        isDark ? const Color(0xFF0D1117) : const Color(0xFF1E1E1E);
    final headerBackground =
        isDark ? const Color(0xFF161B22) : const Color(0xFF2D2D2D);

    return Scaffold(
      backgroundColor: consoleBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar
            _buildHeader(headerBackground, isDark),

            // Console Output
            Expanded(
              child: _buildConsole(consoleBackground),
            ),

            // Bottom Status Bar
            _buildStatusBar(headerBackground, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color backgroundColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back to simple mode button
          Tooltip(
            message: 'Back to Simple Mode',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _isNerdMode = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_back,
                    color: Colors.white.withOpacity(0.7),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Terminal Icon & Title
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _serverService.isRunning
                  ? Colors.green.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.terminal,
              color:
                  _serverService.isRunning ? Colors.greenAccent : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Totals Server',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _serverService.isRunning
                    ? 'Running on port ${_serverService.port}'
                    : 'Stopped',
                style: TextStyle(
                  color: _serverService.isRunning
                      ? Colors.greenAccent.withOpacity(0.8)
                      : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Action Buttons
          _buildHeaderButton(
            icon: Icons.delete_outline,
            tooltip: 'Clear Console',
            onPressed: _clearConsole,
          ),
          const SizedBox(width: 8),
          if (_serverService.isRunning) ...[
            _buildHeaderButton(
              icon: Icons.copy,
              tooltip: 'Copy URL',
              onPressed: _copyUrl,
            ),
            const SizedBox(width: 8),
          ],
          _buildServerToggleButton(),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.white.withOpacity(0.7),
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerToggleButton() {
    final isRunning = _serverService.isRunning;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _toggleServer,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isRunning
                ? Colors.red.withOpacity(0.2)
                : Colors.green.withOpacity(0.2),
            border: Border.all(
              color: isRunning
                  ? Colors.red.withOpacity(0.5)
                  : Colors.green.withOpacity(0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isRunning ? Colors.red : Colors.greenAccent,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRunning ? Icons.stop : Icons.play_arrow,
                      color: isRunning ? Colors.red : Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? 'Stop' : 'Start',
                      style: TextStyle(
                        color: isRunning ? Colors.red : Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildConsole(Color backgroundColor) {
    return Container(
      color: backgroundColor,
      child: _consoleEntries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.terminal,
                    size: 48,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No logs yet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start the server to see request logs',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _consoleEntries.length,
              itemBuilder: (context, index) {
                return _buildConsoleEntry(_consoleEntries[index]);
              },
            ),
    );
  }

  Widget _buildConsoleEntry(_ConsoleEntry entry) {
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    Color textColor;
    Color? badgeColor;
    String? badgeText;

    switch (entry.type) {
      case _ConsoleEntryType.system:
        textColor = Colors.white.withOpacity(0.6);
        break;
      case _ConsoleEntryType.success:
        textColor = Colors.greenAccent;
        break;
      case _ConsoleEntryType.error:
        textColor = Colors.redAccent;
        break;
      case _ConsoleEntryType.request:
        textColor = Colors.white.withOpacity(0.9);
        if (entry.statusCode != null) {
          if (entry.statusCode! >= 200 && entry.statusCode! < 300) {
            badgeColor = Colors.green;
          } else if (entry.statusCode! >= 400) {
            badgeColor = Colors.red;
          } else {
            badgeColor = Colors.orange;
          }
          badgeText = '${entry.statusCode}';
        }
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            timeStr,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),

          // Status badge for requests
          if (badgeText != null && badgeColor != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: badgeColor.withOpacity(0.5)),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Message
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),

          // Duration for requests
          if (entry.duration != null)
            Text(
              '${entry.duration!.inMilliseconds}ms',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(Color backgroundColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Connection Status Indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  _serverService.isRunning ? Colors.greenAccent : Colors.grey,
              boxShadow: _serverService.isRunning
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _serverService.isRunning ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color:
                  _serverService.isRunning ? Colors.greenAccent : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(width: 24),

          // IP Address
          if (_networkIp != null) ...[
            Icon(
              Icons.wifi,
              color: Colors.white.withOpacity(0.4),
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              _networkIp!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],

          const Spacer(),

          // Log count
          Text(
            '${_consoleEntries.length} logs',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
            ),
          ),

          if (_serverService.isRunning) ...[
            const SizedBox(width: 16),
            // URL (tappable to copy)
            GestureDetector(
              onTap: _copyUrl,
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    color: Colors.blue.withOpacity(0.7),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _serverService.serverUrl ?? '',
                    style: TextStyle(
                      color: Colors.blue.withOpacity(0.8),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ConsoleEntryType {
  system,
  success,
  error,
  request,
}

class _ConsoleEntry {
  final DateTime timestamp;
  final String message;
  final _ConsoleEntryType type;
  final int? statusCode;
  final Duration? duration;

  _ConsoleEntry({
    required this.timestamp,
    required this.message,
    required this.type,
    this.statusCode,
    this.duration,
  });
}
