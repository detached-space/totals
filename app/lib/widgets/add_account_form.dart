import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/components/custom_inputfield.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/account_registration_service.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/widgets/inline_bank_selector.dart';
import 'package:totals/l10n/app_localizations.dart';

class RegisterAccountForm extends StatefulWidget {
  final void Function() onSubmit;
  final int? initialBankId;

  const RegisterAccountForm({
    required this.onSubmit,
    this.initialBankId,
    super.key,
  });

  @override
  State<RegisterAccountForm> createState() => _RegisterAccountFormState();
}

class _RegisterAccountFormState extends State<RegisterAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _accountHolderName = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();
  final SmsConfigService _smsConfigService = SmsConfigService();

  int? _selectedBankId;
  bool _isFormValid = false;
  bool _syncPreviousSms = true;
  bool _isLoadingBanks = true;
  List<Bank> _banks = [];
  Set<int> _supportedBankIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountHolderName.dispose();
    super.dispose();
  }

  List<BankSelectorOption> get _bankOptions {
    return buildBankSelectorOptions(_banks, _supportedBankIds);
  }

  bool get _hasSupportedBanks {
    return _bankOptions.any((option) => option.isSupported);
  }

  bool get _canSubmit {
    return _isFormValid && _selectedBankId != null && _hasSupportedBanks;
  }

  String _normalizeBankToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _bankDedupeKey(Bank bank) {
    final short = _normalizeBankToken(bank.shortName);
    final name = _normalizeBankToken(bank.name);
    if (short.contains('mpesa') || name.contains('mpesa')) {
      return 'mpesa';
    }
    if (short.isNotEmpty) return short;
    if (name.isNotEmpty) return name;
    return bank.image.toLowerCase();
  }

  List<Bank> _dedupeBanks(List<Bank> banks) {
    final dedupedByKey = <String, Bank>{};
    for (final bank in banks) {
      final key = _bankDedupeKey(bank);
      final existing = dedupedByKey[key];
      if (existing == null) {
        dedupedByKey[key] = bank;
        continue;
      }

      final shouldReplace = key == 'mpesa' && bank.id == 8 && existing.id != 8;
      if (shouldReplace) dedupedByKey[key] = bank;
    }
    return dedupedByKey.values.toList();
  }

  Future<Set<int>> _loadSupportedBankIds() async {
    try {
      final patterns =
          await _smsConfigService.getPatterns(allowRemoteFetch: false);
      return {
        ...patterns.map((pattern) => pattern.bankId),
        ...await FallbackSmsParser.supportedBankIds(),
      };
    } catch (e) {
      debugPrint("debug: Error loading SMS patterns: $e");
      return FallbackSmsParser.supportedBankIds();
    }
  }

  Future<void> _loadBanks() async {
    final supportedBankIds = await _loadSupportedBankIds();

    try {
      final banks = _dedupeBanks(await _bankConfigService.getBanks());
      if (!mounted) return;

      setState(() {
        _banks = banks;
        _supportedBankIds = supportedBankIds;
        _selectedBankId = resolveSupportedBankId(
          banks: banks,
          supportedBankIds: supportedBankIds,
          preferredBankId: widget.initialBankId ?? _selectedBankId,
        );
        _isLoadingBanks = false;
      });
    } catch (e) {
      debugPrint("debug: Error loading banks: $e");
      if (!mounted) return;

      setState(() {
        _banks = [];
        _supportedBankIds = supportedBankIds;
        _selectedBankId = null;
        _isLoadingBanks = false;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _selectedBankId == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      final service = AccountRegistrationService();
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      final trimmedAccountNumber = _accountNumber.text.trim();
      final trimmedAccountHolderName = _accountHolderName.text.trim();

      final account = await service.registerAccount(
        accountNumber: trimmedAccountNumber,
        accountHolderName: trimmedAccountHolderName,
        bankId: _selectedBankId!,
        syncPreviousSms: _syncPreviousSms,
        onSyncComplete: () {
          provider.loadData();
        },
      );

      if (account == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('This account already exists')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await provider.loadData();
      widget.onSubmit();

      if (_syncPreviousSms) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.l10nTextRead(
                "Adding your account. You can leave the app, we'll notify you when it's done.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("debug: Error registering account: $e");
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid =
          _accountHolderName.text.isNotEmpty && _accountNumber.text.isNotEmpty;
    });
  }

  Widget _buildUnsupportedBankNotice(
    BuildContext context, {
    required String message,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoadingBanks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_banks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No banks available',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      onChanged: _validateForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add New Account',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your bank details below',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close,
                  color: colorScheme.onSurfaceVariant,
                ),
                style: IconButton.styleFrom(
                  backgroundColor:
                      colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Bank',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          InlineBankSelector(
            options: _bankOptions,
            selectedBankId: _selectedBankId,
            onChanged: (bankId) {
              setState(() {
                _selectedBankId = bankId;
              });
            },
          ),
          if (!_hasSupportedBanks) ...[
            const SizedBox(height: 12),
            _buildUnsupportedBankNotice(
              context,
              message:
                  'Only banks with parsing patterns can be registered right now. Unsupported banks remain visible but disabled until support is added.',
            ),
          ],
          const SizedBox(height: 24),
          CustomTextField(
            controller: _accountNumber,
            labelText: context.l10nText('Account Number'),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.l10nTextRead('Enter account number');
              }
              if (value.trim().isEmpty) {
                return context.l10nTextRead('Enter account number');
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _accountHolderName,
            labelText: context.l10nText('Account Holder Name'),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.l10nTextRead('Enter account holder name');
              }
              if (value.trim().isEmpty) {
                return context.l10nTextRead('Enter account holder name');
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.sms_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10nText('Sync SMS History'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        context.l10nText('Import past transactions'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _syncPreviousSms,
                  onChanged: (value) {
                    setState(() {
                      _syncPreviousSms = value;
                    });
                  },
                  activeColor: colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                  child: Text(context.l10nText('Cancel')),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submitForm : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    disabledBackgroundColor:
                        colorScheme.surfaceContainerHighest,
                    disabledForegroundColor: colorScheme.onSurfaceVariant,
                  ),
                  child: Text(
                    context.l10nText('Save Account'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
