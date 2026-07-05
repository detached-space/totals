import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_consent_page.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_destination_sheet.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_log_page.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_rule_sheet.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/data_sync_scheduler.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';

class DataSyncHomePage extends StatefulWidget {
  const DataSyncHomePage({super.key});

  @override
  State<DataSyncHomePage> createState() => _DataSyncHomePageState();
}

class _DataSyncHomePageState extends State<DataSyncHomePage> {
  final _repo = DataSyncRepository();
  final _settings = DataSyncSettingsService.instance;

  bool _loading = true;
  bool _enabled = false;
  bool _syncing = false;
  bool _lastSyncRunning = false;
  List<SyncDestination> _destinations = const [];
  List<SyncRule> _rules = const [];

  @override
  void initState() {
    super.initState();
    _lastSyncRunning = SyncService.instance.status.value.running;
    SyncService.instance.status.addListener(_handleSyncStatusChanged);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.status.removeListener(_handleSyncStatusChanged);
    super.dispose();
  }

  void _handleSyncStatusChanged() {
    final running = SyncService.instance.status.value.running;
    if (_lastSyncRunning && !running) {
      unawaited(_load());
    }
    _lastSyncRunning = running;
  }

  Future<void> _load() async {
    await _settings.ensureLoaded();
    final destinations = await _repo.getDestinations();
    final rules = await _repo.getRules();
    if (!mounted) return;
    setState(() {
      _enabled = _settings.masterEnabled.value;
      _destinations = destinations;
      _rules = rules;
      _loading = false;
    });
  }

  Future<void> _toggleMaster(bool value) async {
    if (value && !_settings.hasConsent) {
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const DataSyncConsentPage()),
      );
      if (accepted != true) return;
    }
    if (!value) {
      if (mounted) setState(() => _enabled = false);
      await _settings.setMasterEnabled(false);
      await SyncService.instance.stopAll();
      await DataSyncScheduler.sync();
      if (!mounted) return;
      await _load();
      return;
    }
    await _settings.setMasterEnabled(value);
    await DataSyncScheduler.sync();
    if (!mounted) return;
    setState(() => _enabled = value);
    unawaited(SyncService.instance.requestDrain(reason: 'enabled'));
  }

  Future<void> _syncNow() async {
    final dueCount = await SyncService.instance.countDue(reason: 'manual');
    if (!mounted) return;
    if (dueCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to sync')),
      );
      return;
    }
    setState(() => _syncing = true);
    await SyncService.instance.primeProgress(
      reason: 'manual',
      total: dueCount,
    );
    await SyncService.instance.requestDrain(reason: 'manual');
    if (!mounted) return;
    setState(() => _syncing = false);
    await _load();
    if (!mounted) return;
    final st = SyncService.instance.status.value;
    final msg = st.failed > 0
        ? '${st.sent} sent · ${st.failed} failed'
        : (st.retried > 0
            ? '${st.sent} sent · ${st.retried} retrying'
            : (st.sent > 0 ? '${st.sent} synced' : 'Nothing to sync'));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addOrEditDestination([SyncDestination? existing]) async {
    final saved =
        await showDataSyncDestinationSheet(context, existing: existing);
    if (saved == true) await _load();
  }

  Future<void> _toggleDestination(SyncDestination dest, bool value) async {
    await _repo.updateDestination(dest.copyWith(enabled: value));
    await _load();
  }

  Future<void> _deleteDestination(SyncDestination dest) async {
    final confirmed = await _confirm(
      'Delete destination?',
      'This removes "${dest.name}", its rules, and its saved credentials.',
    );
    if (confirmed != true || dest.id == null) return;
    await _repo.deleteDestination(dest.id!);
    await DataSyncScheduler.sync();
    await _load();
  }

  Future<void> _addOrEditRule([SyncRule? existing]) async {
    if (_destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a destination first.')),
      );
      return;
    }
    final saved = await showDataSyncRuleSheet(
      context,
      existing: existing,
      destinations: _destinations,
    );
    if (saved == true) {
      await DataSyncScheduler.sync();
      await _load();
    }
  }

  Future<void> _toggleRule(SyncRule rule, bool value) async {
    if (!value && rule.id != null) {
      await SyncService.instance.stopRule(rule.id!);
    }
    await _repo.updateRule(rule.copyWith(enabled: value));
    await DataSyncScheduler.sync();
    if (value) unawaited(SyncService.instance.requestDrain(reason: 'rule-on'));
    await _load();
  }

  Future<void> _deleteRule(SyncRule rule) async {
    final confirmed = await _confirm(
      'Delete rule?',
      'This removes "${rule.name}" and its queued items.',
    );
    if (confirmed != true || rule.id == null) return;
    await _repo.deleteRule(rule.id!);
    await DataSyncScheduler.sync();
    await _load();
  }

  Future<void> _wipe() async {
    final confirmed = await _confirm(
      'Wipe all sync data?',
      'Deletes every destination, rule, queued item, and saved credential. '
          'This cannot be undone.',
    );
    if (confirmed != true) return;
    await _repo.wipeAll();
    await _settings.setMasterEnabled(false);
    await DataSyncScheduler.sync();
    await _load();
  }

  Future<void> _resetSyncStateForDebug() async {
    final confirmed = await _confirm(
      'Reset sync state?',
      'Debug only. Clears the synced-records store (the outbox) and re-arms '
          'every rule so it backfills and re-schedules from scratch. Your '
          'transactions are untouched.',
    );
    if (confirmed != true) return;
    await _repo.resetSyncStateForDebug();
    // Re-queue matching records for each enabled rule as *pending* (backfill
    // enqueues but does not send), so "Sync now" and the schedule both have
    // something to push.
    final rules = await _repo.getRules();
    var queued = 0;
    for (final rule in rules) {
      if (rule.enabled) {
        queued += await SyncService.instance.backfillRule(rule);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Sync store cleared — $queued record(s) re-queued.')),
    );
    await _load();
  }

  Future<bool?> _confirm(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Confirm', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(title: const Text('Data Sync')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _masterCard(),
                if (_enabled) ...[
                  const SizedBox(height: 16),
                  _syncNowButton(),
                  const SizedBox(height: 12),
                  _statusCard(),
                  const SizedBox(height: 20),
                  _destinationsSection(),
                  const SizedBox(height: 20),
                  _rulesSection(),
                  const SizedBox(height: 20),
                  DataSyncTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'Sync log',
                    subtitle: 'See what was sent, pending, or failed',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DataSyncLogPage()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _notifyToggle(),
                ],
                if (_destinations.isNotEmpty || _rules.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _wipe,
                    child: const Text('Wipe all sync data',
                        style: TextStyle(color: AppColors.red)),
                  ),
                ],
                if (kDebugMode && _enabled) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _resetSyncStateForDebug,
                    icon: const Icon(Icons.bug_report_outlined, size: 18),
                    label: const Text('Clear sync store (debug)'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _statusCard() {
    return ValueListenableBuilder<SyncRunStatus>(
      valueListenable: SyncService.instance.status,
      builder: (context, st, _) {
        final IconData icon;
        final Color color;
        final String text;
        final String? trailing;
        if (st.running) {
          icon = Icons.sync_rounded;
          color = AppColors.primaryLight;
          text = st.hasProgress ? 'Syncing ${st.fraction}' : 'Preparing sync';
          trailing = st.hasProgress ? '${st.percent}%' : null;
        } else if (!st.hasResult) {
          icon = Icons.info_outline_rounded;
          color = AppColors.slate400;
          text = 'No sync yet';
          trailing = null;
        } else if (st.failed > 0) {
          icon = Icons.error_outline_rounded;
          color = AppColors.red;
          text = '${st.sent} sent · ${st.failed} failed';
          trailing = _relativeTime(st.at!);
        } else if (st.retried > 0) {
          icon = Icons.schedule_rounded;
          color = AppColors.primaryLight;
          text = '${st.sent} sent · ${st.retried} retrying';
          trailing = _relativeTime(st.at!);
        } else if (st.sent > 0) {
          icon = Icons.check_circle_outline_rounded;
          color = AppColors.incomeSuccess;
          text = '${st.sent} synced';
          trailing = _relativeTime(st.at!);
        } else {
          icon = Icons.check_circle_outline_rounded;
          color = AppColors.slate400;
          text = 'Up to date';
          trailing = _relativeTime(st.at!);
        }
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DataSyncLogPage()),
          ),
          child: DataSyncCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _syncNowButton() {
    return ValueListenableBuilder<SyncRunStatus>(
      valueListenable: SyncService.instance.status,
      builder: (context, st, _) {
        final hasEnabledRule = _rules.any((r) => r.enabled);
        final running = st.running || _syncing;
        final label = st.running && st.hasProgress
            ? 'Syncing ${st.fraction}'
            : (running ? 'Preparing sync' : 'Sync now');
        return DataSyncPrimaryButton(
          label: label,
          icon: running ? Icons.sync_rounded : AppIcons.upload_rounded,
          onPressed: hasEnabledRule && !running ? _syncNow : null,
        );
      },
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _notifyToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: _settings.notify,
      builder: (context, value, _) {
        return DataSyncCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: value,
            activeThumbColor: AppColors.primaryLight,
            onChanged: (v) => _settings.setNotify(v),
            title: Text(
              'Notify me about syncs',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'A quiet notification when a sync finishes; failures alert.',
              style: TextStyle(
                  color: AppColors.textTertiary(context), fontSize: 12),
            ),
          ),
        );
      },
    );
  }

  Widget _masterCard() {
    return DataSyncCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sync my data to a backend',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _enabled,
                activeThumbColor: AppColors.primaryLight,
                onChanged: _toggleMaster,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Advanced, off by default. Pushes the records you choose to a '
            'server you configure. Your data leaves your device — one-way only.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _destinationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: DataSyncSectionHeader('Destinations')),
            TextButton.icon(
              onPressed: () => _addOrEditDestination(),
              icon: const Icon(AppIcons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_destinations.isEmpty)
          DataSyncCard(
            child: Text(
              'No destinations yet. Add the server you want to send data to.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
        for (final dest in _destinations) ...[
          DataSyncTile(
            icon: AppIcons.cloud_download,
            iconColor:
                dest.enabled ? AppColors.primaryLight : AppColors.slate400,
            title: dest.name,
            subtitle: '${dest.authType.label} · ${_host(dest.baseUrl)}',
            onTap: () => _addOrEditDestination(dest),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: dest.enabled,
                  activeThumbColor: AppColors.primaryLight,
                  onChanged: (v) => _toggleDestination(dest, v),
                ),
                IconButton(
                  onPressed: () => _deleteDestination(dest),
                  icon: const Icon(AppIcons.delete_outline_rounded,
                      color: AppColors.red, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _rulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: DataSyncSectionHeader('Rules')),
            TextButton.icon(
              onPressed: () => _addOrEditRule(),
              icon: const Icon(AppIcons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_rules.isEmpty)
          DataSyncCard(
            child: Text(
              'No rules yet. A rule decides which records go to which '
              'destination, and when.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
        for (final rule in _rules) ...[
          DataSyncTile(
            icon: AppIcons.bolt_rounded,
            iconColor:
                rule.enabled ? AppColors.primaryLight : AppColors.slate400,
            title: rule.name,
            subtitle: '${rule.entity.label} → ${_destName(rule.destinationId)}',
            onTap: () => _addOrEditRule(rule),
            trailing: _ruleTrailing(rule),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _ruleTrailing(SyncRule rule) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rule.lastStatus != null) DataSyncStatusPill(rule.lastStatus!),
        Switch.adaptive(
          value: rule.enabled,
          activeThumbColor: AppColors.primaryLight,
          onChanged: (v) => _toggleRule(rule, v),
        ),
        IconButton(
          onPressed: () => _deleteRule(rule),
          icon: const Icon(
            AppIcons.delete_outline_rounded,
            color: AppColors.red,
            size: 20,
          ),
        ),
      ],
    );
  }

  String _host(String url) {
    return Uri.tryParse(url)?.host ?? url;
  }

  String _destName(int destinationId) {
    final match = _destinations.where((d) => d.id == destinationId);
    return match.isEmpty ? 'Unknown' : match.first.name;
  }
}
