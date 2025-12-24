import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/failed_parse.dart';
import 'package:totals/repositories/failed_parse_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/sms_service.dart';

class FailedParsesPage extends StatefulWidget {
  const FailedParsesPage({super.key});

  @override
  State<FailedParsesPage> createState() => _FailedParsesPageState();
}

class _FailedParsesPageState extends State<FailedParsesPage> {
  final FailedParseRepository _repo = FailedParseRepository();
  final TextEditingController _searchController = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();

  bool _loading = true;
  bool _retrying = false;
  List<FailedParse> _items = const [];
  List<Bank> _banks = const [];
  int? _selectedBankId;
  final Map<String, Bank?> _bankByAddress = {};

  static const int _unknownBankId = -1;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBanks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.getAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      _bankByAddress.clear();
    });
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _bankByAddress.clear();
      });
    } catch (e) {
      print("debug: Error loading banks: $e");
    }
  }

  Future<void> _clearAll() async {
    await _repo.clear();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared failed parsings')),
    );
  }

  List<FailedParse> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    Iterable<FailedParse> results = _items;
    if (q.isNotEmpty) {
      results = results.where((i) {
        return i.address.toLowerCase().contains(q) ||
            i.reason.toLowerCase().contains(q) ||
            i.body.toLowerCase().contains(q) ||
            i.timestamp.toLowerCase().contains(q);
      });
    }
    if (_selectedBankId != null) {
      results = results.where((item) {
        final bank = _resolveBank(item);
        if (_selectedBankId == _unknownBankId) {
          return bank == null;
        }
        return bank?.id == _selectedBankId;
      });
    }
    return results.toList(growable: false);
  }

  Bank? _resolveBank(FailedParse item) {
    if (_banks.isEmpty) return null;
    return _bankByAddress.putIfAbsent(item.address, () {
      for (final bank in _banks) {
        for (final code in bank.codes) {
          if (item.address.contains(code)) {
            return bank;
          }
        }
      }
      return null;
    });
  }

  List<Bank> get _availableBanks {
    if (_banks.isEmpty) return const [];
    final ids = <int>{};
    for (final item in _items) {
      final bank = _resolveBank(item);
      if (bank != null) {
        ids.add(bank.id);
      }
    }
    final banks = _banks.where((bank) => ids.contains(bank.id)).toList();
    banks.sort((a, b) => a.shortName.compareTo(b.shortName));
    return banks;
  }

  bool get _hasUnknownBank {
    if (_banks.isEmpty) return false;
    return _items.any((item) => _resolveBank(item) == null);
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
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  String _formatTimestamp(String timestamp) {
    final dateTime = DateTime.tryParse(timestamp);
    if (dateTime == null) return timestamp;
    return DateFormat('h:mm a, MMM/dd/yyyy').format(dateTime).toLowerCase();
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
      message = 'Retry failed: $error';
    } else if (result?.status == ParseStatus.success) {
      message = 'Retry succeeded';
    } else if (result?.status == ParseStatus.duplicate) {
      message = 'Duplicate still exists (kept failed parse)';
    } else {
      message = 'Retry failed: ${result?.reason ?? 'Unknown error'}';
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
        SnackBar(content: Text('Retry failed: $batchError')),
      );
      return;
    }

    final total = items.length;
    final summary = [
      'Retried $total',
      if (success > 0) 'success: $success',
      if (duplicate > 0) 'duplicates kept: $duplicate',
      if (failed > 0) 'failed: $failed',
      if (errors > 0) 'errors: $errors',
    ].join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  Widget _buildBankFilters() {
    final availableBanks = _availableBanks;
    final showUnknown = _hasUnknownBank;
    if (availableBanks.isEmpty && !showUnknown) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
            context,
            'All',
            _selectedBankId == null,
            onTap: () => setState(() => _selectedBankId = null),
          ),
          const SizedBox(width: 8),
          if (showUnknown) ...[
            _buildFilterChip(
              context,
              'Unknown',
              _selectedBankId == _unknownBankId,
              onTap: () => setState(() => _selectedBankId = _unknownBankId),
            ),
            const SizedBox(width: 8),
          ],
          ...availableBanks.map((bank) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildFilterChip(
                context,
                bank.shortName,
                _selectedBankId == bank.id,
                onTap: () => setState(() => _selectedBankId = bank.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    bool isSelected, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final hasActiveFilters =
        _searchController.text.trim().isNotEmpty || _selectedBankId != null;
    final retryTooltip = hasActiveFilters ? 'Retry filtered' : 'Retry all';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Failed parsings'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: retryTooltip,
            onPressed: _retrying || filtered.isEmpty
                ? null
                : () => _retryBulk(List<FailedParse>.from(filtered)),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Clear all',
            onPressed: _items.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_retrying)
            const LinearProgressIndicator(
              minHeight: 2,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search sender, reason, or message…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildBankFilters(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _items.isEmpty
                              ? 'No failed parsings.'
                              : 'No results found.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _copy(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.address,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.copy_rounded,
                                            size: 18,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        item.reason,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item.body,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatTimestamp(item.timestamp),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Tap to copy',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          TextButton.icon(
                                            onPressed: _retrying
                                                ? null
                                                : () => _retrySingle(item),
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Retry'),
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(0, 0),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
