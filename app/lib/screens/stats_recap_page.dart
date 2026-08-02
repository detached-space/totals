import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:totals/utils/share_position.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/text_utils.dart';

class StatsRecapPage extends StatefulWidget {
  const StatsRecapPage({super.key});

  @override
  State<StatsRecapPage> createState() => _StatsRecapPageState();
}

class _StatsRecapPageState extends State<StatsRecapPage> {
  static const int _recapYear = 2025;
  final BankConfigService _bankConfigService = BankConfigService();
  List<Bank> _banks = [];

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await _bankConfigService.getBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
      });
    } catch (_) {
      // Ignore bank load errors; placeholders will show.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final data = StatsRecapData.from(
          transactions: provider.allTransactions,
          banks: _banks,
          year: _recapYear,
        );

        return Scaffold(
          backgroundColor: const Color(0xFF0F1014),
          body: StatsRecapContent(data: data),
        );
      },
    );
  }
}

class StatsRecapContent extends StatefulWidget {
  final StatsRecapData data;

  const StatsRecapContent({
    super.key,
    required this.data,
  });

  @override
  State<StatsRecapContent> createState() => _StatsRecapContentState();
}

class _StatsRecapContentState extends State<StatsRecapContent> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _isCapturing = false;

  Future<void> _captureAndShare() async {
    setState(() {
      _isCapturing = true;
    });

    try {
      // Wait a bit for UI to settle
      await Future.delayed(const Duration(milliseconds: 300));

      final RenderRepaintBoundary boundary =
          _repaintBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save to temporary directory
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/recap_${widget.data.year}_${DateTime.now().millisecondsSinceEpoch}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(pngBytes);

      // Share the image
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'My ${widget.data.year} Totals Recap!',
        sharePositionOrigin: sharePositionOriginFor(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing recap: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1014),
      ),
      child: Stack(
        children: [
          // Background accents
          Positioned(
            top: -100,
            right: -100,
            child: _BlurredAccent(
              color: const Color(0xFF2E6DF6).withOpacity(0.2),
              size: 400,
            ),
          ),
          Positioned(
            bottom: -150,
            left: -150,
            child: _BlurredAccent(
              color: const Color(0xFFFF5252).withOpacity(0.15),
              size: 500,
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 100),
                    child: RepaintBoundary(
                      key: _repaintBoundaryKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'THE FULL RECAP',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    color: Colors.white.withOpacity(0.4),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Your Year in totals',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Text(
                                '${widget.data.year}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),
                        
                        // Bank Section
                        Center(
                          child: Column(
                            children: [
                              Text(
                                'MOST USED BANKS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _BankCluster(banks: widget.data.topBanks),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 48),
                        
                        // Table-like sections for sent/received
                        _ModernCounterpartyGrid(
                          sentTo: widget.data.topSentTo,
                          receivedFrom: widget.data.topReceivedFrom,
                        ),
                        
                        const SizedBox(height: 48),
                        
                        // Footer
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'TOTALS WRAPPED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
                // Save and Share Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1014),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isCapturing ? null : _captureAndShare,
                            icon: _isCapturing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.share_rounded),
                            label: Text(_isCapturing ? 'Preparing...' : 'Save & Share'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F1014),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _BlurredAccent extends StatelessWidget {
  final Color color;
  final double size;

  const _BlurredAccent({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

class _ModernCounterpartyGrid extends StatelessWidget {
  final List<StatsRecapEntry> sentTo;
  final List<StatsRecapEntry> receivedFrom;

  const _ModernCounterpartyGrid({
    required this.sentTo,
    required this.receivedFrom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSection(context, 'TOP TRANSFERRED TO', sentTo, const Color(0xFFFF5252)),
        const SizedBox(height: 32),
        _buildSection(context, 'TOP RECEIVED FROM', receivedFrom, const Color(0xFF00C853)),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<StatsRecapEntry> entries, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  'No data available for this year.',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                ),
              )
            else
              ...entries.asMap().entries.map((e) => _buildEntryRow(e.key, e.value, color)),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryRow(int index, StatsRecapEntry entry, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'ETB ${formatNumberWithComma(entry.amount)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class StatsRecapData {
  final int year;
  final String monthLabel;
  final List<Bank> topBanks;
  final List<StatsRecapEntry> topSentTo;
  final List<StatsRecapEntry> topReceivedFrom;

  const StatsRecapData({
    required this.year,
    required this.monthLabel,
    required this.topBanks,
    required this.topSentTo,
    required this.topReceivedFrom,
  });

  factory StatsRecapData.from({
    required List<Transaction> transactions,
    required List<Bank> banks,
    required int year,
  }) {
    final filtered = _filterTransactionsForYear(transactions, year);
    final topBanks = _topBanks(filtered, banks);
    final sentTo = _topSentTo(filtered);
    final receivedFrom = _topReceivedFrom(filtered);
    final monthLabel = DateFormat('MMMM').format(
      DateTime(year, DateTime.now().month),
    );

    return StatsRecapData(
      year: year,
      monthLabel: monthLabel,
      topBanks: topBanks,
      topSentTo: sentTo,
      topReceivedFrom: receivedFrom,
    );
  }

  static DateTime? _parseTransactionDate(Transaction transaction) {
    final raw = transaction.time;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  static bool _isIncome(Transaction transaction) {
    final type = transaction.type?.toUpperCase() ?? '';
    if (type.contains('CREDIT')) return true;
    if (type.contains('DEBIT')) return false;
    return transaction.amount >= 0;
  }

  static String? _cleanCounterparty(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static bool _telebirrSenderHasPhone(String sender) {
    final hasParens = sender.contains('(') && sender.contains(')');
    final hasDigits = RegExp(r'\d').hasMatch(sender);
    return hasParens && hasDigits;
  }

  static String _normalizeTelebirrName(Transaction transaction, String name) {
    if (transaction.bankId == 6) {
      return formatTelebirrSenderName(name);
    }
    return name;
  }

  static List<Transaction> _filterTransactionsForYear(
    List<Transaction> transactions,
    int year,
  ) {
    final filtered = <Transaction>[];
    for (final transaction in transactions) {
      final date = _parseTransactionDate(transaction);
      if (date == null) continue;
      if (date.year == year) {
        filtered.add(transaction);
      }
    }
    return filtered;
  }

  static List<StatsRecapEntry> _topSentTo(List<Transaction> transactions) {
    final totals = <String, double>{};
    for (final transaction in transactions) {
      if (_isIncome(transaction)) continue;
      final raw = _cleanCounterparty(transaction.receiver) ??
          _cleanCounterparty(transaction.creditor);
      if (raw == null) continue;
      final label = _normalizeTelebirrName(transaction, raw);
      totals.update(
        label,
        (value) => value + transaction.amount.abs(),
        ifAbsent: () => transaction.amount.abs(),
      );
    }
    return _topCounterparties(totals);
  }

  static List<StatsRecapEntry> _topReceivedFrom(
    List<Transaction> transactions,
  ) {
    final totals = <String, double>{};
    for (final transaction in transactions) {
      if (!_isIncome(transaction)) continue;
      final raw = _cleanCounterparty(transaction.creditor) ??
          _cleanCounterparty(transaction.receiver);
      if (raw == null) continue;
      if (transaction.bankId == 6 && !_telebirrSenderHasPhone(raw)) {
        continue;
      }
      final label = _normalizeTelebirrName(transaction, raw);
      totals.update(
        label,
        (value) => value + transaction.amount.abs(),
        ifAbsent: () => transaction.amount.abs(),
      );
    }
    return _topCounterparties(totals);
  }

  static List<StatsRecapEntry> _topCounterparties(
    Map<String, double> totals,
  ) {
    final entries = totals.entries
        .map((entry) => StatsRecapEntry(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return entries.take(5).toList();
  }

  static List<Bank> _topBanks(
    List<Transaction> transactions,
    List<Bank> banks,
  ) {
    final counts = <int, int>{};
    for (final transaction in transactions) {
      final bankId = transaction.bankId;
      if (bankId == null) continue;
      counts.update(bankId, (value) => value + 1, ifAbsent: () => 1);
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final banksById = {
      for (final bank in banks) bank.id: bank,
    };
    final top = <Bank>[];
    for (final entry in sorted) {
      final bank = banksById[entry.key];
      if (bank != null) {
        top.add(bank);
      }
      if (top.length == 3) break;
    }
    return top;
  }
}

class _BankCluster extends StatelessWidget {
  final List<Bank> banks;

  const _BankCluster({required this.banks});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
           if (index < banks.length) {
             return Padding(
               padding: const EdgeInsets.symmetric(horizontal: 10),
               child: _BankBubble(bank: banks[index], size: index == 0 ? 100 : 70),
             );
           } else {
             return Padding(
               padding: const EdgeInsets.symmetric(horizontal: 10),
               child: _PlaceholderBubble(size: 70, label: ''),
             );
           }
        }),
      ),
    );
  }
}

class _BankBubble extends StatelessWidget {
  final Bank bank;
  final double size;

  const _BankBubble({
    required this.bank,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          bank.image,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _PlaceholderBubble extends StatelessWidget {
  final double size;
  final String label;

  const _PlaceholderBubble({
    required this.size,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.3),
          ),
        ),
      ),
    );
  }
}

class StatsRecapEntry {
  final String label;
  final double amount;

  const StatsRecapEntry(this.label, this.amount);
}
