import 'package:sqflite/sqflite.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/models/auto_categorization.dart';
import 'package:totals/models/category.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/receiver_category_service.dart';
import 'package:totals/utils/loan_debt_utils.dart';

class AutoCategorizationService {
  AutoCategorizationService._();

  static final AutoCategorizationService instance =
      AutoCategorizationService._();

  Future<bool> isEnabled() {
    return NotificationSettingsService.instance.isAutoCategorizationEnabled();
  }

  String normalizeCounterparty(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String normalizeFlow(String? flow) {
    return (flow ?? '').trim().toLowerCase() == 'income' ? 'income' : 'expense';
  }

  String flowForTransactionType(String? type) {
    return (type ?? '').trim().toUpperCase() == 'CREDIT' ? 'income' : 'expense';
  }

  String? resolvePrimaryCounterparty({
    required String? type,
    String? receiver,
    String? creditor,
  }) {
    String? normalizeDisplay(String? value) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed.replaceAll(RegExp(r'\s+'), ' ');
    }

    final normalizedReceiver = normalizeDisplay(receiver);
    final normalizedCreditor = normalizeDisplay(creditor);
    final isCredit = (type ?? '').trim().toUpperCase() == 'CREDIT';
    if (isCredit) {
      return normalizedCreditor ?? normalizedReceiver;
    }
    return normalizedReceiver ?? normalizedCreditor;
  }

  Future<List<AutoCategorizationRule>> getRules({String? flow}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedFlow = flow == null ? null : normalizeFlow(flow);
    final rows = await db.query(
      'auto_category_rules',
      where: normalizedFlow == null ? null : 'flow = ?',
      whereArgs: normalizedFlow == null ? null : [normalizedFlow],
      orderBy: 'counterparty COLLATE NOCASE ASC, isPrimary DESC, id ASC',
    );
    final managedCategoryIds = await _loanDebtManagedCategoryIds(db);
    final rules = rows
        .map(AutoCategorizationRule.fromDb)
        .where((rule) => !managedCategoryIds.contains(rule.categoryId))
        .toList(growable: false);
    return _sortRules(rules);
  }

  List<AutoCategorizationRule> _sortRules(List<AutoCategorizationRule> rules) {
    rules.sort((a, b) {
      final counterpartyComparison =
          a.counterparty.toLowerCase().compareTo(b.counterparty.toLowerCase());
      if (counterpartyComparison != 0) return counterpartyComparison;
      if (a.flow != b.flow) {
        return a.flow.compareTo(b.flow);
      }
      if (a.isPrimary != b.isPrimary) {
        return a.isPrimary ? -1 : 1;
      }
      return a.categoryId.compareTo(b.categoryId);
    });
    return rules;
  }

  Future<List<AutoCategorizationRule>> getRulesForCounterparty(
    String counterparty,
    String flow,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'auto_category_rules',
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
      orderBy: 'isPrimary DESC, id ASC',
    );
    final managedCategoryIds = await _loanDebtManagedCategoryIds(db);
    final rules = rows
        .map(AutoCategorizationRule.fromDb)
        .where((rule) => !managedCategoryIds.contains(rule.categoryId))
        .toList(growable: false);
    return _sortRules(rules);
  }

  Future<AutoCategorizationRule?> getRuleForCounterparty(
    String counterparty,
    String flow,
  ) async {
    final rules = await getRulesForCounterparty(counterparty, flow);
    if (rules.isEmpty) return null;
    for (final rule in rules) {
      if (rule.isPrimary) return rule;
    }
    return rules.first;
  }

  Future<void> upsertRule({
    required String counterparty,
    required String flow,
    required int categoryId,
  }) async {
    await replaceRules(
      counterparty: counterparty,
      flow: flow,
      categoryIds: <int>[categoryId],
      primaryCategoryId: categoryId,
    );
  }

  Future<void> replaceRules({
    required String counterparty,
    required String flow,
    required Iterable<int> categoryIds,
    int? primaryCategoryId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCounterparty = normalizeCounterparty(counterparty);
    final displayCounterparty = counterparty.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final normalizedFlow = normalizeFlow(flow);
    final managedCategoryIds = await _loanDebtManagedCategoryIds(db);

    final normalizedCategoryIds = <int>[];
    for (final categoryId in categoryIds) {
      if (categoryId <= 0 || normalizedCategoryIds.contains(categoryId)) {
        continue;
      }
      if (managedCategoryIds.contains(categoryId)) continue;
      normalizedCategoryIds.add(categoryId);
    }

    final resolvedPrimaryCategoryId = normalizedCategoryIds.isEmpty
        ? null
        : (primaryCategoryId != null &&
                normalizedCategoryIds.contains(primaryCategoryId)
            ? primaryCategoryId
            : normalizedCategoryIds.first);

    await db.transaction((txn) async {
      await txn.delete(
        'auto_category_rules',
        where: 'normalizedCounterparty = ? AND flow = ?',
        whereArgs: [normalizedCounterparty, normalizedFlow],
      );

      if (normalizedCategoryIds.isEmpty) return;

      final createdAt = DateTime.now().toIso8601String();
      for (final categoryId in normalizedCategoryIds) {
        await txn.insert(
          'auto_category_rules',
          {
            'counterparty': displayCounterparty,
            'normalizedCounterparty': normalizedCounterparty,
            'flow': normalizedFlow,
            'categoryId': categoryId,
            'isPrimary': categoryId == resolvedPrimaryCategoryId ? 1 : 0,
            'createdAt': createdAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteRulesForCounterparty(
    String counterparty,
    String flow,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_rules',
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
    );
  }

  Future<void> deleteRule(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'auto_category_rules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final rule = AutoCategorizationRule.fromDb(rows.first);
    await db.transaction((txn) async {
      await txn.delete(
        'auto_category_rules',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (!rule.isPrimary) return;

      final remaining = await txn.query(
        'auto_category_rules',
        columns: ['id'],
        where: 'normalizedCounterparty = ? AND flow = ?',
        whereArgs: [rule.normalizedCounterparty, rule.flow],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (remaining.isEmpty) return;

      await txn.update(
        'auto_category_rules',
        {'isPrimary': 1},
        where: 'id = ?',
        whereArgs: [remaining.first['id']],
      );
    });
  }

  Future<void> dismissPrompt({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedCounterparty = normalizeCounterparty(counterparty);
    final displayCounterparty = counterparty.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    await db.insert(
      'auto_category_prompt_dismissals',
      {
        'counterparty': displayCounterparty,
        'normalizedCounterparty': normalizedCounterparty,
        'flow': normalizeFlow(flow),
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isPromptDismissed({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'auto_category_prompt_dismissals',
      columns: ['id'],
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<AutoCategoryPromptDismissal>> getDismissals(
      {String? flow}) async {
    final db = await DatabaseHelper.instance.database;
    final normalizedFlow = flow == null ? null : normalizeFlow(flow);
    final rows = await db.query(
      'auto_category_prompt_dismissals',
      where: normalizedFlow == null ? null : 'flow = ?',
      whereArgs: normalizedFlow == null ? null : [normalizedFlow],
      orderBy: 'counterparty COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(AutoCategoryPromptDismissal.fromDb).toList(growable: false);
  }

  Future<void> clearPromptDismissal({
    required String counterparty,
    required String flow,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_prompt_dismissals',
      where: 'normalizedCounterparty = ? AND flow = ?',
      whereArgs: [
        normalizeCounterparty(counterparty),
        normalizeFlow(flow),
      ],
    );
  }

  Future<void> clearPromptDismissalById(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_prompt_dismissals',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRulesForCategory(int categoryId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'auto_category_rules',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
    );
  }

  Future<AutoCategorizationSelection?> getCategorySelectionForTransaction({
    required String? type,
    String? receiver,
    String? creditor,
  }) async {
    if (!await isEnabled()) return null;

    final flow = flowForTransactionType(type);
    final counterparty = resolvePrimaryCounterparty(
      type: type,
      receiver: receiver,
      creditor: creditor,
    );
    if (counterparty != null) {
      final rules = await getRulesForCounterparty(counterparty, flow);
      if (rules.isNotEmpty) {
        final categoryIds = <int>[];
        int? primaryCategoryId;
        for (final rule in rules) {
          if (rule.categoryId <= 0 || categoryIds.contains(rule.categoryId)) {
            continue;
          }
          categoryIds.add(rule.categoryId);
          if (primaryCategoryId == null && rule.isPrimary) {
            primaryCategoryId = rule.categoryId;
          }
        }
        if (categoryIds.isNotEmpty) {
          primaryCategoryId ??= categoryIds.first;
          return AutoCategorizationSelection(
            primaryCategoryId: primaryCategoryId,
            categoryIds: List<int>.unmodifiable(categoryIds),
          );
        }
      }
    }

    final fallbackCategoryId =
        await ReceiverCategoryService.instance.getCategoryForTransaction(
      receiver: receiver,
      creditor: creditor,
    );
    if (fallbackCategoryId == null || fallbackCategoryId <= 0) return null;
    final managedCategoryIds = await _loanDebtManagedCategoryIds();
    if (managedCategoryIds.contains(fallbackCategoryId)) return null;

    return AutoCategorizationSelection(
      primaryCategoryId: fallbackCategoryId,
      categoryIds: List<int>.unmodifiable(<int>[fallbackCategoryId]),
    );
  }

  Future<int?> getCategoryForTransaction({
    required String? type,
    String? receiver,
    String? creditor,
  }) async {
    final selection = await getCategorySelectionForTransaction(
      type: type,
      receiver: receiver,
      creditor: creditor,
    );
    return selection?.primaryCategoryId;
  }

  Future<Set<int>> _loanDebtManagedCategoryIds([Database? existingDb]) async {
    final db = existingDb ?? await DatabaseHelper.instance.database;
    final rows = await db.query('categories');
    return rows
        .map(Category.fromDb)
        .where((category) =>
            isLoanDebtCategory(category) || isRepaymentCategory(category))
        .map((category) => category.id)
        .whereType<int>()
        .toSet();
  }
}
