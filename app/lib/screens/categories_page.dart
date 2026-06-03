import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/models/auto_categorization.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/screens/auto_categorization_rules_scan_page.dart';
import 'package:totals/utils/auto_categorization_rules_share_payload.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_style.dart';
import 'package:totals/widgets/account_share_qr_code.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Categories Page
// ═════════════════════════════════════════════════════════════════════════════

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentFlow => _tabController.index == 1 ? 'income' : 'expense';

  Future<void> _openEditor({Category? existing, String? initialFlow}) async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryEditorSheet(
        existing: existing,
        initialFlow: initialFlow ?? _currentFlow,
      ),
    );

    if (result == null || result.name.trim().isEmpty) return;
    final isUncategorized = result.type == CategoryType.uncategorized;
    final isEssential = result.type == CategoryType.essential;

    try {
      if (existing == null) {
        await provider.createCategory(
          name: result.name,
          essential: isEssential,
          uncategorized: isUncategorized,
          iconKey: result.iconKey,
          colorKey: result.colorKey,
          description: result.description,
          flow: result.flow,
          recurring: result.recurring,
        );
      } else {
        await provider.updateCategory(
          existing.copyWith(
            name: result.name,
            essential: isEssential,
            uncategorized: isUncategorized,
            iconKey: result.iconKey,
            colorKey: result.colorKey,
            description: result.description,
            flow: result.flow,
            recurring: result.recurring,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Failed to save category')}: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openAutoCategorizationShareSheet(String flow) async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final rules = provider.autoCategorizationRulesForFlow(flow);
    final payload = AutoCategorizationRulesSharePayload.fromRules(
      rules: rules,
      resolveCategory: provider.getCategoryById,
      flow: flow,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.cardColor(context),
      builder: (_) => _AutoCategorizationShareSheet(
        payload: payload,
        flow: flow,
        onScan: _scanAutoCategorizationRules,
      ),
    );
  }

  Future<void> _scanAutoCategorizationRules() async {
    final result =
        await Navigator.of(context).push<AutoCategorizationRulesImportResult>(
      MaterialPageRoute(
        builder: (_) => const AutoCategorizationRulesScanPage(),
      ),
    );
    if (result == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_buildAutoCategorizationImportMessage(result)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _buildAutoCategorizationImportMessage(
    AutoCategorizationRulesImportResult result,
  ) {
    if (!result.importedAnything) {
      return context.l10nTextRead('No auto-category rules imported');
    }

    final ruleLabel = result.importedRuleGroups == 1
        ? context.l10nTextRead('rule group')
        : context.l10nTextRead('rule groups');
    final categoryLabel = result.createdCategories == 1
        ? context.l10nTextRead('category')
        : context.l10nTextRead('categories');
    final createdCategoryText = result.createdCategories > 0
        ? ', ${context.l10nTextRead('created')} '
            '${result.createdCategories} $categoryLabel'
        : '';
    return '${context.l10nTextRead('Imported')} '
        '${result.importedRuleGroups} $ruleLabel$createdCategoryText.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          context.l10nText('Categories'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(context),
          ),
        ),
        centerTitle: true,
        actions: const [SizedBox.shrink()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.mutedFill(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.cardColor(context),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.textPrimary(context),
              unselectedLabelColor: AppColors.textSecondary(context),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              tabs: [
                Tab(text: context.l10nText('Expenses')),
                Tab(text: context.l10nText('Income')),
              ],
            ),
          ),
        ),
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, provider, _) {
          final categories = provider.categories;
          final expenseCategories = categories
              .where((c) => c.flow.toLowerCase() != 'income')
              .toList(growable: false);
          final incomeCategories = categories
              .where((c) => c.flow.toLowerCase() == 'income')
              .toList(growable: false);
          final expenseRules =
              provider.autoCategorizationRulesForFlow('expense');
          final incomeRules = provider.autoCategorizationRulesForFlow('income');
          final expenseDismissals =
              provider.autoCategoryPromptDismissalsForFlow('expense');
          final incomeDismissals =
              provider.autoCategoryPromptDismissalsForFlow('income');

          return TabBarView(
            controller: _tabController,
            children: [
              _CategoryList(
                categories: expenseCategories,
                autoCategorizationRules: expenseRules,
                promptDismissals: expenseDismissals,
                isAutoCategorizationEnabled:
                    provider.isAutoCategorizationEnabled,
                emptyLabel: 'No expense categories yet',
                sections: _buildSections(
                  expenseCategories,
                  flow: 'expense',
                ),
                resolveCategory: provider.getCategoryById,
                onSetAutoCategorizationEnabled:
                    provider.setAutoCategorizationEnabled,
                onShareScanAutoCategorization: () =>
                    _openAutoCategorizationShareSheet('expense'),
                onCreate: () => _openEditor(initialFlow: 'expense'),
                onEdit: (c) => _openEditor(existing: c, initialFlow: c.flow),
                onDeleteRule: (rule) async {
                  await provider.deleteAutoCategorizationRule(rule);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.l10nTextRead('Removed auto-categorization for')} '
                        '${rule.counterparty}.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onClearDismissal: (dismissal) async {
                  await provider.clearAutoCategoryPromptDismissal(dismissal);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.l10nTextRead('Totals can ask again for')} '
                        '${dismissal.counterparty}.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              _CategoryList(
                categories: incomeCategories,
                autoCategorizationRules: incomeRules,
                promptDismissals: incomeDismissals,
                isAutoCategorizationEnabled:
                    provider.isAutoCategorizationEnabled,
                emptyLabel: 'No income categories yet',
                sections: _buildSections(
                  incomeCategories,
                  flow: 'income',
                ),
                resolveCategory: provider.getCategoryById,
                onSetAutoCategorizationEnabled:
                    provider.setAutoCategorizationEnabled,
                onShareScanAutoCategorization: () =>
                    _openAutoCategorizationShareSheet('income'),
                onCreate: () => _openEditor(initialFlow: 'income'),
                onEdit: (c) => _openEditor(existing: c, initialFlow: c.flow),
                onDeleteRule: (rule) async {
                  await provider.deleteAutoCategorizationRule(rule);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.l10nTextRead('Removed auto-categorization for')} '
                        '${rule.counterparty}.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                onClearDismissal: (dismissal) async {
                  await provider.clearAutoCategoryPromptDismissal(dismissal);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${context.l10nTextRead('Totals can ask again for')} '
                        '${dismissal.counterparty}.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<_CategorySection> _buildSections(
    List<Category> categories, {
    required String flow,
  }) {
    final builtIn = _sortCategories(
      categories.where((c) => c.builtIn).toList(),
    );
    final custom = _sortCategories(
      categories.where((c) => !c.builtIn).toList(),
    );
    final flowLabel = flow == 'income' ? 'income' : 'expense';

    return [
      _CategorySection(
        title: 'Built-in',
        subtitle: 'Included by default',
        emptyLabel: 'No built-in $flowLabel categories available.',
        items: builtIn,
      ),
      _CategorySection(
        title: 'Custom',
        subtitle: 'Created by you',
        emptyLabel: 'No custom $flowLabel categories yet.',
        showsCreateAction: true,
        items: custom,
      ),
    ];
  }

  List<Category> _sortCategories(List<Category> categories) {
    categories.sort((a, b) {
      final typeCompare =
          _categoryTypeSortOrder(a).compareTo(_categoryTypeSortOrder(b));
      if (typeCompare != 0) return typeCompare;

      final recurringCompare =
          (b.recurring ? 1 : 0).compareTo(a.recurring ? 1 : 0);
      if (recurringCompare != 0) return recurringCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return categories;
  }

  int _categoryTypeSortOrder(Category category) {
    switch (category.type) {
      case CategoryType.essential:
        return 0;
      case CategoryType.nonEssential:
        return 1;
      case CategoryType.uncategorized:
        return 2;
    }
  }
}

// ── Section data ────────────────────────────────────────────────────────────
class _CategorySection {
  final String title;
  final String subtitle;
  final String emptyLabel;
  final bool showsCreateAction;
  final List<Category> items;
  const _CategorySection({
    required this.title,
    required this.subtitle,
    required this.emptyLabel,
    this.showsCreateAction = false,
    required this.items,
  });
}

// ── Category List ───────────────────────────────────────────────────────────
class _CategoryList extends StatelessWidget {
  final List<Category> categories;
  final List<AutoCategorizationRule> autoCategorizationRules;
  final List<AutoCategoryPromptDismissal> promptDismissals;
  final bool isAutoCategorizationEnabled;
  final String emptyLabel;
  final List<_CategorySection> sections;
  final Category? Function(int?) resolveCategory;
  final Future<void> Function(bool enabled) onSetAutoCategorizationEnabled;
  final VoidCallback onShareScanAutoCategorization;
  final VoidCallback onCreate;
  final ValueChanged<Category> onEdit;
  final Future<void> Function(AutoCategorizationRule rule) onDeleteRule;
  final Future<void> Function(AutoCategoryPromptDismissal dismissal)
      onClearDismissal;

  const _CategoryList({
    required this.categories,
    required this.autoCategorizationRules,
    required this.promptDismissals,
    required this.isAutoCategorizationEnabled,
    required this.emptyLabel,
    required this.sections,
    required this.resolveCategory,
    required this.onSetAutoCategorizationEnabled,
    required this.onShareScanAutoCategorization,
    required this.onCreate,
    required this.onEdit,
    required this.onDeleteRule,
    required this.onClearDismissal,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty &&
        autoCategorizationRules.isEmpty &&
        promptDismissals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10nText(emptyLabel),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        for (int s = 0; s < sections.length; s++) ...[
          if (s > 0) const SizedBox(height: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: sections[s].title,
                subtitle: sections[s].subtitle,
                count: sections[s].items.length,
              ),
              const SizedBox(height: 14),
              if (sections[s].items.isEmpty)
                _EmptySectionCard(
                  label: sections[s].emptyLabel,
                  onCreate: sections[s].showsCreateAction ? onCreate : null,
                )
              else
                _CategoryWrap(
                  categories: sections[s].items,
                  onCreate: sections[s].showsCreateAction ? onCreate : null,
                  onEdit: onEdit,
                ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        _AutoCategorizationRulesCard(
          rules: autoCategorizationRules,
          isEnabled: isAutoCategorizationEnabled,
          resolveCategory: resolveCategory,
          onSetEnabled: onSetAutoCategorizationEnabled,
          onShareScan: onShareScanAutoCategorization,
          onDeleteRule: onDeleteRule,
        ),
        if (promptDismissals.isNotEmpty) ...[
          const SizedBox(height: 28),
          _DismissedPromptsCard(
            dismissals: promptDismissals,
            onClearDismissal: onClearDismissal,
          ),
        ],
      ],
    );
  }
}

class _AutomationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final Widget child;
  final Widget? titleAction;
  final Widget? trailing;

  const _AutomationCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.child,
    this.titleAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: title,
          subtitle: subtitle,
          count: count,
          titleAction: titleAction,
          trailing: trailing,
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _AutoCategorizationShareScanButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AutoCategorizationShareScanButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10nText('Share or scan rules'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.mutedFill(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              size: 17,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoCategorizationShareSheet extends StatefulWidget {
  final AutoCategorizationRulesSharePayload payload;
  final String flow;
  final Future<void> Function() onScan;

  const _AutoCategorizationShareSheet({
    required this.payload,
    required this.flow,
    required this.onScan,
  });

  @override
  State<_AutoCategorizationShareSheet> createState() =>
      _AutoCategorizationShareSheetState();
}

class _AutoCategorizationShareSheetState
    extends State<_AutoCategorizationShareSheet> {
  final GlobalKey _qrKey = GlobalKey();

  String? get _qrData => widget.payload.rules.isEmpty
      ? null
      : AutoCategorizationRulesSharePayload.encode(widget.payload);

  Future<void> _shareQrCode() async {
    final qrData = _qrData;
    if (qrData == null) return;
    final shareText = context.l10nTextRead(
      'Scan this QR code to import my auto-category rules',
    );

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final renderObject = _qrKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;

      final image = await renderObject.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/auto_category_rules_qr.png');
      await file.writeAsBytes(buffer);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: shareText,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Error sharing QR code')}: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openScanner() async {
    final onScan = widget.onScan;
    Navigator.pop(context);
    await onScan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qrData = _qrData;
    final hasData = qrData != null;
    final flowLabel = widget.flow == 'income'
        ? context.l10nText('Income')
        : context.l10nText('Expense');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Share or scan rules'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary(context),
                  ),
                  tooltip: context.l10nText('Close'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasData
                  ? '$flowLabel ${context.l10nText('auto-category rules')}'
                  : context.l10nText('No rules to share yet.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 18),
            if (hasData)
              RepaintBoundary(
                key: _qrKey,
                child: AccountShareQrCode(
                  data: qrData,
                  fallback: Text(
                    context.l10nText('Too much data to render QR'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 220,
                height: 220,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderColor(context)),
                ),
                child: Text(
                  context.l10nText(
                    'Create auto-category rules before sharing this tab.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(context.l10nText('Scan')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          AppColors.isDark(context) ? AppColors.white : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasData ? _shareQrCode : null,
                    icon: const Icon(Icons.share_rounded),
                    label: Text(context.l10nText('Share')),
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

class _AutoCategorizationRulesCard extends StatelessWidget {
  final List<AutoCategorizationRule> rules;
  final bool isEnabled;
  final Category? Function(int?) resolveCategory;
  final Future<void> Function(bool enabled) onSetEnabled;
  final VoidCallback onShareScan;
  final Future<void> Function(AutoCategorizationRule rule) onDeleteRule;

  const _AutoCategorizationRulesCard({
    required this.rules,
    required this.isEnabled,
    required this.resolveCategory,
    required this.onSetEnabled,
    required this.onShareScan,
    required this.onDeleteRule,
  });

  @override
  Widget build(BuildContext context) {
    return _AutomationCard(
      title: context.l10nText('Auto-Categorization'),
      subtitle: isEnabled
          ? context.l10nText('Future transactions matched automatically')
          : context.l10nText('Auto-categorization is turned off'),
      count: rules.length,
      titleAction: _AutoCategorizationShareScanButton(onTap: onShareScan),
      trailing: Switch.adaptive(
        value: isEnabled,
        onChanged: (value) {
          onSetEnabled(value);
        },
        activeColor: AppColors.primaryLight,
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: isEnabled ? 1 : 0.45,
        child: rules.isEmpty
            ? _AutomationEmptyState(
                label: context.l10nText('No auto-categorization rules yet.'),
              )
            : Column(
                children: [
                  for (final rule in rules)
                    _AutoCategorizationRuleRow(
                      rule: rule,
                      category: resolveCategory(rule.categoryId),
                      onDeleteRule: onDeleteRule,
                    ),
                ],
              ),
      ),
    );
  }
}

class _AutoCategorizationRuleRow extends StatelessWidget {
  final AutoCategorizationRule rule;
  final Category? category;
  final Future<void> Function(AutoCategorizationRule rule) onDeleteRule;

  const _AutoCategorizationRuleRow({
    required this.rule,
    required this.category,
    required this.onDeleteRule,
  });

  @override
  Widget build(BuildContext context) {
    final color = category == null
        ? AppColors.textTertiary(context)
        : categoryPaletteColor(category!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
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
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rule.counterparty,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppColors.textTertiary(context),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          category == null
                              ? context.l10nText('Deleted category')
                              : context.l10nText(category!.name),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: category == null
                                ? AppColors.textTertiary(context)
                                : AppColors.textSecondary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () async => onDeleteRule(rule),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: AppColors.textSecondary(context),
                        ),
                        splashRadius: 18,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
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

class _DismissedPromptsCard extends StatelessWidget {
  final List<AutoCategoryPromptDismissal> dismissals;
  final Future<void> Function(AutoCategoryPromptDismissal dismissal)
      onClearDismissal;

  const _DismissedPromptsCard({
    required this.dismissals,
    required this.onClearDismissal,
  });

  @override
  Widget build(BuildContext context) {
    return _AutomationCard(
      title: context.l10nText('Dismissed Prompts'),
      subtitle: context.l10nText(
        'Addresses that should not trigger the popup again',
      ),
      count: dismissals.length,
      child: Column(
        children: [
          for (final dismissal in dismissals)
            _DismissedPromptRow(
              dismissal: dismissal,
              onClearDismissal: onClearDismissal,
            ),
        ],
      ),
    );
  }
}

class _DismissedPromptRow extends StatelessWidget {
  final AutoCategoryPromptDismissal dismissal;
  final Future<void> Function(AutoCategoryPromptDismissal dismissal)
      onClearDismissal;

  const _DismissedPromptRow({
    required this.dismissal,
    required this.onClearDismissal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.textTertiary(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              dismissal.counterparty,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () async => onClearDismissal(dismissal),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(context.l10nText('Ask again')),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final Widget? titleAction;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    this.titleAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      context.l10nText(title).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.textTertiary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.mutedFill(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  if (titleAction != null) ...[
                    const SizedBox(width: 6),
                    titleAction!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.l10nText(subtitle),
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

// ── Section Empty State ─────────────────────────────────────────────────────
class _EmptySectionCard extends StatelessWidget {
  final String label;
  final VoidCallback? onCreate;

  const _EmptySectionCard({
    required this.label,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onCreate != null)
          _CreateCategoryButton(onTap: onCreate!)
        else
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.mutedFill(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.add_circle_outline_rounded,
              size: 18,
              color: AppColors.textSecondary(context),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10nText(label),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AutomationEmptyState extends StatelessWidget {
  final String label;

  const _AutomationEmptyState({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 13,
        height: 1.35,
      ),
    );
  }
}

// ── Category Wrap ───────────────────────────────────────────────────────────
class _CategoryWrap extends StatelessWidget {
  final List<Category> categories;
  final VoidCallback? onCreate;
  final ValueChanged<Category> onEdit;

  const _CategoryWrap({
    required this.categories,
    this.onCreate,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in categories)
          _CategoryRowChip(
            category: category,
            onTap: () => onEdit(category),
          ),
        if (onCreate != null) _CreateCategoryButton(onTap: onCreate!),
      ],
    );
  }
}

class _CreateCategoryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateCategoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 18,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

// ── Category Row Chip ───────────────────────────────────────────────────────
class _CategoryRowChip extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _CategoryRowChip({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = categoryPaletteColor(category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  context.l10nText(category.name),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Editor Result
// ═════════════════════════════════════════════════════════════════════════════
class _CategoryEditorResult {
  final String name;
  final CategoryType type;
  final String? iconKey;
  final String? colorKey;
  final String? description;
  final String flow;
  final bool recurring;

  const _CategoryEditorResult({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.colorKey,
    required this.description,
    required this.flow,
    required this.recurring,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Editor Sheet
// ═════════════════════════════════════════════════════════════════════════════
class _CategoryEditorSheet extends StatefulWidget {
  final Category? existing;
  final String initialFlow;

  const _CategoryEditorSheet({
    required this.existing,
    required this.initialFlow,
  });

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late CategoryType _categoryType;
  String? _iconKey;
  String? _colorKey;
  late String _flow;
  late bool _recurring;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.existing?.description ?? '');
    _categoryType = widget.existing?.type ?? CategoryType.nonEssential;
    _iconKey = widget.existing?.iconKey ?? 'more_horiz';
    _flow =
        (widget.existing?.flow ?? widget.initialFlow).toLowerCase() == 'income'
            ? 'income'
            : 'expense';
    _recurring = widget.existing?.recurring ?? false;
    if (widget.existing != null) {
      _colorKey = resolvedCategoryColorKey(widget.existing!) ??
          fallbackCategoryColorKey(widget.existing!);
    } else {
      _colorKey = suggestedCategoryColorKey(
        flow: _flow,
        essential: _categoryType == CategoryType.essential,
        uncategorized: _categoryType == CategoryType.uncategorized,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      _CategoryEditorResult(
        name: _nameController.text,
        type: _categoryType,
        iconKey: _iconKey,
        colorKey: _colorKey,
        description: _descriptionController.text,
        flow: _flow,
        recurring: _recurring,
      ),
    );
  }

  Future<void> _handleDelete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          ctx.l10nText('Delete category?'),
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          '${ctx.l10nText('This will remove')} '
          '"${ctx.l10nText(existing.name)}" '
          '${ctx.l10nText('and uncategorize any transactions using it.')}',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              ctx.l10nText('Cancel'),
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.l10nText('Delete'),
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      await provider.deleteCategory(existing);
      if (!mounted) return;
      final message = context.l10nTextRead('Category deleted');
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Failed to delete category')}: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;
    final canDelete = isEdit && (widget.existing?.builtIn != true);
    final isIncome = _flow == 'income';
    final selectedColorKey = _colorKey ??
        suggestedCategoryColorKey(
          flow: _flow,
          essential: _categoryType == CategoryType.essential,
          uncategorized: _categoryType == CategoryType.uncategorized,
        );
    final selectedCategoryColor = categoryColorFromKey(selectedColorKey);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title row
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText(isEdit ? 'Edit Category' : 'New Category'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary(context),
                  ),
                  tooltip: context.l10nText('Close'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Flow toggle
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.mutedFill(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _FlowTab(
                      label: 'Expense',
                      selected: !isIncome,
                      onTap: () => setState(() => _flow = 'expense'),
                    ),
                  ),
                  Expanded(
                    child: _FlowTab(
                      label: 'Income',
                      selected: isIncome,
                      onTap: () => setState(() => _flow = 'income'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Name
            _buildTextField(
              context: context,
              controller: _nameController,
              label: 'Name',
              hint: 'e.g. Groceries',
            ),
            const SizedBox(height: 14),

            // Description
            _buildTextField(
              context: context,
              controller: _descriptionController,
              label: 'Description',
              hint: 'Optional note about this category',
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Category type
            _buildLabel(context, 'Type'),
            const SizedBox(height: 8),
            _TypeOption(
              title: isIncome ? 'Main income' : 'Essential',
              subtitle: isIncome
                  ? 'Primary income sources'
                  : 'Needs — used for spending insights',
              selected: _categoryType == CategoryType.essential,
              onTap: () => setState(() {
                _categoryType = CategoryType.essential;
              }),
            ),
            const SizedBox(height: 8),
            _TypeOption(
              title: isIncome ? 'Side income' : 'Non-essential',
              subtitle: isIncome
                  ? 'Secondary income sources'
                  : 'Wants — discretionary spending',
              selected: _categoryType == CategoryType.nonEssential,
              onTap: () => setState(() {
                _categoryType = CategoryType.nonEssential;
              }),
            ),
            const SizedBox(height: 8),
            _TypeOption(
              title: 'Uncategorized',
              subtitle: 'Catch-all or mixed transactions',
              selected: _categoryType == CategoryType.uncategorized,
              onTap: () => setState(() {
                _categoryType = CategoryType.uncategorized;
              }),
            ),
            const SizedBox(height: 16),

            // Color picker
            _buildLabel(context, 'Color'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: categoryColorOptions.map((option) {
                final selected = option.key == selectedColorKey;
                return Tooltip(
                  message: context.l10nText(option.label),
                  child: GestureDetector(
                    onTap: () => setState(() => _colorKey = option.key),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: option.color,
                        border: Border.all(
                          color: selected
                              ? AppColors.textPrimary(context)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 16),

            // Recurring toggle
            Material(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => setState(() => _recurring = !_recurring),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: AppColors.textSecondary(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10nText('Recurring'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            Text(
                              context.l10nText(
                                'Monthly/weekly repeating expenses',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _recurring,
                        onChanged: (v) => setState(() => _recurring = v),
                        activeColor: selectedCategoryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Icon picker
            _buildLabel(context, 'Icon'),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: categoryIconOptions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 42,
                ),
                itemBuilder: (context, index) {
                  final option = categoryIconOptions[index];
                  final selected = _iconKey == option.key;
                  return Tooltip(
                    message: context.l10nText(option.label),
                    child: Material(
                      color: selected
                          ? selectedCategoryColor.withValues(alpha: 0.15)
                          : AppColors.surfaceColor(context),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _iconKey = option.key),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? selectedCategoryColor
                                  : AppColors.borderColor(context),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            option.icon,
                            size: 20,
                            color: selected
                                ? selectedCategoryColor
                                : AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10nText('Swipe sideways to see more icons.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),

            // Delete button
            if (canDelete) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(context.l10nText('Delete category')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _handleDelete,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  context.l10nText('Save'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      maxLines: maxLines,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        labelText: context.l10nText(label),
        hintText: hint == null ? null : context.l10nText(hint),
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
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
          borderSide: const BorderSide(
            color: AppColors.primaryLight,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      context.l10nText(text).toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: AppColors.textTertiary(context),
      ),
    );
  }
}

// ── Flow Tab ────────────────────────────────────────────────────────────────
class _FlowTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FlowTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardColor(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            context.l10nText(label),
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Type Option ─────────────────────────────────────────────────────────────
class _TypeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.08)
          : AppColors.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : AppColors.borderColor(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.primaryLight
                        : AppColors.textTertiary(context),
                    width: 2,
                  ),
                  color: selected ? AppColors.primaryLight : Colors.transparent,
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10nText(title),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    Text(
                      context.l10nText(subtitle),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
