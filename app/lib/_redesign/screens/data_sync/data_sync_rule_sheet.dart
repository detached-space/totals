import 'dart:async';

import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/profile.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/data_sync_scheduler.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';

/// Opens the full-screen, step-by-step rule editor. Returns true if saved.
Future<bool?> showDataSyncRuleSheet(
  BuildContext context, {
  SyncRule? existing,
  required List<SyncDestination> destinations,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _RuleWizardPage(existing: existing, destinations: destinations),
    ),
  );
}

enum _WhenMode { realtime, interval, daily, manual }

class _MapRow {
  String totalsField;
  final TextEditingController backend;
  _MapRow(this.totalsField, String backendValue)
      : backend = TextEditingController(text: backendValue);
}

class _RuleWizardPage extends StatefulWidget {
  final SyncRule? existing;
  final List<SyncDestination> destinations;
  const _RuleWizardPage({this.existing, required this.destinations});

  @override
  State<_RuleWizardPage> createState() => _RuleWizardPageState();
}

class _RuleWizardPageState extends State<_RuleWizardPage> {
  final _repo = DataSyncRepository();
  static const int _allProfilesValue = -1;
  static const _stepTitles = [
    'Basics',
    'Where it goes',
    'Filter & fields',
    'When to sync',
  ];

  int _step = 0;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _pathCtrl;
  final _minAmtCtrl = TextEditingController();
  final _maxAmtCtrl = TextEditingController();

  SyncEntity _entity = SyncEntity.transactions;
  int? _destinationId;
  String _typeFilter = 'any'; // any | CREDIT | DEBIT
  bool _activeOnly = false;
  String _method = 'POST';
  SyncBatchMode _batchMode = SyncBatchMode.perRecord;
  bool _sendUnmapped = false;
  final List<_MapRow> _mappings = [];
  bool _saving = false;

  // Profile/bank/account selection. Loaded independent of the active profile.
  List<Profile> _profiles = const [];
  int? _selectedProfileId;
  List<Account> _allAccounts = const [];
  List<Account> _accounts = const [];
  Map<int, Bank> _banksById = const {};
  bool _loadingAccounts = true;
  final Set<int> _selectedBankIds = {};
  final Set<String> _selectedAccountKeys = {};

  // When to sync.
  _WhenMode _whenMode = _WhenMode.realtime;
  bool _alsoOnReconnect = false;
  int _scheduleInterval = 60;
  final List<String> _scheduleTimes = [];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _pathCtrl = TextEditingController(text: e?.pathTemplate ?? '/');
    _destinationId = e?.destinationId ??
        (widget.destinations.isNotEmpty ? widget.destinations.first.id : null);
    if (e != null) {
      _entity = e.entity;
      _method = e.method;
      _batchMode = e.batchMode;
      _sendUnmapped = e.sendUnmapped;
      _alsoOnReconnect = e.triggerOnConnectivity;
      if (e.triggerOnNewTxn) {
        _whenMode = _WhenMode.realtime;
      } else if (e.scheduleMode == SyncScheduleMode.interval) {
        _whenMode = _WhenMode.interval;
      } else if (e.scheduleMode == SyncScheduleMode.daily) {
        _whenMode = _WhenMode.daily;
      } else {
        _whenMode = _WhenMode.manual;
      }
      if (e.scheduleIntervalMinutes != null) {
        _scheduleInterval = e.scheduleIntervalMinutes!;
      }
      _scheduleTimes.addAll(e.scheduleTimes);
      final f = e.filter;
      if (f != null) {
        _typeFilter = f.type ?? 'any';
        _activeOnly = f.isActive ?? false;
        if (f.minAmount != null) _minAmtCtrl.text = _trimNum(f.minAmount!);
        if (f.maxAmount != null) _maxAmtCtrl.text = _trimNum(f.maxAmount!);
        if (f.bankIds != null) _selectedBankIds.addAll(f.bankIds!);
        if (f.accountKeys != null) _selectedAccountKeys.addAll(f.accountKeys!);
        _selectedProfileId = f.profileId;
      }
      e.fieldMap.forEach((totals, backend) {
        _mappings.add(_MapRow(totals, backend));
      });
    }
    _loadAccountsAndBanks();
  }

  Future<void> _loadAccountsAndBanks() async {
    try {
      final profiles = await ProfileRepository().getProfiles();
      final accounts = await _repo.getAccountsForFilter();
      final banks = await BankConfigService().getBanks();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        if (_selectedProfileId != null &&
            !_profiles.any((profile) => profile.id == _selectedProfileId)) {
          _selectedProfileId = null;
        }
        _allAccounts = accounts;
        _applyProfileAccountFilter();
        _banksById = {for (final b in banks) b.id: b};
        _loadingAccounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAccounts = false);
    }
  }

  void _applyProfileAccountFilter() {
    final selectedProfileId = _selectedProfileId;
    _accounts = selectedProfileId == null
        ? _allAccounts
        : _allAccounts
            .where((account) => account.profileId == selectedProfileId)
            .toList(growable: false);
    _pruneBankAccountSelections();
  }

  void _pruneBankAccountSelections() {
    final visibleBanks = {for (final account in _accounts) account.bank};
    _selectedBankIds.removeWhere((bankId) => !visibleBanks.contains(bankId));
    final visibleAccounts = {
      for (final account in _accounts)
        if (_accountSelectable(account)) _accountKey(account),
    };
    _selectedAccountKeys.removeWhere((key) => !visibleAccounts.contains(key));
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _minAmtCtrl.dispose();
    _maxAmtCtrl.dispose();
    for (final m in _mappings) {
      m.backend.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _next() {
    final error = _validateStep(_step);
    if (error != null) {
      _toast(error);
      return;
    }
    if (_step == _stepTitles.length - 1) {
      _save();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _step++);
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() => _step--);
  }

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_nameCtrl.text.trim().isEmpty) return 'Give the rule a name.';
        return null;
      case 1:
        if (_destinationId == null) return 'Pick a destination.';
        return null;
      case 3:
        if (_whenMode == _WhenMode.daily && _scheduleTimes.isEmpty) {
          return 'Add at least one time, or change when to sync.';
        }
        return null;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Build payload + save
  // ---------------------------------------------------------------------------

  SyncScheduleMode get _scheduleMode {
    switch (_whenMode) {
      case _WhenMode.interval:
        return SyncScheduleMode.interval;
      case _WhenMode.daily:
        return SyncScheduleMode.daily;
      case _WhenMode.realtime:
      case _WhenMode.manual:
        return SyncScheduleMode.off;
    }
  }

  SyncFilter? _buildFilter() {
    final minAmt = double.tryParse(_minAmtCtrl.text.trim());
    final maxAmt = double.tryParse(_maxAmtCtrl.text.trim());
    final supportsAccounts = _entity != SyncEntity.budgets;
    final supportsProfiles = _entity != SyncEntity.budgets;
    final selectedBankIds = _scopedSelectedBankIds();
    final selectedAccountKeys = _scopedSelectedAccountKeys();
    final filter = SyncFilter(
      type: _entity == SyncEntity.transactions && _typeFilter != 'any'
          ? _typeFilter
          : null,
      minAmount: _entity == SyncEntity.transactions ? minAmt : null,
      maxAmount: _entity == SyncEntity.transactions ? maxAmt : null,
      bankIds: supportsAccounts && selectedBankIds.isNotEmpty
          ? selectedBankIds
          : null,
      accountKeys: supportsAccounts && selectedAccountKeys.isNotEmpty
          ? selectedAccountKeys
          : null,
      isActive: _entity == SyncEntity.budgets && _activeOnly ? true : null,
      profileId: supportsProfiles ? _selectedProfileId : null,
    );
    return filter.isEmpty ? null : filter;
  }

  List<int> _scopedSelectedBankIds() {
    if (_loadingAccounts) return _selectedBankIds.toList(growable: false);
    final visibleBankIds = {for (final account in _accounts) account.bank};
    return _selectedBankIds
        .where(visibleBankIds.contains)
        .toList(growable: false);
  }

  List<String> _scopedSelectedAccountKeys() {
    if (_loadingAccounts) return _selectedAccountKeys.toList(growable: false);
    final visibleAccountKeys = {
      for (final account in _accounts)
        if (_accountSelectable(account)) _accountKey(account),
    };
    return _selectedAccountKeys
        .where(visibleAccountKeys.contains)
        .toList(growable: false);
  }

  Map<String, String> _buildFieldMap() {
    final map = <String, String>{};
    for (final m in _mappings) {
      final backend = m.backend.text.trim();
      if (backend.isNotEmpty) map[m.totalsField] = backend;
    }
    return map;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final now = DateTime.now();
    final enabled = widget.existing?.enabled ?? true;
    final scheduleMode = _scheduleMode;
    final rule = SyncRule(
      id: widget.existing?.id,
      destinationId: _destinationId!,
      name: _nameCtrl.text.trim(),
      entity: _entity,
      filter: _buildFilter(),
      method: _method,
      pathTemplate: _pathCtrl.text.trim().isEmpty ? '/' : _pathCtrl.text.trim(),
      fieldMap: _buildFieldMap(),
      sendUnmapped: _sendUnmapped,
      batchMode: _batchMode,
      triggerManual: true,
      triggerOnNewTxn: _whenMode == _WhenMode.realtime,
      triggerOnConnectivity: _alsoOnReconnect,
      scheduleMode: scheduleMode,
      scheduleIntervalMinutes:
          scheduleMode == SyncScheduleMode.interval ? _scheduleInterval : null,
      scheduleTimes: scheduleMode == SyncScheduleMode.daily
          ? List.of(_scheduleTimes)
          : const [],
      enabled: enabled,
      backfillDone: widget.existing?.backfillDone ?? false,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      int ruleId;
      if (_isEditing) {
        await _repo.updateRule(rule);
        ruleId = rule.id!;
      } else {
        ruleId = await _repo.insertRule(rule);
      }
      final saved = rule.copyWith(id: ruleId);
      if (enabled && !saved.backfillDone) {
        await _maybeBackfill(saved);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  Future<void> _maybeBackfill(SyncRule rule) async {
    final count = await SyncService.instance.countMatching(rule);
    if (!mounted || count == 0) {
      await _repo.markRuleBackfilled(rule.id!);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Push existing records?'),
        content: Text(
          'This rule matches $count existing ${rule.entity.label.toLowerCase()}. '
          'Send them to the destination now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Push $count'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SyncService.instance.primeProgress(
        reason: 'backfill',
        total: count,
      );
      await SyncService.instance.backfillRule(rule);
      unawaited(SyncService.instance.requestDrain(reason: 'backfill'));
      unawaited(DataSyncScheduler.requestImmediateDrain(
        reason: 'backfill',
        initialDelay: const Duration(seconds: 30),
      ));
    } else {
      await _repo.markRuleBackfilled(rule.id!);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Scaffold
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.destinations.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add rule')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Add a destination before creating a rule.',
              style: TextStyle(color: AppColors.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final isLast = _step == _stepTitles.length - 1;
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final formBottomPadding = keyboardInset > 0 ? 16.0 : 8.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit rule' : 'Add rule'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _stepTitles.length,
            minHeight: 3,
            backgroundColor: AppColors.borderColor(context),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
          ),
        ),
      ),
      body: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 16, 20, formBottomPadding),
                children: [
                  Text(
                    'Step ${_step + 1} of ${_stepTitles.length}',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stepTitles[_step],
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ..._currentStep(),
                ],
              ),
            ),
            _bottomBar(isLast),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool isLast) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        bottomSafeArea + actionBottomGap,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        border: Border(top: BorderSide(color: AppColors.borderColor(context))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            OutlinedButton(
              onPressed: _saving ? null : _back,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Back'),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: DataSyncPrimaryButton(
              label:
                  isLast ? (_isEditing ? 'Save changes' : 'Add rule') : 'Next',
              loading: _saving,
              onPressed: _next,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _currentStep() {
    switch (_step) {
      case 0:
        return _stepBasics();
      case 1:
        return _stepWhere();
      case 2:
        return _stepFilter();
      default:
        return _stepWhen();
    }
  }

  // ---------------------------------------------------------------------------
  // Step 1 · Basics
  // ---------------------------------------------------------------------------

  List<Widget> _stepBasics() {
    return [
      DataSyncTextField(
        controller: _nameCtrl,
        label: 'Rule name',
        hint: 'e.g. Big debits → expenses API',
      ),
      const SizedBox(height: 20),
      _label('What data does this rule sync?'),
      const SizedBox(height: 8),
      for (final entity in SyncEntity.values)
        _radioTile<SyncEntity>(
          value: entity,
          group: _entity,
          title: entity.label,
          onChanged: (v) => setState(() {
            _entity = v;
            for (final m in _mappings) {
              m.backend.dispose();
            }
            _mappings.clear();
            _typeFilter = 'any';
            _activeOnly = false;
          }),
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Step 2 · Where it goes
  // ---------------------------------------------------------------------------

  List<Widget> _stepWhere() {
    return [
      _label('Destination'),
      const SizedBox(height: 8),
      _boxed(DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _destinationId,
          items: [
            for (final d in widget.destinations)
              DropdownMenuItem(value: d.id, child: Text(d.name)),
          ],
          onChanged: (v) => setState(() => _destinationId = v),
        ),
      )),
      const SizedBox(height: 20),
      _label('Endpoint'),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _boxed(
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _method,
                items: [
                  for (final m in SyncHttpMethod.all)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'POST'),
              ),
            ),
            grow: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DataSyncTextField(
              controller: _pathCtrl,
              label: '',
              hint: '/transactions',
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _hint('Path can include {reference}, {accountNumber}, {bankId}.'),
      const SizedBox(height: 20),
      _label('How to send'),
      const SizedBox(height: 8),
      _SegmentedControl<SyncBatchMode>(
        value: _batchMode,
        options: const [
          (SyncBatchMode.perRecord, 'One request each'),
          (SyncBatchMode.bulkArray, 'Bulk (one array)'),
        ],
        onChanged: (v) => setState(() => _batchMode = v),
      ),
      const SizedBox(height: 6),
      _hint(_batchMode == SyncBatchMode.bulkArray
          ? 'All matching records are sent together as one JSON array.'
          : 'One request per record — the path can target {reference} for upserts.'),
    ];
  }

  // ---------------------------------------------------------------------------
  // Step 3 · Filter & fields
  // ---------------------------------------------------------------------------

  List<Widget> _stepFilter() {
    final widgets = <Widget>[];
    if (_entity != SyncEntity.budgets) {
      widgets.addAll([
        ..._profileSelector(),
        const SizedBox(height: 16),
      ]);
    }
    if (_entity == SyncEntity.transactions) {
      widgets.addAll([
        _label('Transaction type'),
        const SizedBox(height: 8),
        _SegmentedControl<String>(
          value: _typeFilter,
          options: const [
            ('any', 'Any'),
            ('CREDIT', 'Credit'),
            ('DEBIT', 'Debit'),
          ],
          onChanged: (v) => setState(() => _typeFilter = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DataSyncTextField(
                controller: _minAmtCtrl,
                label: 'Min amount',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DataSyncTextField(
                controller: _maxAmtCtrl,
                label: 'Max amount',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._bankAccountLists(),
      ]);
    } else if (_entity == SyncEntity.accounts) {
      widgets.addAll(_bankAccountLists());
    } else {
      widgets.add(_switchTile(
        'Active budgets only',
        _activeOnly,
        (v) => setState(() => _activeOnly = v),
      ));
    }

    widgets.addAll([
      const SizedBox(height: 22),
      _mappingSection(),
      _switchTile(
        'Send unmapped fields too',
        _sendUnmapped,
        (v) => setState(() => _sendUnmapped = v),
        subtitle: 'Off = only mapped fields are sent (better for privacy).',
      ),
    ]);
    return widgets;
  }

  List<Widget> _profileSelector() {
    if (_loadingAccounts) {
      return [
        _label('Profile'),
        const SizedBox(height: 8),
        _hint('Loading profiles…'),
      ];
    }
    if (_profiles.isEmpty) {
      return [
        _label('Profile'),
        const SizedBox(height: 8),
        _hint('All profiles are included.'),
      ];
    }
    return [
      _label('Profile'),
      const SizedBox(height: 8),
      _boxed(
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            isExpanded: true,
            value: _selectedProfileId ?? _allProfilesValue,
            items: [
              const DropdownMenuItem<int>(
                value: _allProfilesValue,
                child: Text('All profiles'),
              ),
              for (final profile in _profiles)
                if (profile.id != null)
                  DropdownMenuItem<int>(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
            ],
            onChanged: (value) => setState(() {
              _selectedProfileId = value == _allProfilesValue ? null : value;
              _applyProfileAccountFilter();
            }),
          ),
        ),
      ),
      const SizedBox(height: 6),
      _hint(_selectedProfileId == null
          ? 'Includes matching records from every profile.'
          : 'Banks and accounts below are filtered to ${_profileLabel(_selectedProfileId)}.'),
    ];
  }

  List<Widget> _bankAccountLists() {
    if (_loadingAccounts) {
      return [_hint('Loading your accounts…')];
    }
    if (_accounts.isEmpty) {
      return [
        _hint(_selectedProfileId == null
            ? 'No accounts found. Bank and account filters are unavailable.'
            : '${_profileLabel(_selectedProfileId)} has no accounts yet. Bank and account filters are unavailable.'),
      ];
    }
    final bankIds = <int>{for (final a in _accounts) a.bank}.toList()..sort();
    return [
      _label('Banks'),
      _hint(_selectedProfileId == null
          ? 'Leave all off to include every bank.'
          : 'Leave all off to include every bank in this profile.'),
      const SizedBox(height: 4),
      for (final bankId in bankIds)
        _checkTile(
          title: _bankLabel(bankId),
          value: _selectedBankIds.contains(bankId),
          onChanged: (sel) => setState(() {
            sel
                ? _selectedBankIds.add(bankId)
                : _selectedBankIds.remove(bankId);
            _pruneBankAccountSelections();
          }),
        ),
      const SizedBox(height: 14),
      _label('Specific accounts'),
      const SizedBox(height: 4),
      for (final acct in _accounts)
        _checkTile(
          title: _accountLabel(acct),
          value: _selectedAccountKeys.contains(_accountKey(acct)),
          enabled: _accountSelectable(acct),
          onChanged: (sel) => setState(() {
            final key = _accountKey(acct);
            sel
                ? _selectedAccountKeys.add(key)
                : _selectedAccountKeys.remove(key);
          }),
        ),
    ];
  }

  String _accountKey(Account a) => '${a.accountNumber}|${a.bank}';

  bool _accountSelectable(Account account) {
    return _selectedBankIds.isEmpty || _selectedBankIds.contains(account.bank);
  }

  String _profileLabel(int? profileId) {
    if (profileId == null) return 'all profiles';
    for (final profile in _profiles) {
      if (profile.id == profileId) return profile.name;
    }
    return 'Profile $profileId';
  }

  String _bankLabel(int bankId) {
    if (bankId == CashConstants.bankId) return CashConstants.bankShortName;
    final bank = _banksById[bankId];
    return bank?.shortName ?? bank?.name ?? 'Bank $bankId';
  }

  String _accountLabel(Account a) {
    final num = a.accountNumber;
    final tail = num.length > 4 ? num.substring(num.length - 4) : num;
    return '${_bankLabel(a.bank)} ••$tail';
  }

  Widget _mappingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _label('Field mapping (Totals → your API)')),
            TextButton.icon(
              onPressed: () => setState(
                  () => _mappings.add(_MapRow(_entity.fieldKeys.first, ''))),
              icon: const Icon(AppIcons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_mappings.isEmpty) _hint('No mapping = send the record as-is.'),
        for (var i = 0; i < _mappings.length; i++) _mappingRow(i),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _mappingRow(int index) {
    final row = _mappings[index];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: _boxed(
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _entity.fieldKeys.contains(row.totalsField)
                      ? row.totalsField
                      : _entity.fieldKeys.first,
                  items: [
                    for (final key in _entity.fieldKeys)
                      DropdownMenuItem(value: key, child: Text(key)),
                  ],
                  onChanged: (v) =>
                      setState(() => row.totalsField = v ?? row.totalsField),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(AppIcons.chevron_right_rounded, size: 18),
          ),
          Expanded(
            child: TextFormField(
              controller: row.backend,
              style: TextStyle(
                  color: AppColors.textPrimary(context), fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'their field',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              _mappings.removeAt(index).backend.dispose();
            }),
            icon: const Icon(
              AppIcons.delete_outline_rounded,
              color: AppColors.red,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 · When to sync
  // ---------------------------------------------------------------------------

  List<Widget> _stepWhen() {
    return [
      _hint('Pick one cadence. “Sync now” always works manually.'),
      const SizedBox(height: 8),
      _radioTile<_WhenMode>(
        value: _WhenMode.realtime,
        group: _whenMode,
        title: 'Real-time',
        subtitle: 'As soon as a matching record is added or changed.',
        onChanged: (v) => setState(() => _whenMode = v),
      ),
      _radioTile<_WhenMode>(
        value: _WhenMode.interval,
        group: _whenMode,
        title: 'Every…',
        subtitle: 'On a repeating interval.',
        onChanged: (v) => setState(() => _whenMode = v),
      ),
      if (_whenMode == _WhenMode.interval)
        Padding(
          padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
          child: _boxed(
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _scheduleInterval,
                items: [
                  for (final mins in syncIntervalPresets)
                    DropdownMenuItem(
                        value: mins,
                        child: Text('Every ${_intervalLabel(mins)}')),
                ],
                onChanged: (v) =>
                    setState(() => _scheduleInterval = v ?? _scheduleInterval),
              ),
            ),
          ),
        ),
      _radioTile<_WhenMode>(
        value: _WhenMode.daily,
        group: _whenMode,
        title: 'Daily at…',
        subtitle: 'At specific times each day.',
        onChanged: (v) => setState(() => _whenMode = v),
      ),
      if (_whenMode == _WhenMode.daily)
        Padding(
          padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in _scheduleTimes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded,
                          size: 16, color: AppColors.textTertiary(context)),
                      const SizedBox(width: 8),
                      Text(_formatTimeLabel(t),
                          style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14)),
                      const Spacer(),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            setState(() => _scheduleTimes.remove(t)),
                        icon: const Icon(
                          AppIcons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(AppIcons.add_rounded, size: 18),
                label: const Text('Add time'),
              ),
            ],
          ),
        ),
      _radioTile<_WhenMode>(
        value: _WhenMode.manual,
        group: _whenMode,
        title: 'Manual only',
        subtitle: 'Only when you tap “Sync now”.',
        onChanged: (v) => setState(() => _whenMode = v),
      ),
      if (_whenMode == _WhenMode.interval || _whenMode == _WhenMode.daily)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _hint('Background sync wakes about every 15 min, so it fires '
              'within ~15 minutes of the chosen time.'),
        ),
      const Divider(height: 28),
      _switchTile(
        'Also sync when back online',
        _alsoOnReconnect,
        (v) => setState(() => _alsoOnReconnect = v),
      ),
    ];
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      // Always show AM/PM regardless of the device's 24-hour setting.
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;
    // Stored as 24-hour HH:mm (used by the scheduler); displayed as 12-hour.
    final value = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (!_scheduleTimes.contains(value)) {
        _scheduleTimes.add(value);
        _scheduleTimes.sort();
      }
    });
  }

  String _formatTimeLabel(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  String _intervalLabel(int mins) {
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60} hr';
  }

  // ---------------------------------------------------------------------------
  // Small shared building blocks
  // ---------------------------------------------------------------------------

  Widget _boxed(Widget child, {bool grow = true}) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: child,
    );
    return grow ? box : IntrinsicWidth(child: box);
  }

  Widget _radioTile<T>({
    required T value,
    required T group,
    required String title,
    String? subtitle,
    required ValueChanged<T> onChanged,
  }) {
    final selected = value == group;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.10)
              : AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primaryLight
                : AppColors.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? AppColors.primaryLight
                  : AppColors.textTertiary(context),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              value
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: value
                  ? AppColors.primaryLight
                  : enabled
                      ? AppColors.textTertiary(context)
                      : AppColors.slate400,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: enabled
                          ? AppColors.textPrimary(context)
                          : AppColors.textTertiary(context),
                      fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeThumbColor: AppColors.primaryLight,
      onChanged: onChanged,
      title: Text(title,
          style:
              TextStyle(color: AppColors.textPrimary(context), fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(
                  color: AppColors.textTertiary(context), fontSize: 12)),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          text,
          style:
              TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
        ),
      );
}

/// Compact equal-width single-choice control (replaces chip walls).
class _SegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _SegmentedControl({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: option.$1 == value
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    option.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: option.$1 == value
                          ? Colors.white
                          : AppColors.textSecondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
