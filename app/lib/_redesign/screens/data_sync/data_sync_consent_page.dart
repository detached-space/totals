import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';

/// Full-screen consent gate shown before Data Sync can be enabled. The user
/// must explicitly acknowledge that their data will leave the device. Pops
/// `true` once consent is recorded.
class DataSyncConsentPage extends StatefulWidget {
  const DataSyncConsentPage({super.key});

  @override
  State<DataSyncConsentPage> createState() => _DataSyncConsentPageState();
}

class _DataSyncConsentPageState extends State<DataSyncConsentPage> {
  bool _acknowledged = false;
  bool _saving = false;

  static const _points = <(IconData, String, String)>[
    (
      AppIcons.upload_rounded,
      'Your data leaves your device',
      'Totals is built to stay on your device. Data Sync sends the financial '
          'records you select to a server you configure. Totals cannot see, '
          'verify, or secure that server.',
    ),
    (
      AppIcons.shield_check,
      'You choose what is sent',
      'Only records matching the rules you create are sent, using the exact '
          'fields you map. You are responsible for the destination’s security '
          'and privacy.',
    ),
    (
      AppIcons.bolt_rounded,
      'One-way export only',
      'Totals only pushes data out. It never pulls data back or changes your '
          'local records based on the server.',
    ),
    (
      AppIcons.lock_outline_rounded,
      'You stay in control',
      'You can disable Data Sync and wipe all of its settings — including saved '
          'credentials — at any time.',
    ),
  ];

  Future<void> _accept() async {
    setState(() => _saving = true);
    await DataSyncSettingsService.instance.recordConsent();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(title: const Text('Enable Data Sync')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: [
                Text(
                  'Before you turn this on',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                for (final point in _points) ...[
                  _ConsentPoint(
                    icon: point.$1,
                    title: point.$2,
                    body: point.$3,
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
                          onChanged: (v) =>
                              setState(() => _acknowledged = v ?? false),
                          activeColor: AppColors.primaryLight,
                        ),
                        Expanded(
                          child: Text(
                            'I understand my data will leave my device.',
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
                20, 8, 20, 16 + MediaQuery.of(context).padding.bottom),
            child: DataSyncPrimaryButton(
              label: 'I understand — enable',
              loading: _saving,
              onPressed: _acknowledged ? _accept : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _ConsentPoint({
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
