import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/transaction_source_sms.dart';

class TransactionSourceSmsRepository {
  static const int _queryChunkSize = 500;

  Future<TransactionSourceSms?> getForTransaction(
    String transactionReference,
  ) async {
    final reference = transactionReference.trim();
    if (reference.isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'transaction_source_sms',
      where: 'transactionReference = ?',
      whereArgs: [reference],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionSourceSms.fromJson(rows.single);
  }

  Future<List<TransactionSourceSms>> getForTransactionReferences(
    Iterable<String> transactionReferences,
  ) async {
    final references = transactionReferences
        .map((reference) => reference.trim())
        .where((reference) => reference.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (references.isEmpty) return const [];

    final db = await DatabaseHelper.instance.database;
    final records = <TransactionSourceSms>[];
    for (var offset = 0;
        offset < references.length;
        offset += _queryChunkSize) {
      final end = (offset + _queryChunkSize).clamp(0, references.length);
      final chunk = references.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'transaction_source_sms',
        where: 'transactionReference IN ($placeholders)',
        whereArgs: chunk,
        orderBy: 'transactionReference ASC',
      );
      records.addAll(rows.map(TransactionSourceSms.fromJson));
    }
    return records;
  }

  Future<void> upsert(TransactionSourceSms sourceSms) {
    return upsertAll([sourceSms]);
  }

  Future<void> upsertAll(Iterable<TransactionSourceSms> sourceMessages) async {
    final normalized = <String, TransactionSourceSms>{};
    for (final sourceSms in sourceMessages) {
      final reference = sourceSms.transactionReference.trim();
      if (reference.isEmpty || sourceSms.body.trim().isEmpty) continue;
      normalized[reference] = TransactionSourceSms(
        transactionReference: reference,
        body: sourceSms.body,
        senderAddress: sourceSms.senderAddress?.trim(),
        receivedAt: sourceSms.receivedAt,
        messageId: sourceSms.messageId?.trim(),
      );
    }
    if (normalized.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final sourceSms in normalized.values) {
      batch.insert(
        'transaction_source_sms',
        sourceSms.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
