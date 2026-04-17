import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/constants/cash_constants.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/account.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/utils/account_share_payload.dart';
import 'package:totals/widgets/account_share_qr_code.dart';

class AccountShareQrPage extends StatefulWidget {
  const AccountShareQrPage({super.key});

  @override
  State<AccountShareQrPage> createState() => _AccountShareQrPageState();
}

class _AccountShareQrPageState extends State<AccountShareQrPage> {
  final AccountRepository _accountRepo = AccountRepository();
  final TextEditingController _displayNameController = TextEditingController();
  final GlobalKey _qrKey = GlobalKey();
  static const String _sharedNameKey = 'account_share_display_name';

  List<Account> _accounts = [];
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
    await _loadSavedDisplayName();
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final allAccounts = await _accountRepo.getAccounts();
      // Filter out cash account
      final accounts = allAccounts
          .where((account) => account.bank != CashConstants.bankId)
          .toList();
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

  String _accountKey(Account account) {
    return '${account.bank}:${account.accountNumber}';
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
            account.accountHolderName.trim().isNotEmpty) {
          final inferredName = account.accountHolderName.trim();
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
        .map((account) => AccountShareEntry(
              bankId: account.bank,
              accountNumber: account.accountNumber,
              name: account.accountHolderName.trim(),
            ))
        .toList();
    if (entries.isEmpty) return null;
    return AccountSharePayload(name: name, accounts: entries);
  }

  void _toggleAccount(Account account, bool? isSelected) {
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
        text: 'Scan this QR code to add my account details',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing QR code: $e'),
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
    final sortedAccounts = List<Account>.from(_accounts)
      ..sort((a, b) {
        final nameA = _getBankInfo(a.bank)?.name ?? '';
        final nameB = _getBankInfo(b.bank)?.name ?? '';
        final bankCompare = nameA.compareTo(nameB);
        if (bankCompare != 0) return bankCompare;
        return a.accountNumber.compareTo(b.accountNumber);
      });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: const Text('Share Accounts'),
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
                            'No accounts yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Register accounts first, then generate a share QR.',
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
                        onDisplayNameChanged: _handleDisplayNameChanged,
                        onShare: _shareQrCode,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            '${_selectedKeys.length} of ${_accounts.length} selected',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _selectAllAccounts,
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            onPressed: _clearAllAccounts,
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final account in sortedAccounts) ...[
                        _AccountShareTile(
                          account: account,
                          bank: _getBankInfo(account.bank),
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
  final ValueChanged<String> onDisplayNameChanged;
  final VoidCallback onShare;

  const _QrPreviewCard({
    required this.qrKey,
    required this.data,
    required this.sharedName,
    required this.displayNameController,
    required this.colorScheme,
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
                  hintText: 'Name shown to recipient',
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
                  'Too much data to render QR',
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
              label: const Text('Share QR Code'),
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
                'Select accounts and enter a name to generate your QR.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            sharedName == null || sharedName!.isEmpty
                ? 'Select accounts below and enter a name to generate your QR.'
                : 'Sharing as $sharedName. Let someone scan this QR to add your accounts.',
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
  final Account account;
  final Bank? bank;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _AccountShareTile({
    required this.account,
    required this.bank,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        child: bank != null
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
        account.accountNumber.isNotEmpty ? account.accountNumber : 'Account',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        bank?.shortName ?? bank?.name ?? 'Unknown Bank',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
