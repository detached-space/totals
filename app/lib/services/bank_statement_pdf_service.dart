import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:totals/models/transaction.dart';
import 'package:totals/utils/transaction_amounts.dart';

const String totalsStatementUrl = 'https://totals.detached.space/';

enum BankStatementPdfProgressStage {
  loadingAssets,
  preparingDocument,
  processingTransactions,
  layingOutPages,
  finalizingDocument,
  complete,
}

class BankStatementPdfProgress {
  final double value;
  final BankStatementPdfProgressStage stage;
  final int? processed;
  final int? total;

  const BankStatementPdfProgress({
    required this.value,
    required this.stage,
    this.processed,
    this.total,
  });
}

typedef BankStatementPdfProgressCallback = void Function(
  BankStatementPdfProgress progress,
);

class BankStatementEntry {
  final Transaction transaction;
  final DateTime occurredAt;
  final String description;
  final double balance;

  const BankStatementEntry({
    required this.transaction,
    required this.occurredAt,
    required this.description,
    required this.balance,
  });

  bool get isDebit => transaction.type?.toUpperCase() == 'DEBIT';

  bool get isCredit => transaction.type?.toUpperCase() == 'CREDIT';

  String get typeLabel {
    if (isDebit) return 'Debit';
    if (isCredit) return 'Credit';
    return 'Other';
  }

  double get amount {
    if (isDebit) return transactionDebitOutflow(transaction);
    return transaction.amount.abs();
  }

  String get reference {
    final value = transaction.displayReference.trim();
    return value.isEmpty ? '-' : value;
  }
}

class BankStatementData {
  final String bankName;
  final String bankShortName;
  final String bankIconAssetPath;
  final String accountNumber;
  final String accountHolderName;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime generatedAt;
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
  final List<BankStatementEntry> entries;

  const BankStatementData({
    required this.bankName,
    required this.bankShortName,
    required this.bankIconAssetPath,
    required this.accountNumber,
    required this.accountHolderName,
    required this.startDate,
    required this.endDate,
    required this.generatedAt,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.entries,
  });

  String get fileName {
    final bankToken = bankShortName
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safeBankToken = bankToken.isEmpty ? 'BANK' : bankToken;
    return 'statement-$safeBankToken-'
        '${DateFormat('yyyy-MM-dd').format(generatedAt)}.pdf';
  }

  static BankStatementData fromTransactions({
    required String bankName,
    required String bankShortName,
    required String bankIconAssetPath,
    required String accountNumber,
    required String accountHolderName,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime generatedAt,
    required double currentAccountBalance,
    required Iterable<Transaction> transactions,
    Map<String, String> descriptionsByReference = const <String, String>{},
  }) {
    final rangeStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final normalizedEnd = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );
    final rangeEnd =
        normalizedEnd.isBefore(rangeStart) ? rangeStart : normalizedEnd;
    final rangeEndExclusive = rangeEnd.add(const Duration(days: 1));

    final timedTransactions = transactions
        .map((transaction) {
          final occurredAt = _parseTransactionTime(transaction.time);
          if (occurredAt == null) return null;
          return _TimedStatementTransaction(transaction, occurredAt);
        })
        .whereType<_TimedStatementTransaction>()
        .toList(growable: true)
      ..sort((left, right) {
        final timeComparison = left.occurredAt.compareTo(right.occurredAt);
        if (timeComparison != 0) return timeComparison;
        return left.transaction.reference.compareTo(
          right.transaction.reference,
        );
      });

    final resolvedBalances = _resolveRunningBalances(
      timedTransactions,
      currentAccountBalance,
    );
    final entries = <BankStatementEntry>[];
    final scopedIndexes = <int>[];
    var totalDebit = 0.0;
    var totalCredit = 0.0;

    for (var index = 0; index < timedTransactions.length; index++) {
      final timed = timedTransactions[index];
      if (timed.occurredAt.isBefore(rangeStart) ||
          !timed.occurredAt.isBefore(rangeEndExclusive)) {
        continue;
      }

      scopedIndexes.add(index);
      final entry = BankStatementEntry(
        transaction: timed.transaction,
        occurredAt: timed.occurredAt,
        description: _statementDescription(
          timed.transaction,
          descriptionsByReference,
        ),
        balance: resolvedBalances[index],
      );
      entries.add(entry);
      if (entry.isDebit) {
        totalDebit += entry.amount;
      } else if (entry.isCredit) {
        totalCredit += entry.amount;
      }
    }

    final double openingBalance;
    final double closingBalance;
    if (scopedIndexes.isNotEmpty) {
      final firstIndex = scopedIndexes.first;
      final lastIndex = scopedIndexes.last;
      openingBalance = resolvedBalances[firstIndex] -
          transactionBalanceDelta(
            timedTransactions[firstIndex].transaction,
          );
      closingBalance = resolvedBalances[lastIndex];
    } else {
      final balanceAtStart = _balanceImmediatelyBefore(
        timedTransactions: timedTransactions,
        resolvedBalances: resolvedBalances,
        instant: rangeStart,
        fallbackBalance: currentAccountBalance,
      );
      openingBalance = balanceAtStart;
      closingBalance = balanceAtStart;
    }

    return BankStatementData(
      bankName: bankName,
      bankShortName: bankShortName,
      bankIconAssetPath: bankIconAssetPath,
      accountNumber: accountNumber,
      accountHolderName: accountHolderName,
      startDate: rangeStart,
      endDate: rangeEnd,
      generatedAt: generatedAt,
      openingBalance: openingBalance,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      closingBalance: closingBalance,
      entries: List<BankStatementEntry>.unmodifiable(entries),
    );
  }
}

class BankStatementPdfService {
  static const _accent = PdfColor(0.42, 0.13, 0.66);
  static const _ink = PdfColor(0.10, 0.10, 0.18);
  static const _muted = PdfColor(0.42, 0.42, 0.48);
  static const _softMuted = PdfColor(0.58, 0.58, 0.63);
  static const _surface = PdfColor(0.96, 0.96, 0.97);
  static const _stripe = PdfColor(0.985, 0.985, 0.985);
  static const _divider = PdfColor(0.88, 0.88, 0.90);
  static const _debit = PdfColor(0.94, 0.27, 0.27);
  static const _credit = PdfColor(0.13, 0.67, 0.35);

  Future<Uint8List> generate(
    BankStatementData statement, {
    BankStatementPdfProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const BankStatementPdfProgress(
        value: 0,
        stage: BankStatementPdfProgressStage.loadingAssets,
      ),
    );
    final iconBytes = await Future.wait<Uint8List?>([
      _loadAssetBytes(statement.bankIconAssetPath),
      _loadAssetBytes('assets/icon/totals_icon.png'),
    ]);
    onProgress?.call(
      const BankStatementPdfProgress(
        value: 0.08,
        stage: BankStatementPdfProgressStage.preparingDocument,
      ),
    );
    return _renderInBackground(
      _BankStatementPdfRenderRequest(
        statement: statement,
        bankIconBytes: iconBytes[0],
        totalsIconBytes: iconBytes[1],
      ),
      onProgress: onProgress,
    );
  }

  Future<Uint8List> _renderInBackground(
    _BankStatementPdfRenderRequest request, {
    BankStatementPdfProgressCallback? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final completer = Completer<Uint8List>();

    final messageSubscription = receivePort.listen((dynamic message) {
      if (message is! List<Object?> || message.isEmpty) return;
      final messageType = message[0];

      if (messageType == _pdfProgressMessage &&
          message.length >= 5 &&
          message[1] is num &&
          message[2] is int) {
        final stageIndex = message[2]! as int;
        if (stageIndex < 0 ||
            stageIndex >= BankStatementPdfProgressStage.values.length) {
          return;
        }
        onProgress?.call(
          BankStatementPdfProgress(
            value: (message[1]! as num).toDouble(),
            stage: BankStatementPdfProgressStage.values[stageIndex],
            processed: message[3] as int?,
            total: message[4] as int?,
          ),
        );
        return;
      }

      if (messageType == _pdfResultMessage &&
          message.length >= 2 &&
          message[1] is TransferableTypedData) {
        if (!completer.isCompleted) {
          final data = message[1]! as TransferableTypedData;
          completer.complete(data.materialize().asUint8List());
        }
        return;
      }

      if (messageType == _pdfErrorMessage && message.length >= 3) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(message[1]?.toString() ?? 'PDF generation failed.'),
            StackTrace.fromString(message[2]?.toString() ?? ''),
          );
        }
      }
    });
    final errorSubscription = errorPort.listen((dynamic error) {
      if (completer.isCompleted) return;
      final values = error is List ? error : const <dynamic>[];
      completer.completeError(
        StateError(
          values.isEmpty
              ? 'PDF generation isolate failed.'
              : values.first.toString(),
        ),
        StackTrace.fromString(
          values.length > 1 ? values[1].toString() : '',
        ),
      );
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _renderBankStatementPdfInIsolate,
        _BankStatementPdfIsolateRequest(
          renderRequest: request,
          replyPort: receivePort.sendPort,
        ),
        debugName: 'bank-statement-pdf',
        errorsAreFatal: true,
        onError: errorPort.sendPort,
      );
      return await completer.future;
    } finally {
      isolate?.kill(priority: Isolate.immediate);
      await messageSubscription.cancel();
      await errorSubscription.cancel();
      receivePort.close();
      errorPort.close();
    }
  }

  Future<Uint8List> _render(
    _BankStatementPdfRenderRequest request,
    BankStatementPdfProgressCallback onProgress,
  ) async {
    final statement = request.statement;
    final bankIcon = _memoryImage(request.bankIconBytes);
    final totalsIcon = _memoryImage(request.totalsIconBytes);
    final document = pw.Document();
    var lastProgress = 0.08;
    var pageGenerationComplete = false;
    var lastReportedPage = 0;

    void report(
      BankStatementPdfProgressStage stage,
      double value, {
      int? processed,
      int? total,
    }) {
      final monotonicValue = value.clamp(lastProgress, 1.0).toDouble();
      lastProgress = monotonicValue;
      onProgress(
        BankStatementPdfProgress(
          value: monotonicValue,
          stage: stage,
          processed: processed,
          total: total,
        ),
      );
    }

    report(BankStatementPdfProgressStage.preparingDocument, 0.1);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 28),
        maxPages: 200,
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
        footer: (context) {
          if (pageGenerationComplete && context.pageNumber > lastReportedPage) {
            lastReportedPage = context.pageNumber;
            final totalPages = context.pagesCount;
            final pageRatio =
                totalPages <= 0 ? 1.0 : context.pageNumber / totalPages;
            report(
              BankStatementPdfProgressStage.layingOutPages,
              0.78 + (pageRatio * 0.18),
              processed: context.pageNumber,
              total: totalPages,
            );
          }
          return _buildFooter(
            context,
            statement: statement,
            totalsIcon: totalsIcon,
          );
        },
        build: (context) => [
          _buildHeader(statement, bankIcon),
          pw.SizedBox(height: 20),
          _buildSummary(statement),
          pw.SizedBox(height: 18),
          if (statement.entries.isEmpty)
            _buildEmptyState()
          else
            _buildTransactionTable(
              statement,
              onProgress: (processed, total) {
                final rowRatio = total <= 0 ? 1.0 : processed / total;
                report(
                  BankStatementPdfProgressStage.processingTransactions,
                  0.14 + (rowRatio * 0.6),
                  processed: processed,
                  total: total,
                );
              },
            ),
        ],
      ),
    );

    pageGenerationComplete = true;
    final totalPages = document.document.pdfPageList.pages.length;
    report(
      BankStatementPdfProgressStage.layingOutPages,
      0.78,
      processed: 0,
      total: totalPages,
    );
    final bytes = await document.save();
    report(BankStatementPdfProgressStage.finalizingDocument, 0.99);
    report(BankStatementPdfProgressStage.complete, 1);
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List?> _loadAssetBytes(String assetPath) async {
    if (assetPath.trim().isEmpty) return null;
    try {
      final data = await rootBundle.load(assetPath);
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      return null;
    }
  }

  pw.MemoryImage? _memoryImage(Uint8List? bytes) {
    return bytes == null ? null : pw.MemoryImage(bytes);
  }

  pw.Widget _buildHeader(
    BankStatementData statement,
    pw.MemoryImage? bankIcon,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _accent, width: 3),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (bankIcon != null) ...[
            pw.Container(
              width: 38,
              height: 38,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: _divider, width: 0.8),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Image(bankIcon, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfSafe(statement.bankName),
                  style: pw.TextStyle(
                    color: _accent,
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Account Statement',
                  style: const pw.TextStyle(
                    color: _muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                _pdfSafe(statement.accountHolderName.trim().isEmpty
                    ? 'Account holder'
                    : statement.accountHolderName),
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _pdfSafe(statement.accountNumber),
                style: const pw.TextStyle(color: _muted, fontSize: 10),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _dateRangeLabel(statement.startDate, statement.endDate),
                style: const pw.TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummary(BankStatementData statement) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _summaryBox(
            label: 'Opening Balance',
            value: _currency(statement.openingBalance),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _summaryBox(
            label: 'Total Debit',
            value: _currency(statement.totalDebit),
            valueColor: _debit,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _summaryBox(
            label: 'Total Credit',
            value: _currency(statement.totalCredit),
            valueColor: _credit,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _summaryBox(
            label: 'Closing Balance',
            value: _currency(statement.closingBalance),
          ),
        ),
      ],
    );
  }

  pw.Widget _summaryBox({
    required String label,
    required String value,
    PdfColor valueColor = _ink,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              color: _softMuted,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: valueColor,
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTransactionTable(
    BankStatementData statement, {
    required void Function(int processed, int total) onProgress,
  }) {
    final total = statement.entries.length;
    final progressInterval = total <= 80 ? 1 : (total / 80).ceil();
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _divider, width: 1.5),
          ),
        ),
        children: [
          _tableHeader('Date'),
          _tableHeader('Description'),
          _tableHeader('Reference'),
          _tableHeader('Type'),
          _tableHeader('Amount', alignRight: true),
          _tableHeader('Balance', alignRight: true),
        ],
      ),
    ];
    for (var index = 0; index < total; index++) {
      rows.add(_transactionRow(statement.entries[index], index));
      final processed = index + 1;
      if (processed == total || processed % progressInterval == 0) {
        onProgress(processed, total);
      }
    }

    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(65),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FixedColumnWidth(42),
        4: pw.FixedColumnWidth(65),
        5: pw.FixedColumnWidth(72),
      },
      children: rows,
    );
  }

  pw.TableRow _transactionRow(BankStatementEntry entry, int index) {
    final typeColor = entry.isDebit
        ? _debit
        : entry.isCredit
            ? _credit
            : _muted;
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: index.isOdd ? _stripe : PdfColors.white,
        border: const pw.Border(
          bottom: pw.BorderSide(color: _divider, width: 0.55),
        ),
      ),
      children: [
        _tableCell(_dateLabel(entry.occurredAt)),
        _tableCell(_pdfSafe(entry.description)),
        _tableCell(_pdfSafe(entry.reference)),
        _tableCell(
          entry.typeLabel,
          color: typeColor,
          fontWeight: pw.FontWeight.bold,
        ),
        _tableCell(_number(entry.amount), alignRight: true),
        _tableCell(_number(entry.balance), alignRight: true),
      ],
    );
  }

  pw.Widget _tableHeader(String value, {bool alignRight = false}) {
    return pw.Container(
      alignment:
          alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      child: pw.Text(
        value.toUpperCase(),
        style: pw.TextStyle(
          color: _softMuted,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  pw.Widget _tableCell(
    String value, {
    bool alignRight = false,
    PdfColor color = _ink,
    pw.FontWeight? fontWeight,
  }) {
    return pw.Container(
      alignment:
          alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  pw.Widget _buildEmptyState() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'No transactions in this period',
            style: pw.TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'The opening and closing balances are unchanged.',
            style: const pw.TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(
    pw.Context context, {
    required BankStatementData statement,
    required pw.MemoryImage? totalsIcon,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 9),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _divider, width: 0.7),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (totalsIcon != null) ...[
            pw.Container(
              width: 13,
              height: 13,
              child: pw.Image(totalsIcon, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 5),
          ],
          pw.Text(
            'Generated by ',
            style: const pw.TextStyle(color: _softMuted, fontSize: 8),
          ),
          pw.UrlLink(
            destination: totalsStatementUrl,
            child: pw.Text(
              'Totals',
              style: pw.TextStyle(
                color: _accent,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline,
              ),
            ),
          ),
          pw.Text(
            ' on ${_dateLabel(statement.generatedAt)}'
            '  |  Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(color: _softMuted, fontSize: 8),
          ),
        ],
      ),
    );
  }

  String _currency(double value) => 'ETB ${_number(value)}';

  String _number(double value) {
    final safeValue = value.isFinite ? value : 0.0;
    return NumberFormat('#,##0.00', 'en_US').format(safeValue);
  }

  String _dateLabel(DateTime date) =>
      DateFormat('MMM d, yyyy', 'en_US').format(date);

  String _dateRangeLabel(DateTime start, DateTime end) =>
      '${_dateLabel(start)} - ${_dateLabel(end)}';
}

const int _pdfProgressMessage = 0;
const int _pdfResultMessage = 1;
const int _pdfErrorMessage = 2;

void _renderBankStatementPdfInIsolate(
  _BankStatementPdfIsolateRequest request,
) async {
  try {
    final bytes = await BankStatementPdfService()._render(
      request.renderRequest,
      (progress) {
        request.replyPort.send([
          _pdfProgressMessage,
          progress.value,
          progress.stage.index,
          progress.processed,
          progress.total,
        ]);
      },
    );
    request.replyPort.send([
      _pdfResultMessage,
      TransferableTypedData.fromList([bytes]),
    ]);
  } catch (error, stackTrace) {
    request.replyPort.send([
      _pdfErrorMessage,
      error.toString(),
      stackTrace.toString(),
    ]);
  }
}

class _BankStatementPdfIsolateRequest {
  final _BankStatementPdfRenderRequest renderRequest;
  final SendPort replyPort;

  const _BankStatementPdfIsolateRequest({
    required this.renderRequest,
    required this.replyPort,
  });
}

class _BankStatementPdfRenderRequest {
  final BankStatementData statement;
  final Uint8List? bankIconBytes;
  final Uint8List? totalsIconBytes;

  const _BankStatementPdfRenderRequest({
    required this.statement,
    required this.bankIconBytes,
    required this.totalsIconBytes,
  });
}

class _TimedStatementTransaction {
  final Transaction transaction;
  final DateTime occurredAt;

  const _TimedStatementTransaction(this.transaction, this.occurredAt);
}

List<double> _resolveRunningBalances(
  List<_TimedStatementTransaction> transactions,
  double currentAccountBalance,
) {
  if (transactions.isEmpty) return const <double>[];

  final balances = List<double>.filled(transactions.length, 0.0);
  var firstAnchorIndex = -1;
  var firstAnchorBalance = 0.0;
  for (var index = 0; index < transactions.length; index++) {
    final parsed =
        _parseBalance(transactions[index].transaction.currentBalance);
    if (parsed == null) continue;
    firstAnchorIndex = index;
    firstAnchorBalance = parsed;
    break;
  }

  if (firstAnchorIndex >= 0) {
    balances[firstAnchorIndex] = firstAnchorBalance;
    for (var index = firstAnchorIndex - 1; index >= 0; index--) {
      balances[index] = balances[index + 1] -
          transactionBalanceDelta(transactions[index + 1].transaction);
    }
    for (var index = firstAnchorIndex + 1;
        index < transactions.length;
        index++) {
      balances[index] =
          _parseBalance(transactions[index].transaction.currentBalance) ??
              balances[index - 1] +
                  transactionBalanceDelta(transactions[index].transaction);
    }
    return balances;
  }

  final safeCurrentBalance =
      currentAccountBalance.isFinite ? currentAccountBalance : 0.0;
  balances[transactions.length - 1] = safeCurrentBalance;
  for (var index = transactions.length - 2; index >= 0; index--) {
    balances[index] = balances[index + 1] -
        transactionBalanceDelta(transactions[index + 1].transaction);
  }
  return balances;
}

double _balanceImmediatelyBefore({
  required List<_TimedStatementTransaction> timedTransactions,
  required List<double> resolvedBalances,
  required DateTime instant,
  required double fallbackBalance,
}) {
  if (timedTransactions.isEmpty) {
    return fallbackBalance.isFinite ? fallbackBalance : 0.0;
  }

  for (var index = timedTransactions.length - 1; index >= 0; index--) {
    if (timedTransactions[index].occurredAt.isBefore(instant)) {
      return resolvedBalances[index];
    }
  }

  return resolvedBalances.first -
      transactionBalanceDelta(timedTransactions.first.transaction);
}

DateTime? _parseTransactionTime(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  final unixTime = int.tryParse(value);
  if (unixTime != null) {
    try {
      final milliseconds = value.length <= 10 ? unixTime * 1000 : unixTime;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toLocal();
    } catch (_) {
      return null;
    }
  }

  return DateTime.tryParse(value)?.toLocal();
}

double? _parseBalance(String? raw) {
  if (raw == null) return null;
  final normalized = raw.trim().replaceAll(',', '');
  if (normalized.isEmpty) return null;
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(normalized);
  if (match == null) return null;
  return double.tryParse(match.group(0)!);
}

String _statementDescription(
  Transaction transaction,
  Map<String, String> descriptionsByReference,
) {
  final patternName = descriptionsByReference[transaction.reference]
      ?.trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (patternName != null && patternName.isNotEmpty) return patternName;

  switch (transaction.type?.trim().toUpperCase()) {
    case 'DEBIT':
      return 'Debit transaction';
    case 'CREDIT':
      return 'Credit transaction';
    default:
      return 'Transaction';
  }
}

String _pdfSafe(String value) {
  final buffer = StringBuffer();
  var replacingUnsupported = false;
  for (final rune in value.runes) {
    final isSupported =
        rune == 0x0A || rune == 0x0D || (rune >= 0x20 && rune <= 0xFF);
    if (isSupported) {
      buffer.writeCharCode(rune);
      replacingUnsupported = false;
    } else if (!replacingUnsupported) {
      buffer.write('?');
      replacingUnsupported = true;
    }
  }
  return buffer.toString();
}
