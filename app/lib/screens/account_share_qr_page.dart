import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/utils/account_sort.dart';
import 'package:totals/widgets/account_share_qr_code.dart';

class AccountShareQrPage extends StatefulWidget {
  final List<AccountShareEntry>? initialAccounts;
  final String? initialDisplayName;
  final bool showAccountNames;
  final String title;
  final String shareMessage;
  final String qrDescription;

  const AccountShareQrPage({
    super.key,
    this.initialAccounts,
    this.initialDisplayName,
    this.showAccountNames = true,
    this.title = 'Share Accounts',
    this.shareMessage = 'Scan this QR code to add my account details',
    this.qrDescription = 'Let someone scan this QR to add your accounts.',
  });

  @override
  State<AccountShareQrPage> createState() => _AccountShareQrPageState();
}

class _AccountShareQrPageState extends State<AccountShareQrPage> {
  final AccountRepository _accountRepo = AccountRepository();
  final TextEditingController _displayNameController = TextEditingController();
  final GlobalKey _qrKey = GlobalKey();
  static const String _sharedNameKey = 'account_share_display_name';

  List<AccountShareEntry> _accounts = [];
  List<Bank> _banks = [];
  bool _isLoading = true;
  Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final initialDisplayName = widget.initialDisplayName?.trim();
    if (initialDisplayName != null && initialDisplayName.isNotEmpty) {
      _displayNameController.text = initialDisplayName;
    } else if (widget.initialAccounts == null) {
      await _loadSavedDisplayName();
    }
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final List<AccountShareEntry> accounts;
      if (widget.initialAccounts != null) {
        accounts = List<AccountShareEntry>.from(widget.initialAccounts!);
      } else {
        final allAccounts = await _accountRepo.getAccounts();
        accounts = allAccounts
            .where((account) => account.bank != CashConstants.bankId)
            .map(
              (account) => AccountShareEntry(
                bankId: account.bank,
                accountNumber: account.accountNumber,
                name: account.accountHolderName.trim(),
              ),
            )
            .toList(growable: false);
      }
      final banks = AllBanksFromAssets.getAllBanks();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _banks = banks;
        _selectedKeys = accounts.map(_accountKey).toSet();
        _isLoading = false;
      });
      // Initialize display name from first account
      _updateDisplayNameFromSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _accountKey(AccountShareEntry account) {
    return '${account.bankId}:${account.accountNumber}';
  }

  Bank? _getBankInfo(int bankId) {
    try {
      return _banks.firstWhere((bank) => bank.id == bankId);
    } catch (_) {
      return null;
    }
  }

  void _updateDisplayNameFromSelection() {
    // Only update if display name is empty
    if (_displayNameController.text.isEmpty) {
      for (final account in _accounts) {
        if (_selectedKeys.contains(_accountKey(account)) &&
            (account.name?.trim().isNotEmpty ?? false)) {
          final inferredName = account.name!.trim();
          _displayNameController.text = inferredName;
          _saveDisplayName(inferredName);
          if (mounted) {
            setState(() {});
          }
          return;
        }
      }
    }
  }

  Future<void> _loadSavedDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_sharedNameKey);
    if (savedName == null || savedName.trim().isEmpty) return;
    _displayNameController.text = savedName.trim();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveDisplayName(String name) async {
    if (widget.initialAccounts != null) return;

    final trimmed = name.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_sharedNameKey);
      return;
    }
    await prefs.setString(_sharedNameKey, trimmed);
  }

  void _handleDisplayNameChanged(String value) {
    _saveDisplayName(value);
    setState(() {});
  }

  AccountSharePayload? _buildPayload() {
    final name = _displayNameController.text.trim();
    if (name.isEmpty) return null;
    final entries = _accounts
        .where((account) => _selectedKeys.contains(_accountKey(account)))
        .toList(growable: false);
    if (entries.isEmpty) return null;
    return AccountSharePayload(name: name, accounts: entries);
  }

  void _toggleAccount(AccountShareEntry account, bool? isSelected) {
    final key = _accountKey(account);
    setState(() {
      if (isSelected == true) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
    _updateDisplayNameFromSelection();
  }

  void _selectAllAccounts() {
    setState(() {
      _selectedKeys = _accounts.map(_accountKey).toSet();
    });
  }

  void _clearAllAccounts() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  Future<void> _shareQrCode() async {
    final shareText = context.l10nTextRead(widget.shareMessage);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final renderObject = _qrKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;

      final RenderRepaintBoundary boundary = renderObject;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_code.png');
      await file.writeAsBytes(buffer);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Error sharing QR code')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final payload = _buildPayload();
    final qrData = payload == null ? null : AccountSharePayload.encode(payload);
    final sortedAccounts = List<AccountShareEntry>.from(_accounts)
      ..sort(
        (left, right) => compareAccountDisplayFields(
          leftBankId: left.bankId,
          rightBankId: right.bankId,
          leftHolderName: left.name,
          rightHolderName: right.name,
          leftAccountNumber: left.accountNumber,
          rightAccountNumber: right.accountNumber,
          bankNameForId: (bankId) =>
              _getBankInfo(bankId)?.name ?? 'Bank $bankId',
        ),
      );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(context.l10nText(widget.title)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _accounts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10nText('No accounts yet'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10nText(
                              'Register accounts first, then generate a share QR.',
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _QrPreviewCard(
                        qrKey: _qrKey,
                        data: qrData,
                        sharedName: _displayNameController.text.trim(),
                        displayNameController: _displayNameController,
                        colorScheme: colorScheme,
                        qrDescription: widget.qrDescription,
                        onDisplayNameChanged: _handleDisplayNameChanged,
                        onShare: _shareQrCode,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            '${_selectedKeys.length} ${context.l10nText('of')} ${_accounts.length} ${context.l10nText('selected')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _selectAllAccounts,
                            child: Text(context.l10nText('Select all')),
                          ),
                          TextButton(
                            onPressed: _clearAllAccounts,
                            child: Text(context.l10nText('Clear')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final account in sortedAccounts) ...[
                        _AccountShareTile(
                          account: account,
                          bank: _getBankInfo(account.bankId),
                          showAccountName: widget.showAccountNames,
                          isSelected:
                              _selectedKeys.contains(_accountKey(account)),
                          onChanged: (value) => _toggleAccount(account, value),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _QrPreviewCard extends StatelessWidget {
  final GlobalKey qrKey;
  final String? data;
  final String? sharedName;
  final TextEditingController displayNameController;
  final ColorScheme colorScheme;
  final String qrDescription;
  final ValueChanged<String> onDisplayNameChanged;
  final VoidCallback onShare;

  const _QrPreviewCard({
    required this.qrKey,
    required this.data,
    required this.sharedName,
    required this.displayNameController,
    required this.colorScheme,
    required this.qrDescription,
    required this.onDisplayNameChanged,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = data != null && data!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: displayNameController,
                decoration: InputDecoration(
                  hintText: context.l10nText('Name shown to recipient'),
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
                onChanged: onDisplayNameChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasData) ...[
            RepaintBoundary(
              key: qrKey,
              child: AccountShareQrCode(
                data: data!,
                fallback: Text(
                  context.l10nText('Too much data to render QR'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share),
              label: Text(context.l10nText('Share QR Code')),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ] else
            Container(
              height: 220,
              width: 220,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10nText(
                  'Select accounts and enter a name to generate your QR.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            sharedName == null || sharedName!.isEmpty
                ? context.l10nText(
                    'Select accounts below and enter a name to generate your QR.',
                  )
                : '${context.l10nText('Sharing as')} $sharedName. ${context.l10nText(qrDescription)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountShareTile extends StatelessWidget {
  final AccountShareEntry account;
  final Bank? bank;
  final bool showAccountName;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _AccountShareTile({
    required this.account,
    required this.bank,
    required this.showAccountName,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bankLabel = context.l10nText(
      bank?.shortName ?? bank?.name ?? 'Unknown Bank',
    );
    final accountName = showAccountName ? account.name?.trim() ?? '' : '';
    final accountNumber = account.accountNumber.isNotEmpty
        ? account.accountNumber
        : context.l10nText('Account');
    final hasBankLogo = bank?.image.isNotEmpty ?? false;
    final primaryLabel = showAccountName
        ? accountName.isNotEmpty
            ? accountName
            : context.l10nText('Account Holder Name')
        : accountNumber;
    final secondaryLabel = showAccountName
        ? hasBankLogo
            ? accountNumber
            : '$bankLabel • $accountNumber'
        : bankLabel;

    return CheckboxListTile(
      value: isSelected,
      onChanged: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      activeColor: colorScheme.primary,
      contentPadding: EdgeInsets.zero,
      secondary: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: hasBankLogo
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  bank!.image,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.account_balance,
                      color: colorScheme.onSurfaceVariant,
                    );
                  },
                ),
              )
            : Icon(
                Icons.account_balance,
                color: colorScheme.onSurfaceVariant,
              ),
      ),
      title: Text(
        primaryLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        secondaryLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
