import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/services/advanced_settings_service.dart';

/// Consent gate shown before Telegram Backup can be enabled.
///
/// Acceptance is versioned so a future material change to what leaves the
/// device can require the user to review the disclosure again.
class TelegramBackupConsentPage extends StatefulWidget {
  const TelegramBackupConsentPage({super.key});

  @override
  State<TelegramBackupConsentPage> createState() =>
      _TelegramBackupConsentPageState();
}

class _TelegramBackupConsentPageState extends State<TelegramBackupConsentPage> {
  bool _acknowledged = false;
  bool _saving = false;

  static const _points = <(IconData, String, String)>[
    (
      AppIcons.sms_outlined,
      'Your full backup is included',
      'Backups contain your financial records and original source SMS '
          'messages retained for transactions. Failed-message diagnostics may '
          'also contain SMS text. SMS parsing patterns are not included.',
    ),
    (
      AppIcons.shield_check,
      'Encrypted before it leaves your device',
      'Totals encrypts the backup on your device. Telegram and the bot owner '
          'cannot read its contents without your recovery key.',
    ),
    (
      AppIcons.schedule_rounded,
      'Backups can be automatic',
      'After you connect a new private bot, backups start on a weekly schedule '
          'using Wi-Fi or mobile data. You can change the schedule or use '
          'manual backups.',
    ),
    (
      AppIcons.info_outline_rounded,
      'Telegram keeps the encrypted files',
      'Telegram receives the encrypted file plus service metadata such as '
          'the bot and chat identifiers, filename, size, and upload time. '
          'Uploaded backups remain in Telegram until you delete them there.',
    ),
    (
      AppIcons.lock_outline_rounded,
      'Keep your recovery key safe',
      'The recovery key is never uploaded and is the only way to open a '
          'backup on another device. Disconnecting removes local settings but '
          'does not delete files already stored by Telegram.',
    ),
  ];

  Future<void> _accept() async {
    if (_saving || !_acknowledged) return;
    setState(() => _saving = true);
    await AdvancedSettingsService.instance.recordTelegramBackupConsent();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(context.l10nText('Enable Telegram Backup')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Text(
                  context.l10nText('Before you turn this on'),
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                for (final point in _points) ...[
                  _TelegramConsentPoint(
                    icon: point.$1,
                    title: context.l10nText(point.$2),
                    body: context.l10nText(point.$3),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _acknowledged = !_acknowledged),
                  child: DataSyncCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _acknowledged,
                          onChanged: (value) => setState(
                            () => _acknowledged = value ?? false,
                          ),
                          activeColor: AppColors.primaryLight,
                        ),
                        Expanded(
                          child: Text(
                            context.l10nText(
                              'I understand that my encrypted Totals backup '
                              'will be sent to Telegram.',
                            ),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: DataSyncPrimaryButton(
              label: context.l10nText('I understand — enable'),
              loading: _saving,
              onPressed: _acknowledged ? _accept : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TelegramConsentPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _TelegramConsentPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryLight, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
