import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/widgets/telegram_recovery_key_dialog.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/data_export_import_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_models.dart';
import 'package:totals/services/telegram_backup/telegram_backup_scheduler.dart';
import 'package:totals/services/telegram_backup/telegram_backup_service.dart';
import 'package:totals/services/telegram_backup/telegram_backup_settings_service.dart';
import 'package:totals/widgets/data_import_options_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramBackupPage extends StatefulWidget {
  const TelegramBackupPage({super.key});

  @override
  State<TelegramBackupPage> createState() => _TelegramBackupPageState();
}

class _TelegramBackupPageState extends State<TelegramBackupPage> {
  final TelegramBackupService _service = TelegramBackupService.instance;
  final TelegramBackupSettingsService _settings =
      TelegramBackupSettingsService.instance;
  final DataExportImportService _exportImportService =
      DataExportImportService();
  final TextEditingController _tokenController = TextEditingController();

  TelegramBackupConfig? _config;
  List<TelegramBackupEntry> _backups = const [];
  bool _loading = true;
  bool _connecting = false;
  bool _tokenVisible = false;
  bool _creatingBackup = false;
  bool _refreshing = false;
  String? _restoringId;
  String? _catalogError;
  TimeOfDay _summaryTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _settings.ensureLoaded();
    final summaryTime =
        await NotificationSettingsService.instance.getDailySummaryTime();
    if (!mounted) return;
    setState(() {
      _config = _settings.config.value;
      _summaryTime = summaryTime;
      _loading = false;
    });
    if (_config != null) await _refreshBackups();
  }

  Future<void> _refreshBackups() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _catalogError = null;
    });
    try {
      final backups = await _service.listBackups();
      await _settings.reload();
      if (!mounted) return;
      setState(() {
        _config = _settings.config.value;
        _backups = backups;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = _message(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    FocusScope.of(context).unfocus();
    setState(() => _connecting = true);
    try {
      final session = await _service.beginPairing(_tokenController.text);
      if (!mounted) return;

      final pairingFuture = _service.waitForPairing(session);
      // Pairing starts before Telegram opens so the bot can acknowledge /start
      // while the user is still in that chat. Keep cancellation/error paths
      // handled even if the user closes the instruction dialog.
      unawaited(
        pairingFuture.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      );

      var opened = false;
      try {
        opened = await launchUrl(
          session.deepLink,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) opened = await launchUrl(session.deepLink);
      } catch (_) {}
      if (!mounted) return;
      final shouldWait = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            dialogContext.l10nText('Finish in Telegram'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dialogContext.l10nText(
                  opened
                      ? 'Tap Start in the private bot chat. When the bot '
                          'confirms your chat, return to Totals to finish setup.'
                      : 'Open the bot link in Telegram and tap Start. When the '
                          'bot confirms your chat, return to Totals.',
                ),
              ),
              if (!opened) ...[
                const SizedBox(height: 12),
                SelectableText(
                  session.deepLink.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10nText('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10nText('Continue in Totals')),
            ),
          ],
        ),
      );
      if (shouldWait != true || !mounted) return;

      final chat = await pairingFuture;
      if (!mounted) return;
      final result = await _finishPairing(session, chat);
      if (result == null || !mounted) return;

      _tokenController.clear();
      await TelegramBackupScheduler.sync();
      setState(() {
        _config = result.config;
        _backups = const [];
        _catalogError = null;
      });
      if (result.shouldShowRecoveryKey) {
        await _showRecoveryKey(
          result.recoveryKey,
          firstTime: true,
        );
      }
      if (!result.createdNewCatalog && mounted) {
        _showSnack(
          context.l10nTextRead(
            'Connected. Automatic backups are off on this device to avoid '
            'duplicates with an older device.',
          ),
        );
      }
      if (mounted) await _refreshBackups();
    } catch (error) {
      if (mounted) _showError(_message(error));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<TelegramConnectionResult?> _finishPairing(
    TelegramPairingSession session,
    TelegramChatIdentity chat,
  ) async {
    String? recoveryKey;
    while (mounted) {
      try {
        return await _service.finishPairing(
          session: session,
          chat: chat,
          recoveryKey: recoveryKey,
        );
      } on TelegramRecoveryKeyRequiredException {
        recoveryKey = await _askForRecoveryKey();
        if (recoveryKey == null) return null;
      } on TelegramRecoveryKeyInvalidException catch (error) {
        recoveryKey = await _askForRecoveryKey(error: error.message);
        if (recoveryKey == null) return null;
      }
    }
    return null;
  }

  Future<String?> _askForRecoveryKey({String? error}) async {
    return showTelegramRecoveryKeyDialog(
      context: context,
      title: context.l10nTextRead('Recovery key needed'),
      description: context.l10nTextRead(
        'Totals found an existing encrypted backup index in this '
        'chat. Enter its recovery key to show those backups.',
      ),
      recoveryKeyLabel: context.l10nTextRead('Recovery key'),
      invalidKeyMessage: context.l10nTextRead(
        'Enter the 64-character Totals recovery key.',
      ),
      chooseFileLabel: context.l10nTextRead('Upload recovery key .txt'),
      invalidFileMessage: context.l10nTextRead(
        'That file does not contain a valid Totals recovery key.',
      ),
      fileReadErrorMessage: context.l10nTextRead(
        'Could not read the recovery key file.',
      ),
      cancelLabel: context.l10nTextRead('Cancel'),
      connectLabel: context.l10nTextRead('Connect'),
      error: error,
    );
  }

  Future<void> _createBackup() async {
    if (_creatingBackup) return;
    setState(() => _creatingBackup = true);
    try {
      await _service.backupNow();
      if (!mounted) return;
      _showSnack(context.l10nTextRead('Encrypted backup sent to Telegram'));
      await _refreshBackups();
    } catch (error) {
      if (mounted) _showError(_message(error));
    } finally {
      if (mounted) {
        setState(() {
          _creatingBackup = false;
          _config = _settings.config.value;
        });
      }
    }
  }

  Future<void> _restore(TelegramBackupEntry entry) async {
    if (_restoringId != null) return;
    setState(() => _restoringId = entry.id);
    try {
      final jsonData = await _service.downloadBackup(entry);
      final summary = DataExportImportService.inspectImportPayload(jsonData);
      if (!mounted) return;
      final options = await showDataImportOptionsSheet(
        context: context,
        summary: summary,
      );
      if (options == null || !mounted) return;
      await _exportImportService.importAllData(jsonData, options: options);
      if (!mounted) return;
      try {
        await Provider.of<TransactionProvider>(
          context,
          listen: false,
        ).loadData();
      } catch (_) {}
      if (mounted) {
        _showSnack(context.l10nTextRead('Data imported successfully'));
      }
    } catch (error) {
      if (mounted) {
        _showError(
          '${context.l10nTextRead('Import failed')}: ${_message(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  Future<void> _openAllBackups() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TelegramBackupsPage(
          backups: List<TelegramBackupEntry>.unmodifiable(_backups),
          onRestore: _restore,
        ),
      ),
    );
  }

  Future<void> _changeSchedule(TelegramBackupSchedule? schedule) async {
    if (schedule == null) return;
    await _service.setSchedule(schedule);
    await TelegramBackupScheduler.sync();
    if (mounted) setState(() => _config = _settings.config.value);
  }

  Future<void> _revealRecoveryKey() async {
    try {
      final key = await _service.formattedRecoveryKey();
      if (mounted) await _showRecoveryKey(key);
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<void> _showRecoveryKey(
    String recoveryKey, {
    bool firstTime = false,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !firstTime,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10nText(
            firstTime ? 'Save your recovery key' : 'Recovery key',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dialogContext.l10nText(
                'This key is the only way to open your Telegram backups on '
                'another device. Totals never sends it to Telegram.',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(dialogContext),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.borderColor(dialogContext),
                ),
              ),
              child: SelectableText(
                recoveryKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              dialogContext.l10nText(
                'Keep it somewhere separate from this phone. Anyone with the '
                'key and bot access can read the backups.',
              ),
              style: TextStyle(
                color: AppColors.textSecondary(dialogContext),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: recoveryKey));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      dialogContext.l10nTextRead('Recovery key copied'),
                    ),
                  ),
                );
              }
            },
            icon: const Icon(AppIcons.copy, size: 18),
            label: Text(dialogContext.l10nText('Copy')),
          ),
          TextButton.icon(
            onPressed: () => _saveRecoveryKey(recoveryKey),
            icon: const Icon(AppIcons.download_rounded, size: 18),
            label: Text(dialogContext.l10nText('Save')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10nText('Done')),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecoveryKey(String recoveryKey) async {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final fileName = 'totals_telegram_recovery_key_'
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}.txt';
    final contents = [
      'Totals Telegram Backup recovery key',
      '',
      recoveryKey,
      '',
      'Keep this file private and separate from your phone.',
      'Totals cannot recover this key for you.',
    ].join('\n');

    try {
      final bytes = Uint8List.fromList(utf8.encode(contents));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Totals recovery key',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );
      if (path == null || path.isEmpty) return;
      // Android/iOS write the supplied bytes through the system document
      // picker. Desktop implementations return a normal path for us to write.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        _showSnack(
          context.l10nTextRead('Recovery key saved'),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(
          '${context.l10nTextRead('Could not save')}: ${_message(error)}',
        );
      }
    }
  }

  Future<void> _openBot() async {
    final config = _config;
    if (config == null) return;
    await _openTelegramChat(config.botUsername);
  }

  Future<void> _openBotFather() => _openTelegramChat('BotFather');

  Future<void> _openTelegramChat(String username) async {
    final normalizedUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (normalizedUsername.isEmpty) return;
    final uri = Uri.https('t.me', '/$normalizedUsername');
    try {
      var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) opened = await launchUrl(uri);
      if (!opened && mounted) {
        _showError(
          context.l10nTextRead('Could not open Telegram.'),
        );
      }
    } catch (_) {
      if (mounted) {
        _showError(
          context.l10nTextRead('Could not open Telegram.'),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10nText('Disconnect Telegram Backup?')),
        content: Text(
          dialogContext.l10nText(
            'Backups stay in Telegram. To reconnect on this or another '
            'device, you will need the bot token and recovery key.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10nText('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10nText('Disconnect')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.disconnect();
    await TelegramBackupScheduler.sync();
    if (!mounted) return;
    setState(() {
      _config = null;
      _backups = const [];
      _catalogError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Telegram Backup')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _config == null
              ? _buildSetup()
              : _buildConnected(_config!),
    );
  }

  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        DataSyncCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10nText(
                        'Automatic, private backups in your own bot chat',
                      ),
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                context.l10nText(
                  'Totals encrypts each backup on this device before it is '
                  'sent. Telegram and the bot owner cannot read the contents '
                  'without your recovery key. Full backups include original '
                  'source SMS messages retained for your transactions.',
                ),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DataSyncSectionHeader(context.l10nText('Connect your bot')),
        DataSyncCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SetupStep(
                number: 1,
                text: context.l10nText(
                  'Create a new private bot with @BotFather in Telegram.',
                ),
                linkedText: '@BotFather',
                linkKey: const Key('telegram-backup-botfather-link'),
                onLinkedTextTap: _openBotFather,
              ),
              const SizedBox(height: 12),
              _SetupStep(
                number: 2,
                text: context.l10nText(
                  'Copy the HTTP API token BotFather gives you and paste it '
                  'below.',
                ),
              ),
              const SizedBox(height: 12),
              _SetupStep(
                number: 3,
                text: context.l10nText(
                  'Totals opens the bot. Tap Start once to pair your private '
                  'chat.',
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _tokenController,
                obscureText: !_tokenVisible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.l10nText('Bot token'),
                  hintText: '123456789:AA…',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _tokenVisible = !_tokenVisible),
                    icon: Icon(
                      _tokenVisible
                          ? AppIcons.visibility_off_outlined
                          : AppIcons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text(
                    context.l10nText(
                      _connecting ? 'Connecting…' : 'Connect Telegram bot',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10nText(
            'A new backup space starts with daily backups over Wi-Fi or mobile '
            'data. When reconnecting an existing space, scheduling stays off '
            'until you turn it on.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildConnected(TelegramBackupConfig config) {
    return RefreshIndicator(
      onRefresh: _refreshBackups,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          DataSyncCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.incomeSuccess.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: AppColors.incomeSuccess,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@${config.botUsername}',
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${context.l10nText('Private chat')}: '
                            '${config.chatDisplayName}',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10nText('Open Telegram'),
                      onPressed: _openBot,
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _creatingBackup ? null : _createBackup,
                    icon: _creatingBackup
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(AppIcons.upload_rounded),
                    label: Text(
                      context.l10nText(
                        _creatingBackup
                            ? 'Encrypting and sending…'
                            : 'Back up now',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10nText(
                    'Full backups include original source SMS messages '
                    'retained for your transactions.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                if (config.lastBackupAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${context.l10nText('Last backup')}: '
                    '${_formatTelegramBackupDate(
                      context,
                      config.lastBackupAt!,
                    )}',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (config.lastBackupError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    config.lastBackupError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          DataSyncSectionHeader(context.l10nText('Automatic backups')),
          DataSyncCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10nText('Schedule'),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _scheduleDescription(config.schedule),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.l10nText(
                              'Uses Wi-Fi or mobile data when a backup is due',
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DropdownButton<TelegramBackupSchedule>(
                      value: config.schedule,
                      underline: const SizedBox.shrink(),
                      onChanged: _changeSchedule,
                      items: [
                        for (final schedule in TelegramBackupSchedule.values)
                          DropdownMenuItem(
                            value: schedule,
                            child: Text(_scheduleLabel(schedule)),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DataSyncTile(
            icon: Icons.key_rounded,
            title: context.l10nText('Recovery key'),
            subtitle: context.l10nText('Reveal, copy, or save your key'),
            showChevron: true,
            onTap: _revealRecoveryKey,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DataSyncSectionHeader(
                  context.l10nText('Backups in Telegram'),
                ),
              ),
              if (_refreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: context.l10nText('Refresh'),
                  onPressed: _refreshBackups,
                  icon: const Icon(AppIcons.refresh, size: 20),
                ),
            ],
          ),
          if (_catalogError != null)
            _ErrorCard(
              message: _catalogError!,
              onRetry: _refreshBackups,
            )
          else if (_backups.isEmpty && !_refreshing)
            DataSyncCard(
              child: Column(
                children: [
                  Icon(
                    AppIcons.cloud_download,
                    color: AppColors.textTertiary(context),
                    size: 30,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10nText('No backups yet'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10nText(
                      'Tap Back up now to create the first encrypted backup.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            TelegramBackupListPreview(
              backups: _backups,
              restoringId: _restoringId,
              onRestore: _restore,
              onShowMore: _openAllBackups,
            ),
          const SizedBox(height: 22),
          TextButton(
            onPressed: _disconnect,
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(context.l10nText('Disconnect Telegram Backup')),
          ),
        ],
      ),
    );
  }

  String _scheduleLabel(TelegramBackupSchedule schedule) {
    switch (schedule) {
      case TelegramBackupSchedule.manual:
        return context.l10nText('Manual');
      case TelegramBackupSchedule.daily:
        return context.l10nText('Daily');
      case TelegramBackupSchedule.weekly:
        return context.l10nText('Weekly');
    }
  }

  String _scheduleDescription(TelegramBackupSchedule schedule) {
    final formattedTime =
        MaterialLocalizations.of(context).formatTimeOfDay(_summaryTime);
    switch (schedule) {
      case TelegramBackupSchedule.manual:
        return context.l10nText('Create backups whenever you choose');
      case TelegramBackupSchedule.daily:
        return '${context.l10nText('After your daily summary time')} · '
            '$formattedTime';
      case TelegramBackupSchedule.weekly:
        return '${context.l10nText('Sundays after')} $formattedTime';
    }
  }

  String _message(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.red,
      ),
    );
  }
}

class TelegramBackupListPreview extends StatelessWidget {
  static const int visibleBackupCount = 4;

  final List<TelegramBackupEntry> backups;
  final String? restoringId;
  final Future<void> Function(TelegramBackupEntry entry) onRestore;
  final VoidCallback onShowMore;

  const TelegramBackupListPreview({
    super.key,
    required this.backups,
    required this.restoringId,
    required this.onRestore,
    required this.onShowMore,
  });

  @override
  Widget build(BuildContext context) {
    final visibleBackups = backups.take(visibleBackupCount);
    return Column(
      children: [
        for (final backup in visibleBackups) ...[
          _BackupTile(
            entry: backup,
            dateLabel: _formatTelegramBackupDate(context, backup.createdAt),
            sizeLabel: _formatTelegramBackupBytes(backup.fileSize),
            restoring: restoringId == backup.id,
            restoreEnabled: restoringId == null,
            onRestore: () => onRestore(backup),
          ),
          const SizedBox(height: 10),
        ],
        if (backups.length > visibleBackupCount)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const Key('telegram-backups-show-more'),
              onPressed: onShowMore,
              child: Text(context.l10nText('Show more backups')),
            ),
          ),
      ],
    );
  }
}

class TelegramBackupsPage extends StatefulWidget {
  final List<TelegramBackupEntry> backups;
  final Future<void> Function(TelegramBackupEntry entry) onRestore;

  const TelegramBackupsPage({
    super.key,
    required this.backups,
    required this.onRestore,
  });

  @override
  State<TelegramBackupsPage> createState() => _TelegramBackupsPageState();
}

class _TelegramBackupsPageState extends State<TelegramBackupsPage> {
  String? _restoringId;

  Future<void> _restore(TelegramBackupEntry entry) async {
    if (_restoringId != null) return;
    setState(() => _restoringId = entry.id);
    try {
      await widget.onRestore(entry);
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Backups in Telegram')),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: widget.backups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final backup = widget.backups[index];
          return _BackupTile(
            entry: backup,
            dateLabel: _formatTelegramBackupDate(context, backup.createdAt),
            sizeLabel: _formatTelegramBackupBytes(backup.fileSize),
            restoring: _restoringId == backup.id,
            restoreEnabled: _restoringId == null,
            onRestore: () => _restore(backup),
          );
        },
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  final int number;
  final String text;
  final String? linkedText;
  final Key? linkKey;
  final VoidCallback? onLinkedTextTap;

  const _SetupStep({
    required this.number,
    required this.text,
    this.linkedText,
    this.linkKey,
    this.onLinkedTextTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: AppColors.textSecondary(context),
      height: 1.4,
    );
    final linkStart = linkedText == null ? -1 : text.indexOf(linkedText!);
    final textWidget = linkStart < 0
        ? Text(text, style: textStyle)
        : Text.rich(
            TextSpan(
              style: textStyle,
              children: [
                TextSpan(text: text.substring(0, linkStart)),
                TextSpan(
                  text: linkedText,
                  style: const TextStyle(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
                TextSpan(
                  text: text.substring(linkStart + linkedText!.length),
                ),
              ],
            ),
          );
    final linkedTextWidget = onLinkedTextTap == null || linkStart < 0
        ? textWidget
        : Semantics(
            link: true,
            label: text,
            child: InkWell(
              key: linkKey,
              onTap: onLinkedTextTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: textWidget,
              ),
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.primaryDark,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: linkedTextWidget),
      ],
    );
  }
}

class _BackupTile extends StatelessWidget {
  final TelegramBackupEntry entry;
  final String dateLabel;
  final String sizeLabel;
  final bool restoring;
  final bool restoreEnabled;
  final VoidCallback onRestore;

  const _BackupTile({
    required this.entry,
    required this.dateLabel,
    required this.sizeLabel,
    required this.restoring,
    required this.restoreEnabled,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return DataSyncCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              AppIcons.cloud_download,
              color: AppColors.primaryLight,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sizeLabel · Schema v${entry.exportSchemaVersion}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: restoring || !restoreEnabled ? null : onRestore,
            child: restoring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10nText('Restore')),
          ),
        ],
      ),
    );
  }
}

String _formatTelegramBackupDate(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} · '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _formatTelegramBackupBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return DataSyncCard(
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.red),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(context.l10nText('Retry')),
          ),
        ],
      ),
    );
  }
}
