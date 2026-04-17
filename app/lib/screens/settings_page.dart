import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/screens/categories_page.dart';
import 'package:totals/screens/notification_settings_page.dart';
import 'package:totals/widgets/clear_database_dialog.dart';
import 'package:totals/screens/profile_management_page.dart';
import 'package:totals/screens/telebirr_bank_transfer_matches_page.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/theme/app_font_option.dart';

Future<void> _openSupportLink() async {
  final uri = Uri.parse('https://www.gurshaplus.com/detached');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    // Fallback to platform default
    await launchUrl(uri);
  }
}

Future<void> _openSupportChat() async {
  final uri = Uri.parse('https://t.me/totals_chat');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    await launchUrl(uri);
  }
}

Widget _buildHeaderBackground(BuildContext context) {
  final theme = Theme.of(context);

  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          theme.colorScheme.primary.withOpacity(0.24),
          theme.colorScheme.secondary.withOpacity(0.16),
          theme.colorScheme.background,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -40,
          right: -30,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(0.18),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -40,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondary.withOpacity(0.16),
            ),
          ),
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  final DataExportImportService _exportImportService =
      DataExportImportService();
  final ProfileRepository _profileRepo = ProfileRepository();
  final SmsConfigService _smsConfigService = SmsConfigService();
  bool _isExporting = false;
  bool _isExportingCsv = false;
  bool _isImporting = false;
  bool _isRefreshingWidget = false;
  bool _isFetchingSmsPatterns = false;
  bool _useRedesign = true;
  bool _isLoadingRedesign = true;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _loadRedesignSetting();
  }

  Future<void> _loadRedesignSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useRedesign = prefs.getBool('use_redesign') ?? true;
        _isLoadingRedesign = false;
      });
    }
  }

  Future<void> _toggleRedesign(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_redesign', value);
    setState(() => _useRedesign = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restart the app to apply the new design.'),
      ),
    );
  }

  Future<void> _fetchSmsPatterns() async {
    if (_isFetchingSmsPatterns) {
      print(
          "debug: Legacy settings SMS pattern fetch ignored - already in progress");
      return;
    }

    print("debug: Legacy settings SMS pattern fetch requested by user");
    setState(() => _isFetchingSmsPatterns = true);
    try {
      final count = await _smsConfigService.refreshPatternsFromInternet();
      print(
          "debug: Legacy settings SMS pattern fetch succeeded with $count patterns");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fetched $count SMS patterns from the internet.'),
        ),
      );
    } catch (error) {
      print("debug: Legacy settings SMS pattern fetch failed: $error");
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFetchingSmsPatterns = false);
      }
      print("debug: Legacy settings SMS pattern fetch finished");
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _exportCsvData() async {
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Export Transactions as CSV'),
        content: const Text(
            'Export all transactions to a CSV file (compatible with Excel/Sheets).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    setState(() => _isExportingCsv = true);
    try {
      final csvData = await _exportImportService.exportTransactionsCsv();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'totals_transactions_$timestamp.csv';

      if (action == 'save') {
        if (!mounted) return;

        if (Platform.isAndroid) {
          try {
            final directory = Directory('/storage/emulated/0/Download');
            if (!await directory.exists()) {
              final appDir = await getApplicationDocumentsDirectory();
              final file = File('${appDir.path}/$fileName');
              await file.writeAsString(csvData);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('CSV saved to: ${appDir.path}/$fileName',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              }
            } else {
              final file = File('${directory.path}/$fileName');
              await file.writeAsString(csvData);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('CSV saved to Downloads folder',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              }
            }
          } catch (e) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/$fileName');
            await tempFile.writeAsString(csvData);
            if (mounted) {
              await Share.shareXFiles([XFile(tempFile.path)],
                  text: 'Totals Transactions CSV', subject: 'Totals CSV');
            }
          }
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$fileName');
          await tempFile.writeAsString(csvData);

          if (!mounted) return;

          String? result;
          try {
            result = await FilePicker.platform.saveFile(
              dialogTitle: 'Save CSV File',
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['csv'],
            );
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            if (mounted) {
              setState(() => _isExportingCsv = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to open file picker: $e',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onError)),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ));
            }
            return;
          }

          if (!mounted) {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            return;
          }

          if (result != null && result.isNotEmpty) {
            try {
              await tempFile.copy(result);
              try {
                if (await tempFile.exists()) await tempFile.delete();
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('CSV saved successfully',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              }
            } catch (e) {
              try {
                if (await tempFile.exists()) await tempFile.delete();
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Failed to save file: $e',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onError)),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              }
            }
          } else {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            if (mounted) setState(() => _isExportingCsv = false);
            return;
          }
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(csvData);
        if (!mounted) return;
        await Share.shareXFiles([XFile(file.path)],
            text: 'Totals Transactions CSV', subject: 'Totals CSV');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('CSV exported successfully',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV export failed: $e',
              style:
                  TextStyle(color: Theme.of(context).colorScheme.onError)),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  Future<void> _exportData() async {
    if (!mounted) return;

    // Show dialog to choose between save and share - always show this dialog
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text('Choose how you want to export your data:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final jsonData = await _exportImportService.exportAllData();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'totals_export_$timestamp.json';

      if (action == 'save') {
        if (!mounted) return;

        // On Android, saveFile has issues with content URIs
        // Use a workaround: save to temp file and let user share/save it
        if (Platform.isAndroid) {
          // For Android, save to Downloads folder directly
          // This avoids the content URI issue
          try {
            final directory = Directory('/storage/emulated/0/Download');
            if (!await directory.exists()) {
              // Fallback to app documents directory
              final appDir = await getApplicationDocumentsDirectory();
              final file = File('${appDir.path}/$fileName');
              await file.writeAsString(jsonData);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Data saved to: ${appDir.path}/$fileName',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            } else {
              final file = File('${directory.path}/$fileName');
              await file.writeAsString(jsonData);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Data saved to Downloads folder',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            }
          } catch (e) {
            // If direct save fails, use share as fallback
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/$fileName');
            await tempFile.writeAsString(jsonData);

            if (mounted) {
              await Share.shareXFiles(
                [XFile(tempFile.path)],
                text: 'Totals Data Export',
                subject: 'Totals Backup',
              );

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Use Share to save the file',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          }
        } else {
          // For iOS and other platforms, use file picker
          // Write to temp file first to avoid app state issues
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$fileName');
          await tempFile.writeAsString(jsonData);

          if (!mounted) return;

          // Let user choose where to save the file
          String? result;
          try {
            result = await FilePicker.platform.saveFile(
              dialogTitle: 'Save Export File',
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['json'],
            );

            // Small delay to ensure app is back in foreground after file picker
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            // If file picker fails, clean up and show error
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}

            if (mounted) {
              setState(() => _isExporting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Failed to open file picker: $e',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.onError),
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
            return;
          }

          // Check if app is still mounted after file picker
          if (!mounted) {
            // Clean up temp file if app was killed
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}
            return;
          }

          // Double-check mounted after delay
          if (!mounted) {
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}
            return;
          }

          if (result != null && result.isNotEmpty) {
            try {
              // Copy from temp file to user-selected location
              final targetFile = File(result);
              await tempFile.copy(targetFile.path);

              // Clean up temp file
              try {
                if (await tempFile.exists()) {
                  await tempFile.delete();
                }
              } catch (_) {}

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Data saved successfully',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            } catch (e) {
              // If copy fails, try direct write
              try {
                final targetFile = File(result);
                await targetFile.writeAsString(jsonData);

                // Clean up temp file
                try {
                  if (await tempFile.exists()) {
                    await tempFile.delete();
                  }
                } catch (_) {}

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Data saved successfully',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary),
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              } catch (writeError) {
                // Clean up temp file
                try {
                  if (await tempFile.exists()) {
                    await tempFile.delete();
                  }
                } catch (_) {}

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to save file: $writeError',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onError),
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              }
            }
          } else {
            // User cancelled the file picker - clean up temp file
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (_) {}

            if (mounted) {
              setState(() => _isExporting = false);
            }
            return;
          }
        }
      } else {
        // Share the file
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(jsonData);

        if (!mounted) return;

        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Totals Data Export',
          subject: 'Totals Backup',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data exported successfully',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export failed: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importData() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonData = await file.readAsString();

        // Show confirmation dialog
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Import Data'),
            content: const Text(
              'This will add the imported data to your existing data. Duplicates will be skipped.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Import'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await _exportImportService.importAllData(jsonData);

          // Reload data in provider
          if (mounted) {
            final provider =
                Provider.of<TransactionProvider>(context, listen: false);
            await provider.loadData();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Data imported successfully',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import failed: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _refreshWidget() async {
    if (_isRefreshingWidget) return;
    setState(() => _isRefreshingWidget = true);
    try {
      await WidgetService.refreshWidget();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Widget refreshed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Widget refresh failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingWidget = false);
      }
    }
  }

  String _getProfileInitials(String profileName) {
    if (profileName.isEmpty) return 'U';
    final parts = profileName.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return profileName[0].toUpperCase();
  }

  Future<void> _navigateToManageProfiles() async {
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileManagementPage(),
      ),
    );
    // Refresh the page and reload transaction data if profile was changed
    if (result == true && mounted) {
      setState(() {});
      // Reload transaction provider to show new profile's data
      try {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
      } catch (e) {
        print("debug: Error reloading transaction provider: $e");
      }
    }
  }

  String _scaleLabel(double scale) {
    final formatted = scale
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}x';
  }

  String _paddingLabel(double value) {
    final formatted = value
        .toStringAsFixed(1)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}px';
  }

  int _closestOptionIndex(double value, List<double> options) {
    int bestIndex = 0;
    double bestDelta = (value - options.first).abs();
    for (int i = 1; i < options.length; i++) {
      final delta = (value - options[i]).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _showFontSizeSheet(ThemeProvider themeProvider) async {
    final theme = Theme.of(context);
    final initialScale = themeProvider.uiScale;
    final scaleOptions = themeProvider.availableUiScales;
    final initialTopPadding = themeProvider.appTopPadding;
    final paddingOptions = themeProvider.availableAppTopPaddings;
    int selectedScaleIndex = _closestOptionIndex(initialScale, scaleOptions);
    int selectedPaddingIndex =
        _closestOptionIndex(initialTopPadding, paddingOptions);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final selectedScale = scaleOptions[selectedScaleIndex];
          final selectedTopPadding = paddingOptions[selectedPaddingIndex];

          Future<void> updateScale(int index) async {
            if (index == selectedScaleIndex) return;
            setSheetState(() => selectedScaleIndex = index);
            await themeProvider.setUiScale(scaleOptions[index]);
          }

          Future<void> updateTopPadding(int index) async {
            if (index == selectedPaddingIndex) return;
            setSheetState(() => selectedPaddingIndex = index);
            await themeProvider.setAppTopPadding(paddingOptions[index]);
          }

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Display Size',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Preview and adjust interface scale and top padding.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: 16 * selectedScale,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your settings and transaction labels adapt here.',
                          style: TextStyle(
                            fontSize: 13 * selectedScale,
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Current size: ${_scaleLabel(selectedScale)}',
                          style: TextStyle(
                            fontSize: 12 * selectedScale,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Top padding: ${_paddingLabel(selectedTopPadding)}',
                          style: TextStyle(
                            fontSize: 12 * selectedScale,
                            fontWeight: FontWeight.w600,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Slider(
                    value: selectedScaleIndex.toDouble(),
                    min: 0,
                    max: (scaleOptions.length - 1).toDouble(),
                    divisions: scaleOptions.length - 1,
                    label: _scaleLabel(selectedScale),
                    onChanged: (value) => updateScale(value.round()),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < scaleOptions.length; i++)
                        ChoiceChip(
                          label: Text(_scaleLabel(scaleOptions[i])),
                          selected: i == selectedScaleIndex,
                          onSelected: (_) => updateScale(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Top Padding',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add extra space above the app content.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < paddingOptions.length; i++)
                        ChoiceChip(
                          label: Text(_paddingLabel(paddingOptions[i])),
                          selected: i == selectedPaddingIndex,
                          onSelected: (_) => updateTopPadding(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true && mounted) {
      await themeProvider.setUiScale(initialScale);
      await themeProvider.setAppTopPadding(initialTopPadding);
    }
  }

  Future<void> _showFontSheet(ThemeProvider themeProvider) async {
    final theme = Theme.of(context);
    final options = themeProvider.availableAppFonts;
    AppFontOption selectedFont = themeProvider.appFont;

    final pickedFont = await showModalBottomSheet<AppFontOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Font',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final option in options) ...[
                    RadioListTile<AppFontOption>(
                      value: option,
                      groupValue: selectedFont,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        option.label,
                        style: AppFontTheme.previewTextStyle(
                          theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          option,
                          redesign: false,
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedFont = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(selectedFont),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || pickedFont == null) return;
    await themeProvider.setAppFont(pickedFont);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            snap: false,
            elevation: 0,
            backgroundColor: theme.colorScheme.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'Settings',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: FutureBuilder(
              future: _profileRepo.getActiveProfile(),
              builder: (context, snapshot) {
                final profileName = snapshot.data?.name ?? 'Personal';
                final profileInitials = _getProfileInitials(profileName);

                return Consumer<TransactionProvider>(
                  builder: (context, provider, child) {
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        // Profile Card
                        _buildProfileCard(
                          context: context,
                          profileName: profileName,
                          profileInitials: profileInitials,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 24),

                        // Section: Settings
                        _buildSectionHeader(title: 'Preferences'),
                        const SizedBox(height: 12),
                        _buildSettingsCard(
                          children: [
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, child) {
                                return _buildSettingTile(
                                  icon:
                                      themeProvider.themeMode == ThemeMode.dark
                                          ? Icons.light_mode_rounded
                                          : Icons.dark_mode_rounded,
                                  title: 'Theme',
                                  trailing: Switch(
                                    value: themeProvider.themeMode ==
                                        ThemeMode.dark,
                                    onChanged: (value) {
                                      themeProvider.toggleTheme();
                                    },
                                  ),
                                  onTap: null,
                                );
                              },
                            ),
                            _buildDivider(context),
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, child) {
                                return _buildSettingTile(
                                  icon: Icons.zoom_out_map_rounded,
                                  title: 'Display size',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${themeProvider.uiScaleLabel} • ${themeProvider.appTopPaddingLabel}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.65),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.3),
                                      ),
                                    ],
                                  ),
                                  onTap: () =>
                                      _showFontSizeSheet(themeProvider),
                                );
                              },
                            ),
                            _buildDivider(context),
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, child) {
                                return _buildSettingTile(
                                  icon: Icons.text_fields_rounded,
                                  title: 'Font',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        themeProvider.appFontLabel,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurface
                                              .withOpacity(0.65),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.3),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showFontSheet(themeProvider),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _isLoadingRedesign
                                ? const SizedBox.shrink()
                                : _buildSettingTile(
                                    icon: Icons.palette_rounded,
                                    title: 'Use Redesign',
                                    trailing: Switch(
                                      value: _useRedesign,
                                      onChanged: _toggleRedesign,
                                    ),
                                    onTap: null,
                                  ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.toc_rounded,
                              title: 'Categories',
                              flipIconHorizontally: true,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const CategoriesPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.notifications_rounded,
                              title: 'Notifications',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationSettingsPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.swap_horiz_rounded,
                              title: 'Telebirr bank matches',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const TelebirrBankTransferMatchesPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.sync_rounded,
                              title: 'Fetch SMS patterns',
                              trailing: _isFetchingSmsPatterns
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : null,
                              onTap: _isFetchingSmsPatterns
                                  ? null
                                  : _fetchSmsPatterns,
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.upload_rounded,
                              title: 'Export Data',
                              trailing: _isExporting
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : null,
                              onTap: _isExporting ? null : _exportData,
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.table_chart_rounded,
                              title: 'Export Transactions as CSV',
                              trailing: _isExportingCsv
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : null,
                              onTap: _isExportingCsv ? null : _exportCsvData,
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.download_rounded,
                              title: 'Import Data',
                              trailing: _isImporting
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : null,
                              onTap: _isImporting ? null : _importData,
                            ),
                            /*
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.refresh_rounded,
                              title: 'Refresh widget',
                              trailing: _isRefreshingWidget
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : null,
                              onTap:
                                  _isRefreshingWidget ? null : _refreshWidget,
                            ),
                            */
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Section: Support
                        _buildSectionHeader(title: 'Support'),
                        const SizedBox(height: 12),
                        _buildSettingsCard(
                          children: [
                            _buildSettingTile(
                              icon: Icons.info_outline_rounded,
                              title: 'About',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AboutPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.help_outline_rounded,
                              title: 'Help & FAQ',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const FAQPage(),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(context),
                            _buildSettingTile(
                              icon: Icons.delete_outline_rounded,
                              title: 'Clear Data',
                              titleColor: theme.colorScheme.error,
                              onTap: () => showClearDatabaseDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Support Developers Button
                        _buildSupportDevelopersButton(),
                        const SizedBox(height: 100), // Padding for floating nav
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required BuildContext context,
    required String profileName,
    required String profileInitials,
    required bool isDark,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _navigateToManageProfiles,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    profileInitials,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profileName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage profiles',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
    bool showTrailing = true,
    bool flipIconHorizontally = false,
  }) {
    final theme = Theme.of(context);
    Widget leadingIcon = Icon(
      icon,
      size: 22,
      color: theme.colorScheme.primary,
    );
    if (flipIconHorizontally) {
      leadingIcon = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
        child: leadingIcon,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: leadingIcon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: titleColor ?? theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w400,
                    fontSize: 16,
                  ),
                ),
              ),
              if (trailing != null)
                trailing
              else if (showTrailing && onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1),
      ),
    );
  }

  Widget _buildSupportDevelopersButton() {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSupportLink,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.primary.withOpacity(0.1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  return Icon(
                    Icons.favorite_rounded,
                    color: theme.colorScheme.primary,
                    size: 20 * (1 + 0.1 * _shimmerController.value),
                  );
                },
              ),
              const SizedBox(width: 12),
              Text(
                'Support the Project',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Widget _buildFeatureChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSupportLink,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.favorite_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Support the devs',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Help us keep improving Totals with thoughtful updates.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 170,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.colorScheme.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'About',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: _buildHeaderBackground(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Totals',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Version 1.1.0',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Image.asset(
                        'assets/images/detached_logo.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'by detached',
                        style: theme.textTheme.labelLarge?.copyWith(
                          letterSpacing: 1.1,
                          color: theme.colorScheme.onSurface.withOpacity(0.65),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'A personal finance tracker that keeps your bank activity organized, searchable, and easy to understand.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildFeatureChip(
                            context,
                            icon: Icons.lock_outline_rounded,
                            label: 'Private',
                          ),
                          _buildFeatureChip(
                            context,
                            icon: Icons.bolt_rounded,
                            label: 'Fast',
                          ),
                          _buildFeatureChip(
                            context,
                            icon: Icons.auto_graph_rounded,
                            label: 'Insightful',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSupportCard(context),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class FAQPage extends StatefulWidget {
  const FAQPage({super.key});

  @override
  State<FAQPage> createState() => _FAQPageState();
}

class _FAQPageState extends State<FAQPage> {
  final Map<int, bool> _expandedItems = {};

  final List<Map<String, String>> _faqs = [
    {
      'question': 'How do I export my data?',
      'answer':
          'Go to Settings > Export Data. You can choose to save the file directly or share it with other apps.',
    },
    {
      'question': 'How do I categorize transactions?',
      'answer':
          'Tap on any transaction in your transaction list and select a category from the list that appears.',
    },
    {
      'question': 'Can I import data from another device?',
      'answer':
          'Yes! Use the Export Data feature to create a backup file, then use Import Data on your other device to restore it.',
    },
    {
      'question': 'My SMS is not parsed. How can I parse it?',
      'answer':
          'Open the Failed Parses page and retry parsing the message from there. It is the button next to the lock button on the home page.',
    },
    {
      'question': 'Skipped a transaction today?',
      'answer':
          "In Today's transactions, tap the refresh button to rescan today's bank SMS to add anything that was missed.",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faqItems = List<Widget>.generate(_faqs.length, (index) {
      final isExpanded = _expandedItems[index] ?? false;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildFAQItem(
          context: context,
          index: index,
          question: _faqs[index]['question']!,
          answer: _faqs[index]['answer']!,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              _expandedItems[index] = !isExpanded;
            });
          },
        ),
      );
    });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 170,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.colorScheme.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'Help & FAQ',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: _buildHeaderBackground(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildIntroCard(context),
                const SizedBox(height: 20),
                ...faqItems,
                const SizedBox(height: 20),
                _buildSupportFooter(context),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.help_outline_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick answers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap a question to reveal the details.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportFooter(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Still need help?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reach out to detached and we will point you in the right direction.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _openSupportChat,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(color: theme.colorScheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Contact us'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQItem({
    required BuildContext context,
    required int index,
    required String question,
    required String answer,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      question,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(left: 44, top: 12, right: 4),
                  child: Text(
                    answer,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
