import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_home_page.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/screens/telegram_backup_consent_page.dart';
import 'package:totals/_redesign/screens/telegram_backup_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/services/advanced_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_scheduler.dart';
import 'package:totals/services/transaction_location_capture_service.dart';

class RedesignAdvancedSettingsPage extends StatefulWidget {
  const RedesignAdvancedSettingsPage({super.key});

  @override
  State<RedesignAdvancedSettingsPage> createState() =>
      _RedesignAdvancedSettingsPageState();
}

class _RedesignAdvancedSettingsPageState
    extends State<RedesignAdvancedSettingsPage> {
  ProfileDoubleTapAction _selected = ProfileDoubleTapAction.lock;
  Set<ToolsFabItem> _visibleTools =
      AdvancedSettingsService.defaultToolsFabItems;
  bool _telegramBackupEnabled = false;
  bool _spendingMapEnabled = false;
  bool _updatingSpendingMap = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AdvancedSettingsService.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _selected = AdvancedSettingsService.instance.profileDoubleTapAction.value;
      _visibleTools = AdvancedSettingsService.instance.toolsFabItems.value;
      _telegramBackupEnabled =
          AdvancedSettingsService.instance.telegramBackupEnabled.value;
      _spendingMapEnabled =
          AdvancedSettingsService.instance.spendingMapEnabled.value;
      _loading = false;
    });
  }

  Future<bool> _confirmSpendingMapDisclosure() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10nText('Enable Spending Map?')),
            content: Text(
              ctx.l10nText(
                'Totals will capture your precise location when a new debit '
                'or credit transaction is recorded. With background '
                'permission, this also works for bank SMS transactions while '
                'the app is not open. Coordinates are stored in the local app '
                'database and are included in manual exports and encrypted '
                'full backups. Custom place names you create are stored with '
                'those locations and included in the same exports and '
                'backups. Google Maps supplies the base map and receives the '
                'visible map area and normal map interactions under Google\'s '
                'privacy terms. Totals does not send your transaction amounts, '
                'account details, or custom place names to Google.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10nText('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10nText('Continue')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _setSpendingMapEnabled(bool enabled) async {
    if (_updatingSpendingMap || enabled == _spendingMapEnabled) return;
    setState(() => _updatingSpendingMap = true);

    LocationCapturePermission? permission;
    try {
      if (enabled) {
        final accepted = await _confirmSpendingMapDisclosure();
        if (!accepted || !mounted) return;
        permission = await TransactionLocationCaptureService.instance
            .requestPermissionForCapture();
        if (!mounted) return;
        if (!permission.canCapture) {
          final message = switch (permission) {
            LocationCapturePermission.serviceDisabled =>
              'Turn on device location to enable Spending Map.',
            LocationCapturePermission.permanentlyDenied =>
              'Location access is blocked. Allow it in system settings.',
            LocationCapturePermission.denied =>
              'Location access is required for Spending Map.',
            _ => 'Location is unavailable on this device.',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10nTextRead(message)),
              action: permission == LocationCapturePermission.serviceDisabled ||
                      permission == LocationCapturePermission.permanentlyDenied
                  ? SnackBarAction(
                      label: context.l10nTextRead('Settings'),
                      onPressed: () async {
                        await TransactionLocationCaptureService.instance
                            .openSettingsFor(permission!);
                      },
                    )
                  : null,
            ),
          );
          return;
        }
      }

      await AdvancedSettingsService.instance.setSpendingMapEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _spendingMapEnabled = enabled;
        _visibleTools = AdvancedSettingsService.instance.toolsFabItems.value;
      });

      if (enabled && permission != null && !permission.canCaptureInBackground) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10nTextRead(
                'Spending Map is enabled for foreground transactions. '
                'Choose “Allow all the time” in system settings to capture '
                'background SMS transactions.',
              ),
            ),
            action: SnackBarAction(
              label: context.l10nTextRead('Settings'),
              onPressed: () async {
                await TransactionLocationCaptureService.instance
                    .openSettingsFor(permission!);
              },
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead('Could not update Spending Map.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingSpendingMap = false);
    }
  }

  Future<void> _setTelegramBackupEnabled(bool enabled) async {
    if (enabled) {
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const TelegramBackupConsentPage(),
        ),
      );
      if (!mounted || accepted != true) return;
    }

    setState(() => _telegramBackupEnabled = enabled);
    try {
      await AdvancedSettingsService.instance.setTelegramBackupEnabled(enabled);
      await TelegramBackupScheduler.sync();
      if (enabled && mounted) _openTelegramBackup();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _telegramBackupEnabled =
            AdvancedSettingsService.instance.telegramBackupEnabled.value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead(
              'Could not update the Telegram Backup setting.',
            ),
          ),
        ),
      );
    }
  }

  void _openTelegramBackup() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TelegramBackupPage(),
      ),
    );
  }

  Future<void> _openActionPicker() async {
    final picked = await showModalBottomSheet<ProfileDoubleTapAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 20 + MediaQuery.of(ctx).padding.bottom),
          decoration: BoxDecoration(
            color: AppColors.cardColor(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              _OptionTile(
                title: ctx.l10nText('Lock app'),
                selected: _selected == ProfileDoubleTapAction.lock,
                onTap: () => Navigator.pop(ctx, ProfileDoubleTapAction.lock),
              ),
              const SizedBox(height: 8),
              _OptionTile(
                title: ctx.l10nText('Do nothing'),
                selected: _selected == ProfileDoubleTapAction.doNothing,
                onTap: () =>
                    Navigator.pop(ctx, ProfileDoubleTapAction.doNothing),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null || picked == _selected) return;
    await AdvancedSettingsService.instance.setProfileDoubleTapAction(picked);
    if (!mounted) return;
    setState(() => _selected = picked);
  }

  Future<void> _openToolsFabPicker() async {
    final availableTools =
        AdvancedSettingsService.instance.availableToolsFabItems;
    final picked = await showModalBottomSheet<Set<ToolsFabItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var draft = Set<ToolsFabItem>.of(_visibleTools);
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void toggle(ToolsFabItem item) {
              if (item == ToolsFabItem.spendingMap) return;
              final isSelected = draft.contains(item);
              if (isSelected && draft.length == 1) return;
              setSheetState(() {
                draft = Set<ToolsFabItem>.of(draft);
                isSelected ? draft.remove(item) : draft.add(item);
              });
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                20 + MediaQuery.of(ctx).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardColor(ctx),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ctx.l10nText('Tools button'),
                          style: TextStyle(
                            color: AppColors.textPrimary(ctx),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${draft.length}/${availableTools.length}',
                        style: TextStyle(
                          color: AppColors.textSecondary(ctx),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final item in availableTools) ...[
                    _ToolsFabOptionTile(
                      icon: _toolsFabIcon(item),
                      color: AppColors.primaryLight,
                      title: _toolsFabLabel(ctx, item),
                      selected: draft.contains(item),
                      canToggle: item != ToolsFabItem.spendingMap &&
                          (draft.length > 1 || !draft.contains(item)),
                      onTap: () => toggle(item),
                    ),
                    if (item != availableTools.last) const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, draft),
                      child: Text(ctx.l10nText('Done')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (picked == null || _sameToolsSelection(picked, _visibleTools)) return;
    await AdvancedSettingsService.instance.setToolsFabItems(picked);
    if (!mounted) return;
    setState(() {
      _visibleTools = AdvancedSettingsService.instance.toolsFabItems.value;
    });
  }

  bool _sameToolsSelection(Set<ToolsFabItem> left, Set<ToolsFabItem> right) {
    if (left.length != right.length) return false;
    return left.every(right.contains);
  }

  String _toolsFabSummary(BuildContext context) {
    final availableCount =
        AdvancedSettingsService.instance.availableToolsFabItems.length;
    if (_visibleTools.length == availableCount) {
      return context.l10nText('All tools');
    }
    return '${_visibleTools.length} ${context.l10nText('tools shown')}';
  }

  String _toolsFabLabel(BuildContext context, ToolsFabItem item) {
    switch (item) {
      case ToolsFabItem.quickAccounts:
        return context.l10nText('Quick Accounts');
      case ToolsFabItem.verifyPayments:
        return context.l10nText('Verify Payments');
      case ToolsFabItem.loans:
        return context.l10nText('Loans');
      case ToolsFabItem.spendingMap:
        return context.l10nText('Spending Map');
      case ToolsFabItem.failedParsings:
        return context.l10nText('Failed Parsings');
      case ToolsFabItem.dataSync:
        return context.l10nText('Data Sync');
      case ToolsFabItem.webDashboard:
        return context.l10nText('Web Dashboard');
    }
  }

  IconData _toolsFabIcon(ToolsFabItem item) {
    switch (item) {
      case ToolsFabItem.quickAccounts:
        return AppIcons.account_balance_outlined;
      case ToolsFabItem.verifyPayments:
        return AppIcons.qr_code_scanner_rounded;
      case ToolsFabItem.loans:
        return AppIcons.debts;
      case ToolsFabItem.spendingMap:
        return AppIcons.map_rounded;
      case ToolsFabItem.failedParsings:
        return AppIcons.sms_outlined;
      case ToolsFabItem.dataSync:
        return AppIcons.cloud_download;
      case ToolsFabItem.webDashboard:
        return AppIcons.dashboard_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Advanced')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                DataSyncTile(
                  icon: AppIcons.cloud_download,
                  title: context.l10nText('Data Sync'),
                  subtitle: context
                      .l10nText('Send your data to a backend you choose'),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DataSyncHomePage(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DataSyncTile(
                  icon: AppIcons.upload_rounded,
                  title: context.l10nText('Telegram Backup'),
                  subtitle: context.l10nText(
                    'Show encrypted Telegram backups in Settings',
                  ),
                  trailing: Switch(
                    value: _telegramBackupEnabled,
                    activeThumbColor: AppColors.primaryLight,
                    onChanged: _setTelegramBackupEnabled,
                  ),
                  onTap: _telegramBackupEnabled
                      ? _openTelegramBackup
                      : () => _setTelegramBackupEnabled(true),
                ),
                const SizedBox(height: 12),
                DataSyncTile(
                  icon: AppIcons.map_rounded,
                  title: context.l10nText('Spending Map'),
                  subtitle: context.l10nText(
                    'Keep debit and credit locations locally and view them on '
                    'a map',
                  ),
                  trailing: _updatingSpendingMap
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch(
                          value: _spendingMapEnabled,
                          activeThumbColor: AppColors.primaryLight,
                          onChanged: _setSpendingMapEnabled,
                        ),
                  onTap: () => _setSpendingMapEnabled(!_spendingMapEnabled),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: InkWell(
                    onTap: _openActionPicker,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryLight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            AppIcons.person_outline_rounded,
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
                                'Profile double tap',
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selected == ProfileDoubleTapAction.lock
                                    ? 'Lock app'
                                    : 'Do nothing',
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcons.chevron_right_rounded,
                          color: AppColors.textTertiary(context),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: InkWell(
                    onTap: _openToolsFabPicker,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryLight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            AppIcons.grid_view_outlined,
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
                                context.l10nText('Tools button'),
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _toolsFabSummary(context),
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcons.chevron_right_rounded,
                          color: AppColors.textTertiary(context),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.12)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  AppIcons.check_rounded,
                  color: AppColors.primaryLight,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolsFabOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final bool selected;
  final bool canToggle;
  final VoidCallback onTap;

  const _ToolsFabOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.selected,
    required this.canToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: canToggle ? 1 : 0.62,
      child: Material(
        color: selected
            ? color.withValues(alpha: AppColors.isDark(context) ? 0.18 : 0.1)
            : AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: canToggle ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: AppColors.isDark(context) ? 0.2 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Checkbox(
                  value: selected,
                  onChanged: canToggle ? (_) => onTap() : null,
                  checkColor: AppColors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return color;
                    return Colors.transparent;
                  }),
                  side: BorderSide(color: AppColors.borderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
