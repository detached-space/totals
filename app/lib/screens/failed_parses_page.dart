import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/failed_parse_review_service.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/sms_service.dart';
import 'package:url_launcher/url_launcher.dart';

const String _telegramBotUsername = 'detached_totals_bot';
const String _telegramBotUrl = 'https://t.me/$_telegramBotUsername';

class FailedParsesPage extends StatefulWidget {
  const FailedParsesPage({super.key});

  @override
  State<FailedParsesPage> createState() => _FailedParsesPageState();
}

class _FailedParsesPageState extends State<FailedParsesPage> {
  final FailedParseRepository _repo = FailedParseRepository();
  final TextEditingController _searchController = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();
  final Map<String, Bank?> _bankByAddress = {};

  bool _loading = true;
  bool _retrying = false;
  List<FailedParse> _items = const [];
  List<Bank> _banks = const [];
  Set<int> _registeredBankIds = <int>{};
  String? _selectedGroupKey;
  final Set<int> _selectedCardIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _repo.getAll(),
        _bankConfigService.getBanks(),
        AccountRepository().getAccounts(),
      ]);
      if (!mounted) return;
      final accounts = results[2] as List;
      setState(() {
        _items = results[0] as List<FailedParse>;
        _banks = results[1] as List<Bank>;
        _registeredBankIds =
            accounts.map((account) => account.bank as int).toSet();
        _loading = false;
        _bankByAddress.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Failed to load failed parsings')}: $e',
          ),
        ),
      );
    }
  }

  static final _transactionSignals = RegExp(
    r'(account|acct|a/c|bal|balance|amount|credited|debited|sent|received|transferred|etb|birr|\d[\d,]*\.\d{2})',
    caseSensitive: false,
  );

  List<FailedParse> get _missingPatternItems {
    return _items
        .where((item) =>
            item.isMissingPattern &&
            _transactionSignals.hasMatch(item.body) &&
            _isRegisteredBankFailedParse(item))
        .toList(growable: false);
  }

  bool _isRegisteredBankFailedParse(FailedParse item) {
    final bank = _resolveBank(item);
    return bank != null && _registeredBankIds.contains(bank.id);
  }

  _FailedParseGroup? get _selectedGroup {
    final key = _selectedGroupKey;
    if (key == null) return null;
    for (final group in _groups) {
      if (group.key == key) return group;
    }
    return null;
  }

  List<FailedParse> get _visibleItems {
    final selectedGroup = _selectedGroup;
    if (selectedGroup == null) {
      return _missingPatternItems;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return selectedGroup.items;

    return selectedGroup.items.where((item) {
      return item.address.toLowerCase().contains(query) ||
          item.body.toLowerCase().contains(query) ||
          item.timestamp.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  List<_FailedParseGroup> get _groups {
    final grouped = <String, List<FailedParse>>{};
    final bankByKey = <String, Bank?>{};

    for (final item in _missingPatternItems) {
      final bank = _resolveBank(item);
      final key = bank == null ? 'unknown' : 'bank:${bank.id}';
      grouped.putIfAbsent(key, () => <FailedParse>[]).add(item);
      bankByKey[key] = bank;
    }

    final groups = grouped.entries.map((entry) {
      final bank = bankByKey[entry.key];
      return _FailedParseGroup(
        key: entry.key,
        bank: bank,
        items: List<FailedParse>.unmodifiable(entry.value),
      );
    }).toList(growable: false);

    groups.sort((a, b) {
      final byCount = b.items.length.compareTo(a.items.length);
      if (byCount != 0) return byCount;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return groups;
  }

  Bank? _resolveBank(FailedParse item) {
    if (_banks.isEmpty) return null;
    final cacheKey = item.address;
    return _bankByAddress.putIfAbsent(cacheKey, () {
      final normalizedAddress = _normalizeToken(item.address);
      for (final bank in _banks) {
        if (!_registeredBankIds.contains(bank.id)) continue;
        for (final code in bank.codes) {
          if (normalizedAddress.contains(_normalizeToken(code))) {
            return bank;
          }
        }
      }
      return null;
    });
  }

  String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _normalizeFailedParseBodyForSimilarity(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(RegExp(r'[^a-z#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _failedParseSimilarityKey(FailedParse item) {
    return '${_normalizeToken(item.address)}|${_normalizeFailedParseBodyForSimilarity(item.body)}';
  }

  List<FailedParse> _findSimilarFailedParses(List<FailedParse> items) {
    final selectedIds = items.map((item) => item.id).whereType<int>().toSet();
    final similarityKeys = items.map(_failedParseSimilarityKey).toSet();
    if (selectedIds.isEmpty || similarityKeys.isEmpty) {
      return const <FailedParse>[];
    }

    return _items.where((candidate) {
      final candidateId = candidate.id;
      if (candidateId == null || selectedIds.contains(candidateId)) {
        return false;
      }
      return similarityKeys.contains(_failedParseSimilarityKey(candidate));
    }).toList(growable: false);
  }

  Future<List<FailedParse>?> _resolveDeleteTargets(
      List<FailedParse> items) async {
    final selectedIds = items.map((item) => item.id).whereType<int>().toSet();
    if (selectedIds.isEmpty) return null;

    final similarItems = _findSimilarFailedParses(items);
    final similarIds =
        similarItems.map((item) => item.id).whereType<int>().toSet();
    if (similarIds.isEmpty || !mounted) {
      return items;
    }

    final choice = await showDialog<_FailedParseDeleteChoice>(
      context: context,
      builder: (dialogContext) {
        final similarCount = similarIds.length;
        return AlertDialog(
          title: Text(
            dialogContext.l10nText('Delete similar failed texts too?'),
          ),
          content: Text(
            similarCount == 1
                ? dialogContext.l10nText(
                    'We found 1 other failed parsing text from the same sender with a very similar message body. Delete it too?',
                  )
                : '${dialogContext.l10nText('We found')} $similarCount ${dialogContext.l10nText('other failed parsing texts from the same sender with very similar message bodies. Delete them too?')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10nText('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _FailedParseDeleteChoice.selectedOnly,
              ),
              child: Text(
                selectedIds.length == 1
                    ? dialogContext.l10nText('Delete this only')
                    : dialogContext.l10nText('Delete selected only'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _FailedParseDeleteChoice.selectedAndSimilar,
              ),
              child: Text(
                similarCount == 1
                    ? dialogContext.l10nText('Delete both')
                    : '${dialogContext.l10nText('Delete all')} ${selectedIds.length + similarCount}',
              ),
            ),
          ],
        );
      },
    );

    switch (choice) {
      case _FailedParseDeleteChoice.selectedOnly:
        return items;
      case _FailedParseDeleteChoice.selectedAndSimilar:
        return <FailedParse>[...items, ...similarItems];
      case null:
        return null;
    }
  }

  Future<void> _deleteItems(
    List<FailedParse> items, {
    bool clearSelection = false,
  }) async {
    final selectedIds = items.map((item) => item.id).whereType<int>().toSet();
    if (selectedIds.isEmpty) return;

    final targets = await _resolveDeleteTargets(items);
    if (targets == null) return;

    final targetIds = targets.map((item) => item.id).whereType<int>().toSet();
    if (targetIds.isEmpty) return;

    await _repo.deleteByIds(targetIds.toList(growable: false));
    if (clearSelection) {
      setState(() => _selectedCardIds.clear());
    }
    await _load();
    if (!mounted) return;

    final similarCount = max(0, targetIds.length - selectedIds.length);
    final message = similarCount == 0
        ? (targetIds.length == 1
            ? context.l10nTextRead('Cleared 1 item')
            : '${context.l10nTextRead('Cleared')} ${targetIds.length} ${context.l10nTextRead('items')}')
        : '${context.l10nTextRead('Cleared')} ${targetIds.length} ${context.l10nTextRead('items, including')} $similarCount ${context.l10nTextRead(similarCount == 1 ? 'similar text' : 'similar texts')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _clearItems(List<FailedParse> items) async {
    await _deleteItems(items);
  }

  Future<void> _copy(FailedParse item) async {
    final text = [
      'Sender: ${item.address}',
      'Reason: ${item.reason}',
      'Time: ${item.timestamp}',
      '',
      item.body,
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10nTextRead('Copied to clipboard'))),
    );
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime == null) return timestamp;
    return DateFormat('h:mm a, MMM dd yyyy').format(dateTime).toLowerCase();
  }

  Future<void> _sendTestNotification() async {
    final bank = await _pickTestBank();
    if (!mounted) return;
    if (bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead('No bank available for a test notification'),
          ),
        ),
      );
      return;
    }

    final timestamp = DateTime.now();
    final senderAddress =
        bank.codes.isNotEmpty ? bank.codes.first : bank.shortName;
    final sampleMessage =
        'TEST ONLY: Account ****1234 was debited ETB 245.50 at Demo Coffee. '
        'Available balance ETB 4,820.10. Ref TEST-${timestamp.millisecondsSinceEpoch}.';

    await NotificationService.instance.requestPermissionsIfNeeded();
    final reviewId = await FailedParseReviewService.instance.storeCandidate(
      bank: bank,
      address: senderAddress,
      body: sampleMessage,
      messageDate: timestamp,
    );
    final shown =
        await NotificationService.instance.showFailedParseReviewNotification(
      reviewId: reviewId,
      bankName: bank.shortName,
      messageBody: sampleMessage,
    );

    if (!mounted) return;
    if (!shown) {
      await FailedParseReviewService.instance.discardCandidate(reviewId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead('Failed to send test notification'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10nTextRead('Test notification sent'))),
    );
  }

  Future<Bank?> _pickTestBank() async {
    if (_banks.isEmpty) {
      try {
        final banks = await _bankConfigService.getBanks();
        if (mounted) {
          setState(() {
            _banks = banks;
            _bankByAddress.clear();
          });
        }
      } catch (_) {
        // Fall through to the current state below.
      }
    }

    final accounts = await AccountRepository().getAccounts();
    final registeredBankIds = accounts.map((account) => account.bank).toSet();

    for (final bank in _banks) {
      if (registeredBankIds.contains(bank.id)) return bank;
    }
    if (_banks.isNotEmpty) return _banks.first;
    return null;
  }

  Future<void> _retrySingle(FailedParse item) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    ParseResult? result;
    Object? error;

    try {
      result = await SmsService.retryFailedParse(
        item.body,
        item.address,
        messageDate: DateTime.tryParse(item.timestamp),
      );
      if (result.status == ParseStatus.success && item.id != null) {
        await _repo.deleteById(item.id!);
      }
      await _load();
    } catch (e) {
      error = e;
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }

    if (!mounted) return;
    String message;
    if (error != null) {
      message = '${context.l10nTextRead('Retry failed')}: $error';
    } else if (result?.status == ParseStatus.success) {
      message = context.l10nTextRead('Retry succeeded');
    } else if (result?.status == ParseStatus.duplicate) {
      message = context.l10nTextRead('Duplicate still exists');
    } else {
      message =
          '${context.l10nTextRead('Retry failed')}: ${result?.reason ?? context.l10nTextRead('Unknown error')}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _retryBulk(List<FailedParse> items) async {
    if (_retrying || items.isEmpty) return;
    setState(() => _retrying = true);

    int success = 0;
    int duplicate = 0;
    int failed = 0;
    int errors = 0;
    final idsToDelete = <int>[];
    Object? batchError;

    try {
      for (final item in items) {
        try {
          final result = await SmsService.retryFailedParse(
            item.body,
            item.address,
            messageDate: DateTime.tryParse(item.timestamp),
          );
          if (result.status == ParseStatus.success) {
            success++;
            if (item.id != null) {
              idsToDelete.add(item.id!);
            }
          } else if (result.status == ParseStatus.duplicate) {
            duplicate++;
          } else {
            failed++;
          }
        } catch (_) {
          errors++;
        }
      }

      if (idsToDelete.isNotEmpty) {
        await _repo.deleteByIds(idsToDelete);
      }
      await _load();
    } catch (e) {
      batchError = e;
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }

    if (!mounted) return;
    if (batchError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10nTextRead('Retry failed')}: $batchError'),
        ),
      );
      return;
    }

    final total = items.length;
    final summary = [
      '${context.l10nTextRead('Retried')} $total',
      if (success > 0) '${context.l10nTextRead('success')}: $success',
      if (duplicate > 0) '${context.l10nTextRead('duplicates')}: $duplicate',
      if (failed > 0) '${context.l10nTextRead('failed')}: $failed',
      if (errors > 0) '${context.l10nTextRead('errors')}: $errors',
    ].join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  void _openGroup(_FailedParseGroup group) {
    _searchController.clear();
    setState(() => _selectedGroupKey = group.key);
  }

  void _closeGroup() {
    _searchController.clear();
    setState(() {
      _selectedGroupKey = null;
      _selectedCardIds.clear();
    });
  }

  // ── Overview ──────────────────────────────────────────────────────────────

  Widget _buildOverview() {
    final theme = Theme.of(context);
    final groups = _groups;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryLight,
          strokeWidth: 2.5,
        ),
      );
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.check_circle_rounded,
              size: 48,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10nText('No failed parsings'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10nText('All transaction messages are being parsed.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryLight,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          return _FailedParseBankCard(
            group: group,
            onTap: () => _openGroup(group),
          );
        },
      ),
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  Widget _buildDetail(_FailedParseGroup group) {
    final visibleItems = _visibleItems;
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: AppColors.textPrimary(context)),
            decoration: InputDecoration(
              hintText: context.l10nText('Filter messages...'),
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              prefixIcon: Icon(
                AppIcons.filter_list,
                color: AppColors.textTertiary(context),
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10nText('Clear'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: Icon(
                        AppIcons.close_rounded,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
              filled: true,
              fillColor: AppColors.cardColor(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primaryLight,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: _FailedParseSummaryCard(group: group),
        ),
        Expanded(
          child: visibleItems.isEmpty
              ? Center(
                  child: Text(
                    hasSearch
                        ? context.l10nText('No transactions match your search.')
                        : context.l10nText(
                            'No transactions without patterns for this bank.',
                          ),
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primaryLight,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildParseCard(visibleItems[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  bool get _isSelecting => _selectedCardIds.isNotEmpty;

  void _toggleCardSelection(FailedParse item) {
    if (item.id == null) return;
    setState(() {
      if (!_selectedCardIds.remove(item.id!)) {
        _selectedCardIds.add(item.id!);
      }
    });
  }

  Future<void> _clearSelectedCards() async {
    final ids = _selectedCardIds.toList();
    if (ids.isEmpty) return;
    final items = _visibleItems
        .where((item) => item.id != null && _selectedCardIds.contains(item.id))
        .toList(growable: false);
    await _deleteItems(items, clearSelection: true);
  }

  Future<void> _copySelectedCards() async {
    final items = _visibleItems
        .where((i) => i.id != null && _selectedCardIds.contains(i.id))
        .toList();
    if (items.isEmpty) return;

    final buffer = StringBuffer();
    for (var idx = 0; idx < items.length; idx++) {
      final item = items[idx];
      buffer.writeln('Sender: ${item.address}');
      buffer.writeln('Reason: ${item.reason}');
      buffer.writeln('Time: ${item.timestamp}');
      buffer.writeln();
      buffer.writeln(item.body);
      if (idx < items.length - 1) {
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          items.length == 1
              ? context.l10nTextRead('Copied 1 message')
              : '${context.l10nTextRead('Copied')} ${items.length} ${context.l10nTextRead('messages')}',
        ),
      ));
  }

  Future<void> _retrySelectedCards() async {
    final items = _visibleItems
        .where((i) => i.id != null && _selectedCardIds.contains(i.id))
        .toList();
    if (items.isEmpty) return;
    setState(() => _selectedCardIds.clear());
    await _retryBulk(items);
  }

  Widget _buildParseCard(FailedParse item) {
    final selected = item.id != null && _selectedCardIds.contains(item.id);
    return _FailedParseCard(
      key:
          ValueKey(item.id ?? '${item.address}|${item.timestamp}|${item.body}'),
      item: item,
      retrying: _retrying,
      formattedTimestamp: _formatTimestamp(item.timestamp),
      onRetry: () => _retrySingle(item),
      onCopy: _copy,
      selected: selected,
      selecting: _isSelecting,
      onSelect: () => _toggleCardSelection(item),
    );
  }

  // ── Scaffold ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedGroup = _selectedGroup;
    final visibleItems = _visibleItems;
    final selectedGroupLabel =
        selectedGroup == null ? null : context.l10nText(selectedGroup.label);
    final retryTooltip = selectedGroup == null
        ? context.l10nText('Retry all banks')
        : _searchController.text.trim().isNotEmpty
            ? context.l10nText('Retry filtered')
            : '${context.l10nText('Retry')} $selectedGroupLabel';
    final clearTooltip = selectedGroup == null
        ? context.l10nText('Clear all banks')
        : _searchController.text.trim().isNotEmpty
            ? context.l10nText('Clear filtered')
            : '${context.l10nText('Clear')} $selectedGroupLabel';

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        leading: IconButton(
          onPressed: _isSelecting
              ? () => setState(() => _selectedCardIds.clear())
              : selectedGroup == null
                  ? () => Navigator.pop(context)
                  : _closeGroup,
          icon: Icon(
            _isSelecting ? AppIcons.close_rounded : AppIcons.arrow_back_rounded,
          ),
        ),
        title: Text(
          _isSelecting
              ? '${_selectedCardIds.length} ${context.l10nText('selected')}'
              : selectedGroup == null
                  ? context.l10nText('Failed Parsings')
                  : '$selectedGroupLabel ${context.l10nText('Patterns')}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(context),
          ),
        ),
        backgroundColor: AppColors.background(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _isSelecting
            ? [
                TextButton(
                  onPressed: () {
                    final allIds =
                        visibleItems.map((i) => i.id).whereType<int>().toSet();
                    setState(() {
                      if (_selectedCardIds.length == allIds.length &&
                          _selectedCardIds.containsAll(allIds)) {
                        _selectedCardIds.clear();
                      } else {
                        _selectedCardIds
                          ..clear()
                          ..addAll(allIds);
                      }
                    });
                  },
                  child: Text(
                    context.l10nText('All'),
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  tooltip: retryTooltip,
                  onPressed: _retrying || visibleItems.isEmpty
                      ? null
                      : () => _retryBulk(visibleItems),
                  icon: Icon(
                    AppIcons.refresh,
                    color: _retrying || visibleItems.isEmpty
                        ? AppColors.textTertiary(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
                IconButton(
                  tooltip: clearTooltip,
                  onPressed: visibleItems.isEmpty
                      ? null
                      : () => _clearItems(visibleItems),
                  icon: Icon(
                    AppIcons.delete_outline_rounded,
                    color: visibleItems.isEmpty
                        ? AppColors.textTertiary(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
              ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_retrying)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primaryLight,
                  backgroundColor:
                      AppColors.primaryLight.withValues(alpha: 0.15),
                ),
              Expanded(
                child: selectedGroup == null
                    ? _buildOverview()
                    : _buildDetail(selectedGroup),
              ),
            ],
          ),
          if (_isSelecting)
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: _SelectionBottomBar(
                count: _selectedCardIds.length,
                onCopy: _copySelectedCards,
                onInvert: () {
                  final allIds =
                      visibleItems.map((i) => i.id).whereType<int>().toSet();
                  setState(() {
                    final inverted = allIds.difference(_selectedCardIds);
                    _selectedCardIds
                      ..clear()
                      ..addAll(inverted);
                  });
                },
                onRetry: _retrying ? null : _retrySelectedCards,
                onDelete: _clearSelectedCards,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Parse Card ────────────────────────────────────────────────────────────────

class _FailedParseCard extends StatefulWidget {
  final FailedParse item;
  final bool retrying;
  final String formattedTimestamp;
  final VoidCallback onRetry;
  final Future<void> Function(FailedParse item) onCopy;
  final bool selected;
  final bool selecting;
  final VoidCallback onSelect;

  const _FailedParseCard({
    super.key,
    required this.item,
    required this.retrying,
    required this.formattedTimestamp,
    required this.onRetry,
    required this.onCopy,
    required this.selected,
    required this.selecting,
    required this.onSelect,
  });

  @override
  State<_FailedParseCard> createState() => _FailedParseCardState();
}

class _FailedParseCardState extends State<_FailedParseCard> {
  static final _rng = Random();
  static final _numRegex = RegExp(r'\d');

  late final List<String> _tokens;
  late final Set<int> _numberIndices;
  final Set<int> _hidden = {};
  final Map<int, String> _scrambled = {};

  @override
  void initState() {
    super.initState();
    _syncTokensFromItem();
  }

  @override
  void didUpdateWidget(covariant _FailedParseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.body != widget.item.body ||
        oldWidget.item.timestamp != widget.item.timestamp ||
        oldWidget.item.address != widget.item.address) {
      _syncTokensFromItem();
    }
  }

  static List<String> _tokenize(String text) {
    final tokens = <String>[];
    final regex = RegExp(r'(\S+|\s+)');
    for (final match in regex.allMatches(text)) {
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  void _syncTokensFromItem() {
    _tokens = _tokenize(widget.item.body);
    _numberIndices = {
      for (var i = 0; i < _tokens.length; i++)
        if (_numRegex.hasMatch(_tokens[i])) i,
    };
    _hidden.clear();
    _scrambled.clear();
  }

  static String _scramble(String token) {
    final buf = StringBuffer();
    for (final c in token.codeUnits) {
      if (c >= 65 && c <= 90) {
        buf.writeCharCode(65 + _rng.nextInt(26));
      } else if (c >= 97 && c <= 122) {
        buf.writeCharCode(97 + _rng.nextInt(26));
      } else if (c >= 48 && c <= 57) {
        buf.writeCharCode(48 + _rng.nextInt(10));
      } else {
        buf.writeCharCode(c);
      }
    }
    return buf.toString();
  }

  String _getScrambled(int index) {
    return _scrambled.putIfAbsent(index, () => _scramble(_tokens[index]));
  }

  String _buildCopyText() {
    final buffer = StringBuffer();
    for (var i = 0; i < _tokens.length; i++) {
      if (_hidden.contains(i)) {
        buffer.write(_getScrambled(i));
      } else {
        buffer.write(_tokens[i]);
      }
    }
    return buffer.toString();
  }

  String _buildTelegramShareText() {
    final body = _buildCopyText().trim();
    return [
      body,
      '',
      'Sender: ${widget.item.address}',
      'Time: ${widget.item.timestamp}',
      'Reason: ${widget.item.reason}',
      'Source: Totals failed parsing page',
    ].join('\n');
  }

  Uri _buildTelegramAppDraftUri(String text) {
    return Uri.parse(
      'tg://resolve?domain=$_telegramBotUsername&text=${Uri.encodeQueryComponent(text)}',
    );
  }

  Uri _buildTelegramWebDraftUri(String text) {
    return Uri.https('t.me', '/$_telegramBotUsername', {'text': text});
  }

  Uri _buildTelegramShareUri(String text) {
    return Uri.https('t.me', '/share/url', {
      'url': _telegramBotUrl,
      'text': text,
    });
  }

  Future<bool> _launchTelegramUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(uri);
      } catch (_) {
        return false;
      }
    }
  }

  void _scrambleNumbers() {
    setState(() {
      for (final i in _numberIndices) {
        _hidden.add(i);
      }
    });
  }

  void _unscrambleAll() {
    setState(() {
      _hidden.clear();
      _scrambled.clear();
    });
  }

  void _longPressChip(int index) {
    final isNumber = _numberIndices.contains(index);
    setState(() {
      for (var i = 0; i < _tokens.length; i++) {
        if (_tokens[i].trim().isEmpty) continue;
        if (_numberIndices.contains(i) == isNumber) {
          _hidden.add(i);
        }
      }
    });
  }

  Future<void> _copyWithRedactions() async {
    final text = [
      'Sender: ${widget.item.address}',
      'Reason: ${widget.item.reason}',
      'Time: ${widget.item.timestamp}',
      '',
      _buildCopyText(),
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(context.l10nTextRead('Transaction copied'))),
      );
  }

  Future<void> _shareToTelegram() async {
    final text = _buildTelegramShareText();
    await Clipboard.setData(ClipboardData(text: text));

    var opened = await _launchTelegramUri(_buildTelegramAppDraftUri(text));
    if (!opened) {
      opened = await _launchTelegramUri(_buildTelegramWebDraftUri(text));
    }
    if (!opened) {
      opened = await _launchTelegramUri(_buildTelegramShareUri(text));
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (opened) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead(
              'Telegram opened with the message loaded. The text was also copied to the clipboard.',
            ),
          ),
        ),
      );
      return;
    }

    try {
      await Share.share(
        text,
        subject: context.l10nTextRead('Failed parsing message'),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead(
              'Telegram could not be opened directly. A share sheet was opened and the text was copied to the clipboard.',
            ),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10nTextRead(
              'Telegram could not be opened. The text was copied to the clipboard.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHidden = _hidden.isNotEmpty;

    final scrambledBg = AppColors.amber.withValues(alpha: 0.12);
    final scrambledFg = AppColors.isDark(context)
        ? AppColors.amber.withValues(alpha: 0.7)
        : AppColors.amber.withValues(alpha: 0.55);

    final isSelected = widget.selected;

    return GestureDetector(
      onLongPress: widget.onSelect,
      onTap: widget.selecting ? widget.onSelect : _copyWithRedactions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLight.withValues(alpha: 0.06)
              : AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight.withValues(alpha: 0.5)
                : AppColors.borderColor(context),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
              children: [
                if (widget.selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      isSelected
                          ? AppIcons.check_circle_rounded
                          : AppIcons.add_circle_outline,
                      size: 20,
                      color: isSelected
                          ? AppColors.primaryLight
                          : AppColors.textTertiary(context),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.l10nText(FailedParse.noMatchingPatternReason),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                    ),
                  ),
                ),
                const Spacer(),
                if (!widget.selecting)
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: _copyWithRedactions,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          AppIcons.copy,
                          size: 22,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Token chips ──
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < _tokens.length; i++)
                  if (_tokens[i].trim().isNotEmpty)
                    GestureDetector(
                      onTap: widget.selecting
                          ? null
                          : () {
                              setState(() {
                                if (_hidden.contains(i)) {
                                  _hidden.remove(i);
                                } else {
                                  _hidden.add(i);
                                }
                              });
                            },
                      onLongPress:
                          widget.selecting ? null : () => _longPressChip(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _hidden.contains(i)
                              ? scrambledBg
                              : AppColors.mutedFill(context),
                          borderRadius: BorderRadius.circular(6),
                          border: _hidden.contains(i)
                              ? Border.all(
                                  color:
                                      AppColors.amber.withValues(alpha: 0.25),
                                )
                              : null,
                        ),
                        child: Text(
                          _hidden.contains(i) ? _getScrambled(i) : _tokens[i],
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: _hidden.contains(i)
                                ? scrambledFg
                                : AppColors.textSecondary(context),
                            fontWeight: _hidden.contains(i)
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Quick actions row ──
            if (!widget.selecting)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _QuickAction(
                    label: context.l10nText('Share to Telegram'),
                    icon: Icons.share_outlined,
                    color: AppColors.primaryLight,
                    onTap: _shareToTelegram,
                  ),
                  if (_numberIndices.isNotEmpty &&
                      !_numberIndices.every(_hidden.contains))
                    _QuickAction(
                      label: context.l10nText('Scramble numbers'),
                      icon: AppIcons.visibility_off_outlined,
                      color: AppColors.amber,
                      onTap: _scrambleNumbers,
                    ),
                  if (hasHidden)
                    _QuickAction(
                      label: context.l10nText('Unscramble all'),
                      icon: AppIcons.visibility_outlined,
                      color: AppColors.primaryLight,
                      onTap: _unscrambleAll,
                    ),
                ],
              ),
            if (!hasHidden && !widget.selecting) ...[
              const SizedBox(height: 6),
              Text(
                context.l10nText(
                  'Tap to scramble - Long-press to scramble similar',
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // ── Footer row ──
            Row(
              children: [
                Icon(
                  AppIcons.schedule_rounded,
                  size: 14,
                  color: AppColors.textTertiary(context),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    widget.formattedTimestamp,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
                if (!widget.selecting)
                  Material(
                    color: AppColors.primaryLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.retrying ? null : widget.onRetry,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.refresh,
                              size: 15,
                              color: AppColors.primaryLight,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              context.l10nText('Retry'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selection Bottom Bar ──────────────────────────────────────────────────────

class _SelectionBottomBar extends StatelessWidget {
  final int count;
  final VoidCallback onCopy;
  final VoidCallback onInvert;
  final VoidCallback? onRetry;
  final VoidCallback onDelete;

  const _SelectionBottomBar({
    required this.count,
    required this.onCopy,
    required this.onInvert,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BottomBarAction(
            icon: AppIcons.copy,
            label: context.l10nText('Copy'),
            onTap: count > 0 ? onCopy : null,
          ),
          _BottomBarAction(
            icon: AppIcons.swap,
            label: context.l10nText('Invert'),
            onTap: onInvert,
          ),
          _BottomBarAction(
            icon: AppIcons.refresh,
            label: context.l10nText('Retry'),
            onTap: count > 0 ? onRetry : null,
          ),
          _BottomBarAction(
            icon: AppIcons.delete_outline_rounded,
            label: context.l10nText('Delete'),
            color: AppColors.red,
            onTap: count > 0 ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

class _BottomBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _BottomBarAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final effectiveColor = isDisabled
        ? AppColors.textTertiary(context)
        : color ?? AppColors.textSecondary(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: effectiveColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Action Chip ─────────────────────────────────────────────────────────

enum _FailedParseDeleteChoice {
  selectedOnly,
  selectedAndSimilar,
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class _FailedParseGroup {
  final String key;
  final Bank? bank;
  final List<FailedParse> items;

  const _FailedParseGroup({
    required this.key,
    required this.bank,
    required this.items,
  });

  String get label => bank?.shortName ?? 'Unknown bank';
}

// ── Bank Card (Overview) ──────────────────────────────────────────────────────

class _FailedParseBankCard extends StatelessWidget {
  final _FailedParseGroup group;
  final VoidCallback onTap;

  const _FailedParseBankCard({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            children: [
              _BankLogo(bank: group.bank, darkForeground: false, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10nText(group.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      group.items.length == 1
                          ? context.l10nText('1 unmatched transaction')
                          : '${group.items.length} ${context.l10nText('unmatched transactions')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.items.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                AppIcons.chevron_right_rounded,
                color: AppColors.textTertiary(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary Card (Detail header) ─────────────────────────────────────────────

class _FailedParseSummaryCard extends StatelessWidget {
  final _FailedParseGroup group;

  const _FailedParseSummaryCard({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final bank = group.bank;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _BankLogo(bank: bank, darkForeground: false, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10nText(group.label),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  group.items.length == 1
                      ? context.l10nText(
                          '1 transaction without a matching pattern',
                        )
                      : '${group.items.length} ${context.l10nText('transactions without matching patterns')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank Logo ─────────────────────────────────────────────────────────────────

class _BankLogo extends StatelessWidget {
  final Bank? bank;
  final bool darkForeground;
  final double size;

  const _BankLogo({
    required this.bank,
    required this.darkForeground,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(10);
    final backgroundColor = darkForeground
        ? Colors.white.withValues(alpha: 0.18)
        : AppColors.mutedFill(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: bank == null
          ? Icon(
              AppIcons.account_balance_rounded,
              size: size * 0.52,
              color: AppColors.primaryLight,
            )
          : Padding(
              padding: EdgeInsets.all(size * 0.18),
              child: Image.asset(
                bank!.image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    AppIcons.account_balance_rounded,
                    size: size * 0.52,
                    color:
                        darkForeground ? Colors.white : AppColors.primaryLight,
                  );
                },
              ),
            ),
    );
  }
}
