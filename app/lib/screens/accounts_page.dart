import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/widgets/add_user_account_form.dart';
import 'package:totals/screens/account_share_qr_page.dart';
import 'package:totals/screens/account_share_scan_page.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/constants/cash_constants.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  final TextEditingController _searchController = TextEditingController();
  List<Bank> _banks = [];
  List<UserAccount> _userAccounts = [];
  String _searchQuery = '';
  bool _isLoading = true;
  Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final configuredBanks = await _bankConfigService.getBanks();
      final mergedBanksById = <int, Bank>{
        for (final bank in configuredBanks) bank.id: bank,
      };
      for (final legacyBank in AllBanksFromAssets.getAllBanks()) {
        mergedBanksById.putIfAbsent(legacyBank.id, () => legacyBank);
      }
      _banks = mergedBanksById.values.toList();

      // Load user accounts
      final accounts = await _userAccountRepo.getUserAccounts();
      final sortedAccounts = List<UserAccount>.from(accounts)
        ..sort(_compareUserAccounts);

      if (mounted) {
        setState(() {
          _userAccounts = sortedAccounts;
          final accountKeys = sortedAccounts.map(_accountKey).toSet();
          _selectedKeys = _selectedKeys.intersection(accountKeys);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        print("debug: Error loading data: $e");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Bank? _getBankInfo(int bankId) {
    try {
      return _banks.firstWhere((element) => element.id == bankId);
    } catch (e) {
      return null;
    }
  }

  String _accountKey(UserAccount account) {
    return '${account.bankId}:${account.accountNumber}';
  }

  String _normalizedSortText(String value) => value.trim().toLowerCase();

  bool _isCashWallet(UserAccount account) {
    return account.bankId == CashConstants.bankId ||
        _normalizedSortText(account.accountHolderName) ==
            _normalizedSortText(CashConstants.defaultAccountHolderName);
  }

  int _compareUserAccounts(UserAccount a, UserAccount b) {
    final aIsCash = _isCashWallet(a);
    final bIsCash = _isCashWallet(b);
    if (aIsCash != bIsCash) return aIsCash ? -1 : 1;

    final holderComparison = _normalizedSortText(
      a.accountHolderName,
    ).compareTo(_normalizedSortText(b.accountHolderName));
    if (holderComparison != 0) return holderComparison;

    final aBank = _getBankInfo(a.bankId);
    final bBank = _getBankInfo(b.bankId);
    final bankComparison = _normalizedSortText(
      aBank?.name ?? aBank?.shortName ?? 'Bank ${a.bankId}',
    ).compareTo(
      _normalizedSortText(
          bBank?.name ?? bBank?.shortName ?? 'Bank ${b.bankId}'),
    );
    if (bankComparison != 0) return bankComparison;

    return _normalizedSortText(
      a.accountNumber,
    ).compareTo(_normalizedSortText(b.accountNumber));
  }

  List<UserAccount> _filterAccounts(List<UserAccount> accounts) {
    if (_searchQuery.isEmpty) return accounts;
    return accounts.where((account) {
      final bank = _getBankInfo(account.bankId);
      final bankName = bank?.name.toLowerCase() ?? '';
      final bankShortName = bank?.shortName.toLowerCase() ?? '';
      final accountNumber = account.accountNumber.toLowerCase();
      final holderName = account.accountHolderName.toLowerCase();
      final query = _searchQuery;
      return accountNumber.contains(query) ||
          holderName.contains(query) ||
          bankName.contains(query) ||
          bankShortName.contains(query);
    }).toList();
  }

  bool get _isSelectionMode => _selectedKeys.isNotEmpty;

  List<UserAccount> get _selectedAccounts {
    return _userAccounts
        .where((account) => _selectedKeys.contains(_accountKey(account)))
        .toList();
  }

  void _toggleSelection(UserAccount account) {
    final key = _accountKey(account);
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  void _selectAll(List<UserAccount> accounts) {
    setState(() {
      _selectedKeys = accounts.map(_accountKey).toSet();
    });
  }

  Future<void> _copyAccountNumber(String accountNumber) async {
    await Clipboard.setData(ClipboardData(text: accountNumber));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10nTextRead('Account number copied to clipboard')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showAddAccountDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            height: mediaQuery.size.height * 0.85,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: AddUserAccountForm(
                onAccountAdded: () {
                  _loadData();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final selected = _selectedAccounts;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10nText('Delete Selected Accounts?')),
          content: Text(
            '${dialogContext.l10nText('Are you sure you want to delete')} ${selected.length} ${dialogContext.l10nText(selected.length == 1 ? 'account' : 'accounts')}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10nText('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(dialogContext.l10nText('Delete')),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        for (final account in selected) {
          if (account.id != null) {
            await _userAccountRepo.deleteUserAccount(account.id!);
          } else {
            await _userAccountRepo.deleteUserAccountByNumberAndBank(
              account.accountNumber,
              account.bankId,
            );
          }
        }
        _clearSelection();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.l10nTextRead('Deleted')} ${selected.length} ${context.l10nTextRead(selected.length == 1 ? 'account' : 'accounts')}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.l10nTextRead('Error deleting accounts')}: $e',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _openShareQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AccountShareQrPage(),
      ),
    );
  }

  Future<void> _openScanQr() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AccountShareScanPage(),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredAccounts = _filterAccounts(_userAccounts);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: _isSelectionMode
            ? IconButton(
                tooltip: context.l10nText('Clear selection'),
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _isSelectionMode
              ? '${_selectedKeys.length} ${context.l10nText('selected')}'
              : context.l10nText('Quick Access Accounts'),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _isSelectionMode
            ? [
                IconButton(
                  tooltip: context.l10nText('Clear selection'),
                  icon: const Icon(Icons.clear_all),
                  onPressed: _clearSelection,
                ),
                IconButton(
                  tooltip: context.l10nText('Select all'),
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _selectAll(filteredAccounts),
                ),
                IconButton(
                  tooltip: context.l10nText('Delete selected'),
                  icon: const Icon(Icons.delete_outline),
                  color: colorScheme.error,
                  onPressed: _confirmDeleteSelected,
                ),
              ]
            : [
                IconButton(
                  tooltip: context.l10nText('Share accounts'),
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: _openShareQr,
                ),
              ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: InputDecoration(
                hintText: context.l10nText('Search accounts...'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Accounts list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredAccounts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isNotEmpty
                                  ? Icons.search_off
                                  : Icons.account_balance_outlined,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? context.l10nText('No accounts found')
                                  : context.l10nText('No accounts yet'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_searchQuery.isEmpty)
                              Text(
                                context.l10nText(
                                  'Tap + to add your first account',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (_searchQuery.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: OutlinedButton.icon(
                                  onPressed: _openScanQr,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: Text(
                                    context.l10nText('Scan account QR'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredAccounts.length,
                          itemBuilder: (context, index) {
                            final account = filteredAccounts[index];
                            final bank = _getBankInfo(account.bankId);
                            return _AccountCard(
                              account: account,
                              bank: bank,
                              isSelected:
                                  _selectedKeys.contains(_accountKey(account)),
                              isSelectionMode: _isSelectionMode,
                              onTap: _isSelectionMode
                                  ? () => _toggleSelection(account)
                                  : null,
                              onLongPress: () {
                                _toggleSelection(account);
                              },
                              onCopy: () =>
                                  _copyAccountNumber(account.accountNumber),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'scan-accounts-fab',
                  onPressed: _openScanQr,
                  child: const Icon(Icons.camera_alt),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'add-account-fab',
                  onPressed: _showAddAccountDialog,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final UserAccount account;
  final Bank? bank;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCopy;

  const _AccountCard({
    required this.account,
    this.bank,
    required this.isSelected,
    required this.isSelectionMode,
    this.onTap,
    required this.onLongPress,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectionColor = colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? selectionColor.withOpacity(0.06) : null,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? selectionColor
              : colorScheme.outline.withOpacity(0.2),
          width: isSelected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Bank icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: bank != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              bank!.image,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: colorScheme.surfaceVariant,
                                  child: Icon(
                                    Icons.account_balance,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.account_balance,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.accountHolderName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10nText(
                            bank?.shortName ?? bank?.name ?? 'Unknown Bank',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          account.accountNumber,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelectionMode)
                    Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? selectionColor : colorScheme.outline,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: onCopy,
                      tooltip: context.l10nText('Copy account number'),
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
