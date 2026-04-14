class AutoCategorizationRule {
  final int? id;
  final String counterparty;
  final String normalizedCounterparty;
  final String flow;
  final int categoryId;
  final bool isPrimary;
  final String createdAt;

  const AutoCategorizationRule({
    this.id,
    required this.counterparty,
    required this.normalizedCounterparty,
    required this.flow,
    required this.categoryId,
    this.isPrimary = false,
    required this.createdAt,
  });

  factory AutoCategorizationRule.fromDb(Map<String, dynamic> row) {
    final rawIsPrimary = row['isPrimary'];
    return AutoCategorizationRule(
      id: row['id'] as int?,
      counterparty: (row['counterparty'] as String?) ?? '',
      normalizedCounterparty: (row['normalizedCounterparty'] as String?) ?? '',
      flow: ((row['flow'] as String?) ?? 'expense').trim().toLowerCase() ==
              'income'
          ? 'income'
          : 'expense',
      categoryId: row['categoryId'] as int? ?? 0,
      isPrimary: rawIsPrimary == null ? true : rawIsPrimary == 1,
      createdAt: (row['createdAt'] as String?) ?? '',
    );
  }

  factory AutoCategorizationRule.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    bool toBool(dynamic value, {required bool defaultValue}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
      return defaultValue;
    }

    final rawFlow = (json['flow'] as String?)?.trim().toLowerCase();
    final counterparty = (json['counterparty'] as String?) ?? '';
    final normalizedCounterparty =
        (json['normalizedCounterparty'] as String?) ?? '';
    return AutoCategorizationRule(
      id: toInt(json['id']),
      counterparty: counterparty,
      normalizedCounterparty: normalizedCounterparty.isNotEmpty
          ? normalizedCounterparty
          : counterparty.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      flow: rawFlow == 'income' ? 'income' : 'expense',
      categoryId: toInt(json['categoryId']) ?? 0,
      isPrimary: toBool(
        json['isPrimary'],
        defaultValue: true,
      ),
      createdAt:
          (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'categoryId': categoryId,
      'isPrimary': isPrimary ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'categoryId': categoryId,
      'isPrimary': isPrimary,
      'createdAt': createdAt,
    };
  }
}

class AutoCategorizationSelection {
  final int? primaryCategoryId;
  final List<int> categoryIds;

  const AutoCategorizationSelection({
    required this.primaryCategoryId,
    required this.categoryIds,
  });

  bool get isEmpty => categoryIds.isEmpty;
}

class AutoCategoryPromptDismissal {
  final int? id;
  final String counterparty;
  final String normalizedCounterparty;
  final String flow;
  final String createdAt;

  const AutoCategoryPromptDismissal({
    this.id,
    required this.counterparty,
    required this.normalizedCounterparty,
    required this.flow,
    required this.createdAt,
  });

  factory AutoCategoryPromptDismissal.fromDb(Map<String, dynamic> row) {
    return AutoCategoryPromptDismissal(
      id: row['id'] as int?,
      counterparty: (row['counterparty'] as String?) ?? '',
      normalizedCounterparty: (row['normalizedCounterparty'] as String?) ?? '',
      flow: ((row['flow'] as String?) ?? 'expense').trim().toLowerCase() ==
              'income'
          ? 'income'
          : 'expense',
      createdAt: (row['createdAt'] as String?) ?? '',
    );
  }

  factory AutoCategoryPromptDismissal.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final rawFlow = (json['flow'] as String?)?.trim().toLowerCase();
    final counterparty = (json['counterparty'] as String?) ?? '';
    final normalizedCounterparty =
        (json['normalizedCounterparty'] as String?) ?? '';
    return AutoCategoryPromptDismissal(
      id: toInt(json['id']),
      counterparty: counterparty,
      normalizedCounterparty: normalizedCounterparty.isNotEmpty
          ? normalizedCounterparty
          : counterparty.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      flow: rawFlow == 'income' ? 'income' : 'expense',
      createdAt:
          (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'createdAt': createdAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'counterparty': counterparty,
      'normalizedCounterparty': normalizedCounterparty,
      'flow': flow,
      'createdAt': createdAt,
    };
  }
}

class AutoCategorizationPromptDecision {
  final String counterparty;
  final String flow;
  final int categoryId;
  final AutoCategorizationRule? existingRule;

  const AutoCategorizationPromptDecision({
    required this.counterparty,
    required this.flow,
    required this.categoryId,
    required this.existingRule,
  });

  bool get updatesExistingRule => existingRule != null;
}
