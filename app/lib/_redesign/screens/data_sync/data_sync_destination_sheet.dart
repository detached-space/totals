import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:totals/_redesign/screens/data_sync/data_sync_widgets.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/services/data_sync/data_sync_repository.dart';
import 'package:totals/services/data_sync/outbound_http_client.dart';
import 'package:totals/services/data_sync/sync_models.dart';
import 'package:totals/services/data_sync/sync_url.dart';

/// Shows the add/edit destination sheet. Returns true if a destination was
/// saved.
Future<bool?> showDataSyncDestinationSheet(
  BuildContext context, {
  SyncDestination? existing,
}) {
  return showDataSyncSheet<bool>(
    context,
    title: existing == null ? 'Add destination' : 'Edit destination',
    child: _DestinationForm(existing: existing),
    scrollable: false,
  );
}

class _DestinationForm extends StatefulWidget {
  final SyncDestination? existing;
  const _DestinationForm({this.existing});

  @override
  State<_DestinationForm> createState() => _DestinationFormState();
}

class _DestinationFormState extends State<_DestinationForm> {
  final _formKey = GlobalKey<FormState>();
  final _repo = DataSyncRepository();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _headerCtrl;
  late final TextEditingController _usernameCtrl;
  final _secretCtrl = TextEditingController();

  SyncAuthType _authType = SyncAuthType.none;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  bool get _isEditing => widget.existing != null;
  bool get _hasExistingSecret => (widget.existing?.secretRef ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _urlCtrl = TextEditingController(text: e?.baseUrl ?? '');
    _headerCtrl = TextEditingController(text: e?.authHeaderName ?? 'X-API-Key');
    _usernameCtrl = TextEditingController(text: e?.authUsername ?? '');
    _authType = e?.authType ?? SyncAuthType.none;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _headerCtrl.dispose();
    _usernameCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _inlineHeaders() {
    final secret = _secretCtrl.text;
    switch (_authType) {
      case SyncAuthType.none:
        return const {};
      case SyncAuthType.apiKey:
        if (secret.isEmpty) return const {};
        final name = _headerCtrl.text.trim();
        return {name.isEmpty ? 'X-API-Key' : name: secret};
      case SyncAuthType.bearer:
        return secret.isEmpty ? const {} : {'Authorization': 'Bearer $secret'};
      case SyncAuthType.basic:
        final token =
            base64Encode(utf8.encode('${_usernameCtrl.text}:$secret'));
        return {'Authorization': 'Basic $token'};
    }
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    final error = SyncUrl.validate(url);
    if (error != null) {
      setState(() => _testResult = error);
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = OutboundHttpClient();
    final code = await client.probe(Uri.parse(url), _inlineHeaders());
    client.close();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = code == null
          ? 'Could not reach the server.'
          : 'Server responded (HTTP $code).';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final secretText = _secretCtrl.text;
    final dest = SyncDestination(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim(),
      authType: _authType,
      authHeaderName:
          _authType == SyncAuthType.apiKey ? _headerCtrl.text.trim() : null,
      authUsername:
          _authType == SyncAuthType.basic ? _usernameCtrl.text.trim() : null,
      secretRef: widget.existing?.secretRef,
      enabled: widget.existing?.enabled ?? true,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (_isEditing) {
        await _repo.updateDestination(
          dest,
          secret: secretText.isEmpty ? null : secretText,
          clearSecret: !_authType.needsSecret,
        );
      } else {
        await _repo.insertDestination(dest, secret: secretText);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testResult = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = keyboardInset > 0 ? 16.0 : 8.0;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: formBottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataSyncTextField(
                    controller: _nameCtrl,
                    label: 'Name',
                    hint: 'My backend',
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  DataSyncTextField(
                    controller: _urlCtrl,
                    label: 'Base URL',
                    hint: 'https://api.example.com',
                    keyboardType: TextInputType.url,
                    validator: SyncUrl.validate,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Authentication',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in SyncAuthType.values)
                        ChoiceChip(
                          label: Text(type.label),
                          selected: _authType == type,
                          onSelected: (_) => setState(() => _authType = type),
                        ),
                    ],
                  ),
                  if (_authType == SyncAuthType.apiKey) ...[
                    const SizedBox(height: 14),
                    DataSyncTextField(
                      controller: _headerCtrl,
                      label: 'Header name',
                      hint: 'X-API-Key',
                    ),
                  ],
                  if (_authType == SyncAuthType.basic) ...[
                    const SizedBox(height: 14),
                    DataSyncTextField(
                      controller: _usernameCtrl,
                      label: 'Username',
                    ),
                  ],
                  if (_authType.needsSecret) ...[
                    const SizedBox(height: 14),
                    DataSyncTextField(
                      controller: _secretCtrl,
                      label: _authType == SyncAuthType.basic
                          ? 'Password'
                          : 'Secret',
                      hint: _isEditing && _hasExistingSecret
                          ? 'Leave blank to keep current'
                          : null,
                      obscure: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: const Text('Test connection'),
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _testResult!,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: actionTopGap),
          Padding(
            padding: EdgeInsets.only(bottom: bottomSafeArea + actionBottomGap),
            child: DataSyncPrimaryButton(
              label: _isEditing ? 'Save changes' : 'Add destination',
              loading: _saving,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
