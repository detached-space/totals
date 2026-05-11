import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/screens/categories_page.dart';
import 'package:totals/screens/notification_settings_page.dart';
import 'package:totals/screens/privacy_policy_page.dart';
import 'package:totals/screens/profile_management_page.dart';
import 'package:totals/widgets/clear_database_dialog.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/theme/app_font_option.dart';

// ── Support links ───────────────────────────────────────────────────────────
Future<void> _openSupportLink() async {
  final uri = Uri.parse('https://www.gurshaplus.com/detached');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
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

// ═════════════════════════════════════════════════════════════════════════════
// Settings Page
// ═════════════════════════════════════════════════════════════════════════════

class RedesignSettingsPage extends StatefulWidget {
  const RedesignSettingsPage({super.key});

  @override
  State<RedesignSettingsPage> createState() => _RedesignSettingsPageState();
}

class _RedesignSettingsPageState extends State<RedesignSettingsPage> {
  final ProfileRepository _profileRepo = ProfileRepository();
  final DataExportImportService _exportImportService =
      DataExportImportService();
  final SmsConfigService _smsConfigService = SmsConfigService();

  bool _isExporting = false;
  bool _isImporting = false;
  bool _isFetchingSmsPatterns = false;

  Future<void> _fetchSmsPatterns() async {
    if (_isFetchingSmsPatterns) {
      print(
          "debug: Redesign settings SMS pattern fetch ignored - already in progress");
      return;
    }

    print("debug: Redesign settings SMS pattern fetch requested by user");
    setState(() => _isFetchingSmsPatterns = true);
    try {
      final count = await _smsConfigService.refreshPatternsFromInternet();
      print(
          "debug: Redesign settings SMS pattern fetch succeeded with $count patterns");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fetched $count SMS patterns from the internet.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      print("debug: Redesign settings SMS pattern fetch failed: $error");
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFetchingSmsPatterns = false);
      }
      print("debug: Redesign settings SMS pattern fetch finished");
    }
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  String _getProfileInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name[0].toUpperCase();
  }

  Future<void> _navigateToManageProfiles() async {
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileManagementPage()),
    );
    if (result == true && mounted) {
      setState(() {});
      try {
        Provider.of<TransactionProvider>(context, listen: false).loadData();
      } catch (_) {}
    }
  }

  // ── Display size sheet ──────────────────────────────────────────────────

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
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
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
              20 +
                  MediaQuery.of(sheetCtx).viewInsets.bottom +
                  MediaQuery.of(sheetCtx).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardColor(sheetCtx),
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
                        color: AppColors.slate400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Display Size',
                    style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(sheetCtx),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Preview and adjust interface scale and top padding.',
                    style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(sheetCtx),
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor(sheetCtx),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.borderColor(sheetCtx)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: 16 * selectedScale,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(sheetCtx),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Transaction categorized successfully.',
                          style: TextStyle(
                            fontSize: 13 * selectedScale,
                            color: AppColors.textSecondary(sheetCtx),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Current size: ${_scaleLabel(selectedScale)}',
                          style: TextStyle(
                            fontSize: 12 * selectedScale,
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Top padding: ${_paddingLabel(selectedTopPadding)}',
                          style: TextStyle(
                            fontSize: 12 * selectedScale,
                            color: AppColors.textSecondary(sheetCtx),
                            fontWeight: FontWeight.w600,
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
                    activeColor: AppColors.primaryLight,
                    inactiveColor: AppColors.borderColor(sheetCtx),
                    onChanged: (v) => updateScale(v.round()),
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
                          selectedColor:
                              AppColors.primaryLight.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: i == selectedScaleIndex
                                ? AppColors.primaryLight
                                : AppColors.borderColor(sheetCtx),
                          ),
                          labelStyle: TextStyle(
                            color: i == selectedScaleIndex
                                ? AppColors.primaryLight
                                : AppColors.textPrimary(sheetCtx),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => updateScale(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Top Padding',
                    style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(sheetCtx),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add extra space above the app content.',
                    style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(sheetCtx),
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
                          selectedColor:
                              AppColors.primaryLight.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: i == selectedPaddingIndex
                                ? AppColors.primaryLight
                                : AppColors.borderColor(sheetCtx),
                          ),
                          labelStyle: TextStyle(
                            color: i == selectedPaddingIndex
                                ? AppColors.primaryLight
                                : AppColors.textPrimary(sheetCtx),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => updateTopPadding(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: AppColors.borderColor(sheetCtx)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                                color: AppColors.textSecondary(sheetCtx)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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
    final options = themeProvider.availableAppFonts;
    AppFontOption selectedFont = themeProvider.appFont;

    final pickedFont = await showModalBottomSheet<AppFontOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 +
                  MediaQuery.of(sheetCtx).viewInsets.bottom +
                  MediaQuery.of(sheetCtx).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardColor(sheetCtx),
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
                        color: AppColors.slate400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Font',
                    style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(sheetCtx),
                        ),
                  ),
                  const SizedBox(height: 16),
                  for (final option in options) ...[
                    RadioListTile<AppFontOption>(
                      value: option,
                      groupValue: selectedFont,
                      activeColor: AppColors.primaryLight,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        option.label,
                        style: AppFontTheme.previewTextStyle(
                          Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                                color: AppColors.textPrimary(sheetCtx),
                                fontWeight: FontWeight.w700,
                              ),
                          option,
                          redesign: true,
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
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.borderColor(sheetCtx),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.textSecondary(sheetCtx),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(sheetCtx).pop(selectedFont),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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

  // ── Export / Import ─────────────────────────────────────────────────────

  Future<void> _exportData() async {
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Export Data',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'Choose how you want to export your data:',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save to File'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
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
        if (Platform.isAndroid) {
          try {
            final directory = Directory('/storage/emulated/0/Download');
            if (await directory.exists()) {
              final file = File('${directory.path}/$fileName');
              await file.writeAsString(jsonData);
              if (mounted) _showSnack('Data saved to Downloads folder');
            } else {
              final appDir = await getApplicationDocumentsDirectory();
              final file = File('${appDir.path}/$fileName');
              await file.writeAsString(jsonData);
              if (mounted) {
                _showSnack('Data saved to: ${appDir.path}/$fileName');
              }
            }
          } catch (_) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/$fileName');
            await tempFile.writeAsString(jsonData);
            if (mounted) {
              await Share.shareXFiles(
                [XFile(tempFile.path)],
                text: 'Totals Data Export',
                subject: 'Totals Backup',
              );
              if (mounted) _showSnack('Use Share to save the file');
            }
          }
        } else {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$fileName');
          await tempFile.writeAsString(jsonData);
          if (!mounted) return;

          String? result;
          try {
            result = await FilePicker.platform.saveFile(
              dialogTitle: 'Save Export File',
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['json'],
            );
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
            if (mounted) _showErrorSnack('Failed to open file picker: $e');
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
              if (mounted) _showSnack('Data saved successfully');
            } catch (_) {
              try {
                await File(result).writeAsString(jsonData);
                try {
                  if (await tempFile.exists()) await tempFile.delete();
                } catch (_) {}
                if (mounted) _showSnack('Data saved successfully');
              } catch (writeErr) {
                try {
                  if (await tempFile.exists()) await tempFile.delete();
                } catch (_) {}
                if (mounted) _showErrorSnack('Failed to save file: $writeErr');
              }
            }
          } else {
            try {
              if (await tempFile.exists()) await tempFile.delete();
            } catch (_) {}
          }
        }
      } else {
        // Share
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(jsonData);
        if (!mounted) return;
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Totals Data Export',
          subject: 'Totals Backup',
        );
        if (mounted) _showSnack('Data exported successfully');
      }
    } catch (e) {
      if (mounted) _showErrorSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
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

        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardColor(ctx),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Import Data',
              style: TextStyle(color: AppColors.textPrimary(ctx)),
            ),
            content: Text(
              'This will add the imported data to your existing data. '
              'Duplicates will be skipped.',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary(ctx)),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Import'),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          await _exportImportService.importAllData(jsonData);
          if (mounted) {
            Provider.of<TransactionProvider>(context, listen: false).loadData();
            _showSnack('Data imported successfully');
          }
        }
      }
    } catch (e) {
      if (mounted) _showErrorSnack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return AppIcons.phone_iphone_rounded;
      case ThemeMode.light:
        return AppIcons.light_mode_rounded;
      case ThemeMode.dark:
        return AppIcons.dark_mode_rounded;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Preferences & settings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),

              // ── Profile card ────────────────────────────────────────────
              FutureBuilder(
                future: _profileRepo.getActiveProfile(),
                builder: (context, snapshot) {
                  final name = snapshot.data?.name ?? 'Personal';
                  final initials = _getProfileInitials(name);
                  return _ProfileCard(
                    name: name,
                    initials: initials,
                    onTap: _navigateToManageProfiles,
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Preferences ─────────────────────────────────────────────
              const _SectionHeader(label: 'Preferences'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: AppIcons.palette_outlined,
                iconColor: AppColors.primaryLight,
                title: 'Theme',
                subtitle: 'Tap to cycle: System, Light, Dark',
                trailing: OutlinedButton.icon(
                  onPressed: themeProvider.cycleThemeMode,
                  icon: Icon(
                    _themeModeIcon(themeProvider.themeMode),
                    size: 16,
                    color: AppColors.primaryLight,
                  ),
                  label: Text(
                    themeProvider.themeModeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 34),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    side: BorderSide(color: AppColors.borderColor(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                onTap: themeProvider.cycleThemeMode,
              ),

              _SettingTile(
                icon: AppIcons.zoom_out_map_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Display Size',
                subtitle: 'Preview and adjust interface scale and top padding',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${themeProvider.uiScaleLabel} • ${themeProvider.appTopPaddingLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      AppIcons.chevron_right,
                      color: AppColors.textTertiary(context),
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showFontSizeSheet(themeProvider),
              ),

              _SettingTile(
                icon: Icons.text_fields_rounded,
                iconColor: AppColors.blue,
                title: 'Font',
                subtitle: 'Switch between the default font and Inter',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      themeProvider.appFontLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      AppIcons.chevron_right,
                      color: AppColors.textTertiary(context),
                      size: 20,
                    ),
                  ],
                ),
                onTap: () => _showFontSheet(themeProvider),
              ),

              // if (!_isLoadingRedesign)
              //   _SettingTile(
              //     icon: AppIcons.palette_rounded,
              //     iconColor: AppColors.amber,
              //     title: 'Use Redesign',
              //     subtitle: 'Switch to the new design system',
              //     trailing: Switch(
              //       value: _useRedesign,
              //       onChanged: _toggleRedesign,
              //       activeColor: AppColors.primaryLight,
              //     ),
              //   ),

              _SettingTile(
                icon: AppIcons.toc_rounded,
                iconColor: AppColors.blue,
                title: 'Categories',
                subtitle: 'Manage transaction categories',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoriesPage()),
                ),
              ),

              // if (!_isLoadingAutoCategorize)
              //   _SettingTile(
              //     icon: AppIcons.category,
              //     iconColor: const Color(0xFFEC4899),
              //     title: 'Auto-categorize',
              //     subtitle: 'Categorize by receiver automatically',
              //     trailing: Switch(
              //       value: _autoCategorizeEnabled,
              //       onChanged: _toggleAutoCategorize,
              //       activeColor: AppColors.primaryLight,
              //     ),
              //   ),

              _SettingTile(
                icon: AppIcons.notifications_outlined,
                iconColor: AppColors.amber,
                title: 'Notifications',
                subtitle: 'Daily summary and budget alerts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsPage(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Data ────────────────────────────────────────────────────
              _SectionHeader(label: 'Data'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: AppIcons.refresh,
                iconColor: AppColors.blue,
                title: 'Fetch SMS Patterns',
                subtitle: 'Download the latest SMS parsing rules',
                showChevron: false,
                trailing: _isFetchingSmsPatterns
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
                onTap: _isFetchingSmsPatterns ? null : _fetchSmsPatterns,
              ),

              _SettingTile(
                icon: AppIcons.upload_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Export Data',
                subtitle: 'Save or share a backup',
                showChevron: false,
                trailing: _isExporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
                onTap: _isExporting ? null : _exportData,
              ),

              _SettingTile(
                icon: AppIcons.download_rounded,
                iconColor: AppColors.blue,
                title: 'Import Data',
                subtitle: 'Restore from a backup file',
                showChevron: false,
                trailing: _isImporting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryLight,
                        ),
                      )
                    : null,
                onTap: _isImporting ? null : _importData,
              ),

              _SettingTile(
                icon: AppIcons.delete_outline_rounded,
                iconColor: AppColors.red,
                title: 'Clear Data',
                subtitle: 'Delete selected app data',
                showChevron: false,
                onTap: () => showClearDatabaseDialog(context),
              ),

              const SizedBox(height: 24),

              // ── Support ─────────────────────────────────────────────────
              _SectionHeader(label: 'Support'),
              const SizedBox(height: 10),

              _SettingTile(
                icon: AppIcons.info_outline_rounded,
                iconColor: AppColors.primaryLight,
                title: 'About',
                subtitle: 'Version, privacy and credits',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _RedesignAboutPage(),
                  ),
                ),
              ),

              _SettingTile(
                icon: AppIcons.shield_check,
                iconColor: AppColors.primaryLight,
                title: 'Privacy Policy',
                subtitle: 'How Totals handles SMS, camera, and local data',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyPage(),
                  ),
                ),
              ),

              _SettingTile(
                icon: AppIcons.help_outline_rounded,
                iconColor: AppColors.incomeSuccess,
                title: 'Help & FAQ',
                subtitle: 'Common questions answered',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _RedesignFAQPage(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Support Developers ──────────────────────────────────────
              _SupportDevelopersCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.textTertiary(context),
            ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String initials;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.name,
    required this.initials,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage profiles',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null && showChevron)
                  Icon(
                    AppIcons.chevron_right_rounded,
                    color: AppColors.textTertiary(context),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportDevelopersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _openSupportLink,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                AppColors.primaryDark.withValues(alpha: 0.12),
                AppColors.primaryLight.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                AppIcons.favorite_rounded,
                color: AppColors.primaryLight,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Support the Project',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// About Page
// ═════════════════════════════════════════════════════════════════════════════

class _RedesignAboutPage extends StatelessWidget {
  const _RedesignAboutPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            AppIcons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Logo + App Info ──
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/icon/totals_icon.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'TOTALS',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Personal finance tracker for Ethiopian banks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Totals is a personal finance app for Ethiopian banks. '
                      'It automatically reads your bank SMS notifications, '
                      'tracks your transactions, and gives you a clear picture '
                      'of your money, balances, spending, budgets, and more, '
                      'all in one place.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── PRIVACY section ──
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                'PRIVACY',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),

            _AboutFeatureCard(
              icon: AppIcons.sms_outlined,
              title: 'SMS Stays On Device',
              description:
                  'For core transaction tracking, Totals reads and parses '
                  'supported bank SMS messages locally on your device. '
                  'Those SMS contents are not sent to our servers.',
            ),
            _AboutFeatureCard(
              icon: AppIcons.cloud_download,
              title: 'Optional Online Features',
              description:
                  'Payment verification and remote config updates can connect '
                  'to online services. Verification may transmit images, '
                  'payment references, selected account numbers, and bank '
                  'identifiers that you submit.',
            ),
            _AboutFeatureCard(
              icon: AppIcons.qr_code_scanner_rounded,
              title: 'Camera By Feature',
              description:
                  'Camera access is used for account QR scanning and payment '
                  'verification capture. QR scanning is handled on-device. '
                  'Verification images are uploaded only when you choose to '
                  'verify them.',
            ),
            _AboutFeatureCard(
              icon: AppIcons.visibility_off_outlined,
              title: 'No Ads or Analytics',
              description:
                  'Totals does not include advertising SDKs or analytics '
                  'telemetry to profile you or sell your data.',
            ),
            _AboutFeatureCard(
              icon: AppIcons.shield_check,
              title: 'Your Data, Your Control',
              description:
                  'Most app data stays on your device until you export, clear, '
                  'or uninstall it. If you manually start the local web '
                  'dashboard, your data becomes reachable on your local '
                  'network until you stop the server.',
            ),

            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PrivacyPolicyPage(),
                ),
              ),
              icon: const Icon(AppIcons.shield_check),
              label: const Text('Read Full Privacy Policy'),
            ),

            const SizedBox(height: 28),

            // ── HOW IT WORKS section ──
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                'HOW IT WORKS',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),

            _AboutStepCard(
              step: 1,
              description:
                  'Totals reads your bank SMS notifications directly on '
                  'your phone.',
            ),
            _AboutStepCard(
              step: 2,
              description:
                  'Transactions are parsed locally and saved to your device.',
            ),
            _AboutStepCard(
              step: 3,
              description:
                  'Totals organizes everything into your dashboard, all '
                  'on-device.',
            ),

            const SizedBox(height: 32),

            // ── Footer ──
            Center(
              child: Text(
                'Made by Detached',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      AppColors.textSecondary(context).withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AboutFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AboutFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: AppColors.primaryLight,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutStepCard extends StatelessWidget {
  final int step;
  final String description;

  const _AboutStepCard({
    required this.step,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FAQ Page
// ═════════════════════════════════════════════════════════════════════════════

class _RedesignFAQPage extends StatefulWidget {
  const _RedesignFAQPage();

  @override
  State<_RedesignFAQPage> createState() => _RedesignFAQPageState();
}

class _RedesignFAQPageState extends State<_RedesignFAQPage> {
  final Map<int, bool> _expanded = {};

  static const _gettingStarted = [
    {
      'icon': 'sms',
      'question': 'How does Totals read my transactions?',
      'answer': 'Totals reads SMS messages from your bank and automatically '
          'extracts transaction details like amount, date, and balance.',
    },
    {
      'icon': 'category',
      'question': 'How do I categorize transactions?',
      'answer':
          'Tap any transaction to open its details, then choose a category. '
              'Totals will remember and auto-categorize future transactions '
              'to the same recipient.',
    },
    {
      'icon': 'account',
      'question': 'Can I track multiple bank accounts?',
      'answer': 'Yes. Totals automatically detects accounts from your SMS and '
          'tracks each one separately. You can view balances and '
          'transactions per account.',
    },
  ];

  static const _dataManagement = [
    {
      'icon': 'export',
      'question': 'How do I export my data?',
      'answer': 'Go to Settings > Export Data. You can save the file directly '
          'or share it with other apps.',
    },
    {
      'icon': 'import',
      'question': 'Can I import data from another device?',
      'answer': 'Yes. Use Export Data to create a backup, then use Import Data '
          'on your other device to restore it.',
    },
    {
      'icon': 'failed',
      'question': 'My SMS was not parsed. What can I do?',
      'answer': 'Open the Failed Parses page from the home screen. You can '
          'retry parsing from there. If it still fails, the bank format '
          'may not be supported yet.',
    },
  ];

  static const _tips = [
    {
      'icon': 'refresh',
      'question': 'Missed a transaction today?',
      'answer': "In Today's transactions, tap the refresh button to rescan "
          "today's bank SMS and pick up anything that was missed.",
    },
    {
      'icon': 'budget',
      'question': 'How do budgets work?',
      'answer': 'Create a budget in the Budget tab with a spending limit and '
          'time period. Totals tracks your spending against it and '
          'notifies you when you are close to your limit.',
    },
    {
      'icon': 'lock',
      'question': 'How do I lock the app?',
      'answer': 'Double-tap the lock icon on the home screen to instantly '
          'lock the app. You will need to authenticate to get back in.',
    },
    {
      'icon': 'gesture',
      'question': 'Are there any shortcuts?',
      'answer': 'Long-press the bottom navigation bar items for quick actions. '
          'Long-press Money to add a cash transaction, long-press Tools '
          'to open your quick-access accounts, and long-press You to '
          'switch between profiles.',
    },
  ];

  IconData _iconForKey(String key) {
    switch (key) {
      case 'sms':
        return AppIcons.sms_outlined;
      case 'category':
        return AppIcons.category;
      case 'account':
        return AppIcons.account_balance_outlined;
      case 'lock':
        return AppIcons.lock_outline_rounded;
      case 'gesture':
        return AppIcons.bolt_rounded;
      case 'export':
        return AppIcons.upload_rounded;
      case 'import':
        return AppIcons.download_rounded;
      case 'failed':
        return AppIcons.info_outline_rounded;
      case 'refresh':
        return AppIcons.refresh;
      case 'budget':
        return AppIcons.savings_outlined;
      default:
        return AppIcons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            AppIcons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & FAQ',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── GETTING STARTED ──
            _sectionHeader(theme, 'GETTING STARTED'),
            ..._buildFaqItems(_gettingStarted, 0),

            const SizedBox(height: 28),

            // ── DATA & BACKUPS ──
            _sectionHeader(theme, 'DATA & BACKUPS'),
            ..._buildFaqItems(_dataManagement, _gettingStarted.length),

            const SizedBox(height: 28),

            // ── TIPS ──
            _sectionHeader(theme, 'TIPS'),
            ..._buildFaqItems(
                _tips, _gettingStarted.length + _dataManagement.length),

            const SizedBox(height: 28),

            // ── Contact ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.sms_outlined,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Still need help?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reach out and we will point you in the right direction.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _openSupportChat,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        side: const BorderSide(color: AppColors.primaryLight),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Contact us',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 14),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textSecondary(context),
        ),
      ),
    );
  }

  List<Widget> _buildFaqItems(
      List<Map<String, String>> items, int indexOffset) {
    final theme = Theme.of(context);
    return List.generate(items.length, (i) {
      final globalIndex = indexOffset + i;
      final isExpanded = _expanded[globalIndex] ?? false;
      final item = items[i];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => setState(() => _expanded[globalIndex] = !isExpanded),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _iconForKey(item['icon']!),
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item['question']!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          AppIcons.keyboard_arrow_down,
                          color: AppColors.textSecondary(context),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding:
                          const EdgeInsets.only(left: 48, top: 8, right: 4),
                      child: Text(
                        item['answer']!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
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
        ),
      );
    });
  }
}
