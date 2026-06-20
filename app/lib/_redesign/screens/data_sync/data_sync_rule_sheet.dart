import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_service.dart';

/// Add/edit rule sheet. Returns true if a rule was saved.
Future<bool?> showDataSyncRuleSheet(
  BuildContext context, {
  SyncRule? existing,
  required List<SyncDestination> destinations,
}) {
  return showDataSyncSheet<bool>(
    context,
    title: existing == null ? 'Add rule' : 'Edit rule',
    child: _RuleForm(existing: existing, destinations: destinations),
  );
}

class _MapRow {
  String totalsField;
  final TextEditingController backend;
  _MapRow(this.totalsField, String backendValue)
      : backend = TextEditingController(text: backendValue);
}

class _RuleForm extends StatefulWidget {
  final SyncRule? existing;
  final List<SyncDestination> destinations;
  const _RuleForm({this.existing, required this.destinations});

  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  final _formKey = GlobalKey<FormState>();
  final _repo = DataSyncRepository();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _pathCtrl;
  final _minAmtCtrl = TextEditingController();
  final _maxAmtCtrl = TextEditingController();
  final _bankIdCtrl = TextEditingController();

  SyncEntity _entity = SyncEntity.transactions;
  int? _destinationId;
  String _typeFilter = 'any'; // any | CREDIT | DEBIT
  bool _activeOnly = false;
  String _method = 'POST';
  SyncBatchMode _batchMode = SyncBatchMode.perRecord;
  bool _sendUnmapped = false;
  bool _triggerPeriodic = false;
  bool _triggerOnNewTxn = false;
  bool _triggerOnConnectivity = false;
  bool _enabled = false;
  final List<_MapRow> _mappings = [];
  bool _saving = false;

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
      _triggerPeriodic = e.triggerPeriodic;
      _triggerOnNewTxn = e.triggerOnNewTxn;
      _triggerOnConnectivity = e.triggerOnConnectivity;
      _enabled = e.enabled;
      final f = e.filter;
      if (f != null) {
        _typeFilter = f.type ?? 'any';
        _activeOnly = f.isActive ?? false;
        if (f.minAmount != null) _minAmtCtrl.text = _trimNum(f.minAmount!);
        if (f.maxAmount != null) _maxAmtCtrl.text = _trimNum(f.maxAmount!);
        if (f.bankId != null) _bankIdCtrl.text = '${f.bankId}';
      }
      e.fieldMap.forEach((totals, backend) {
        _mappings.add(_MapRow(totals, backend));
      });
    }
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _minAmtCtrl.dispose();
    _maxAmtCtrl.dispose();
    _bankIdCtrl.dispose();
    for (final m in _mappings) {
      m.backend.dispose();
    }
    super.dispose();
  }

  SyncFilter? _buildFilter() {
    final minAmt = double.tryParse(_minAmtCtrl.text.trim());
    final maxAmt = double.tryParse(_maxAmtCtrl.text.trim());
    final bankId = int.tryParse(_bankIdCtrl.text.trim());
    final filter = SyncFilter(
      type: _entity == SyncEntity.transactions && _typeFilter != 'any'
          ? _typeFilter
          : null,
      minAmount: _entity == SyncEntity.transactions ? minAmt : null,
      maxAmount: _entity == SyncEntity.transactions ? maxAmt : null,
      bankId: _entity == SyncEntity.budgets ? null : bankId,
      isActive: _entity == SyncEntity.budgets && _activeOnly ? true : null,
    );
    return filter.isEmpty ? null : filter;
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
    if (!_formKey.currentState!.validate()) return;
    if (_destinationId == null) {
      _toast('Pick a destination first.');
      return;
    }
    setState(() => _saving = true);

    final now = DateTime.now();
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
      triggerPeriodic: _triggerPeriodic,
      triggerOnNewTxn: _triggerOnNewTxn,
      triggerOnConnectivity: _triggerOnConnectivity,
      enabled: _enabled,
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

      // Offer to push existing matching records when a rule is enabled and
      // hasn't been backfilled yet.
      if (_enabled && !saved.backfillDone) {
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
      await SyncService.instance.backfillRule(rule);
      unawaitedDrain();
    } else {
      // Mark done so we don't re-prompt every edit; user can use "Sync now".
      await _repo.markRuleBackfilled(rule.id!);
    }
  }

  void unawaitedDrain() {
    SyncService.instance.requestDrain(reason: 'backfill');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Add a destination before creating a rule.',
          style: TextStyle(color: AppColors.textSecondary(context)),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataSyncTextField(
            controller: _nameCtrl,
            label: 'Rule name',
            hint: 'e.g. Big debits → expenses API',
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          _label('Data to sync'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entity in SyncEntity.values)
                ChoiceChip(
                  label: Text(entity.label),
                  selected: _entity == entity,
                  onSelected: (_) => setState(() {
                    _entity = entity;
                    // Field keys differ per entity — drop stale mappings.
                    for (final m in _mappings) {
                      m.backend.dispose();
                    }
                    _mappings.clear();
                    _typeFilter = 'any';
                    _activeOnly = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Destination'),
          const SizedBox(height: 8),
          _destinationDropdown(),
          const SizedBox(height: 16),
          ..._filterSection(),
          const SizedBox(height: 16),
          _label('Request'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(flex: 0, child: _methodDropdown()),
              const SizedBox(width: 12),
              Expanded(
                child: DataSyncTextField(
                  controller: _pathCtrl,
                  label: 'Path',
                  hint: '/transactions',
                  helper: _entity == SyncEntity.transactions
                      ? 'Placeholders: {reference}, {bankId}, {accountNumber}'
                      : 'You can use {placeholders} from the record fields',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _mappingSection(),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sendUnmapped,
            onChanged: (v) => setState(() => _sendUnmapped = v),
            activeColor: AppColors.primaryLight,
            title: Text('Send unmapped fields too',
                style: TextStyle(
                    color: AppColors.textPrimary(context), fontSize: 14)),
            subtitle: Text(
              'Off = only the mapped fields are sent (recommended for privacy).',
              style: TextStyle(
                  color: AppColors.textTertiary(context), fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          _label('Batching'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in SyncBatchMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: _batchMode == mode,
                  onSelected: (_) => setState(() => _batchMode = mode),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Triggers (manual "Sync now" always works)'),
          _triggerCheck('On a schedule (about every 15 min)', _triggerPeriodic,
              (v) => setState(() => _triggerPeriodic = v)),
          _triggerCheck('When a new transaction arrives', _triggerOnNewTxn,
              (v) => setState(() => _triggerOnNewTxn = v)),
          _triggerCheck('When connectivity returns', _triggerOnConnectivity,
              (v) => setState(() => _triggerOnConnectivity = v)),
          const Divider(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            activeColor: AppColors.primaryLight,
            title: Text('Enabled',
                style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          DataSyncPrimaryButton(
            label: _isEditing ? 'Save changes' : 'Add rule',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  List<Widget> _filterSection() {
    final widgets = <Widget>[_label('Filter (optional)'), const SizedBox(height: 8)];
    if (_entity == SyncEntity.transactions) {
      widgets.addAll([
        Wrap(
          spacing: 8,
          children: [
            for (final t in const ['any', 'CREDIT', 'DEBIT'])
              ChoiceChip(
                label: Text(t == 'any' ? 'Any type' : t),
                selected: _typeFilter == t,
                onSelected: (_) => setState(() => _typeFilter = t),
              ),
          ],
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        DataSyncTextField(
          controller: _bankIdCtrl,
          label: 'Bank ID',
          hint: 'Leave blank for all banks',
          keyboardType: TextInputType.number,
        ),
      ]);
    } else if (_entity == SyncEntity.accounts) {
      widgets.add(DataSyncTextField(
        controller: _bankIdCtrl,
        label: 'Bank ID',
        hint: 'Leave blank for all banks',
        keyboardType: TextInputType.number,
      ));
    } else {
      widgets.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _activeOnly,
        onChanged: (v) => setState(() => _activeOnly = v),
        activeColor: AppColors.primaryLight,
        title: Text('Active budgets only',
            style:
                TextStyle(color: AppColors.textPrimary(context), fontSize: 14)),
      ));
    }
    return widgets;
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
        if (_mappings.isEmpty)
          Text(
            'No mapping = send the record as-is.',
            style:
                TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
          ),
        for (var i = 0; i < _mappings.length; i++) _mappingRow(i),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: DropdownButtonHideUnderline(
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
            icon: Icon(AppIcons.delete_outline_rounded,
                color: AppColors.red, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _destinationDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _destinationId,
          items: [
            for (final d in widget.destinations)
              DropdownMenuItem(value: d.id, child: Text(d.name)),
          ],
          onChanged: (v) => setState(() => _destinationId = v),
        ),
      ),
    );
  }

  Widget _methodDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _method,
          items: [
            for (final m in SyncHttpMethod.all)
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _method = v ?? 'POST'),
        ),
      ),
    );
  }

  Widget _triggerCheck(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: value,
      activeColor: AppColors.primaryLight,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14)),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
}
