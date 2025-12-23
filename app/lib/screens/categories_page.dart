import 'package:flutter/material.dart' hide Category;
import 'package:provider/provider.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';
import 'package:totals/utils/category_style.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          String currentFlow() {
            final controller = DefaultTabController.of(context);
            final index = controller?.index ?? 0;
            return index == 1 ? 'income' : 'expense';
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Categories'),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Income'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _openEditor(
                    context,
                    initialFlow: currentFlow(),
                  ),
                  tooltip: 'Add category',
                ),
              ],
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

                return TabBarView(
                  children: [
                    _ExpensesTab(
                      categories: expenseCategories,
                      onEdit: (c) => _openEditor(context, existing: c),
                    ),
                    _IncomeTab(
                      categories: incomeCategories,
                      onEdit: (c) => _openEditor(context, existing: c),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    Category? existing,
    String initialFlow = 'expense',
  }) async {
    final provider = Provider.of<TransactionProvider>(context, listen: false);

    final result = await showModalBottomSheet<_CategoryEditorResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return _CategoryEditorSheet(existing: existing, initialFlow: initialFlow);
      },
    );

    if (result == null) return;
    if (result.name.trim().isEmpty) return;
    final isUncategorized = result.type == CategoryType.uncategorized;
    final isEssential = result.type == CategoryType.essential;

    try {
      if (existing == null) {
        await provider.createCategory(
          name: result.name,
          essential: isEssential,
          uncategorized: isUncategorized,
          iconKey: result.iconKey,
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
            description: result.description,
            flow: result.flow,
            recurring: result.recurring,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save category: $e')),
        );
      }
    }
  }
}

class _CategoryEditorResult {
  final String name;
  final CategoryType type;
  final String? iconKey;
  final String? description;
  final String flow;
  final bool recurring;

  const _CategoryEditorResult({
    required this.name,
    required this.type,
    required this.iconKey,
    required this.description,
    required this.flow,
    required this.recurring,
  });
}

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
    _flow = (widget.existing?.flow ?? widget.initialFlow).toLowerCase() == 'income'
        ? 'income'
        : 'expense';
    _recurring = widget.existing?.recurring ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final canDelete = isEdit && (widget.existing?.builtIn != true);
    final isIncome = _flow == 'income';
    final essentialLabel = isIncome ? 'Main income' : 'Essential';
    final nonEssentialLabel = isIncome ? 'Side income' : 'Non-essential';
    final essentialSubtitle = isIncome
        ? 'Primary income sources'
        : 'Used for spending insights';
    final nonEssentialSubtitle = isIncome
        ? 'Secondary income sources'
        : 'Optional or discretionary spending';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit category' : 'Add category',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _CategoryEditorResult(
                          name: _nameController.text,
                          type: _categoryType,
                          iconKey: _iconKey,
                          description: _descriptionController.text,
                          flow: _flow,
                          recurring: _recurring,
                        ),
                      );
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                ],
                selected: {_flow},
                onSelectionChanged: (s) => setState(() => _flow = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              Text(
                'Category type',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              RadioListTile<CategoryType>(
                contentPadding: EdgeInsets.zero,
                value: CategoryType.essential,
                groupValue: _categoryType,
                onChanged: (v) => setState(() => _categoryType = v!),
                title: Text(essentialLabel),
                subtitle: Text(essentialSubtitle),
              ),
              RadioListTile<CategoryType>(
                contentPadding: EdgeInsets.zero,
                value: CategoryType.nonEssential,
                groupValue: _categoryType,
                onChanged: (v) => setState(() => _categoryType = v!),
                title: Text(nonEssentialLabel),
                subtitle: Text(nonEssentialSubtitle),
              ),
              RadioListTile<CategoryType>(
                contentPadding: EdgeInsets.zero,
                value: CategoryType.uncategorized,
                groupValue: _categoryType,
                onChanged: (v) => setState(() => _categoryType = v!),
                title: const Text('Uncategorized'),
                subtitle: const Text('Catch-all or mixed transactions'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _recurring,
                onChanged: (v) => setState(() => _recurring = v),
                title: const Text('Recurring'),
                subtitle: const Text('Repeats (monthly/weekly) vs one-time'),
              ),
              const SizedBox(height: 12),
              Text(
                'Icon',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  const itemSize = 44.0;
                  const gap = 10.0;
                  final maxWidth = constraints.maxWidth;
                  final rawCount =
                      ((maxWidth + gap) / (itemSize + gap)).floor();
                  final crossAxisCount = rawCount.clamp(3, 7);
                  final gridWidth =
                      (crossAxisCount * itemSize) + ((crossAxisCount - 1) * gap);

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: gridWidth),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: categoryIconOptions.length,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          mainAxisExtent: itemSize,
                        ),
                        itemBuilder: (context, index) {
                          final option = categoryIconOptions[index];
                          return _IconChoice(
                            option: option,
                            selected: _iconKey == option.key,
                            onTap: () => setState(() => _iconKey = option.key),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (canDelete) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete category'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: () async {
                      final existing = widget.existing;
                      if (existing == null) return;

                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Delete category?'),
                            content: Text(
                              'This will remove "${existing.name}" and uncategorize any transactions using it.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          );
                        },
                      );
                      if (confirm != true) return;

                      try {
                        final provider = Provider.of<TransactionProvider>(
                          context,
                          listen: false,
                        );
                        await provider.deleteCategory(existing);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Category deleted')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to delete category: $e'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final CategoryIconOption option;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: option.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : Theme.of(context).dividerColor,
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(option.icon, size: 20),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onEdit;

  const _CategoryTile({
    required this.category,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = categoryTypeColor(category, context);
    final description = (category.description ?? '').trim();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        onTap: onEdit,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            iconForCategoryKey(category.iconKey),
            color: color,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          description.isEmpty ? 'No description' : description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<Category> onEdit;

  const _ExpensesTab({
    required this.categories,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'No expense categories yet',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final essential = categories
        .where((c) => c.type == CategoryType.essential)
        .toList(growable: false);
    final nonEssential = categories
        .where((c) => c.type == CategoryType.nonEssential)
        .toList(growable: false);
    final uncategorized = categories
        .where((c) => c.type == CategoryType.uncategorized)
        .toList(growable: false);
    final hasCoreSections = essential.isNotEmpty || nonEssential.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        if (essential.isNotEmpty) ...[
          _SectionHeader(title: 'Essential', count: essential.length),
          const SizedBox(height: 8),
          for (final c in essential) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        if (nonEssential.isNotEmpty) ...[
          _SectionHeader(title: 'Non-essential', count: nonEssential.length),
          const SizedBox(height: 8),
          for (final c in nonEssential) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
        ],
        if (uncategorized.isNotEmpty) ...[
          if (hasCoreSections) const SizedBox(height: 12),
          _SectionHeader(title: 'Uncategorized', count: uncategorized.length),
          const SizedBox(height: 8),
          for (final c in uncategorized) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _IncomeTab extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<Category> onEdit;

  const _IncomeTab({
    required this.categories,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'No income categories yet',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final main = categories
        .where((c) => c.type == CategoryType.essential)
        .toList(growable: false);
    final side = categories
        .where((c) => c.type == CategoryType.nonEssential)
        .toList(growable: false);
    final uncategorized = categories
        .where((c) => c.type == CategoryType.uncategorized)
        .toList(growable: false);
    final hasCoreSections = main.isNotEmpty || side.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        if (main.isNotEmpty) ...[
          _SectionHeader(title: 'Main income', count: main.length),
          const SizedBox(height: 8),
          for (final c in main) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        if (side.isNotEmpty) ...[
          _SectionHeader(title: 'Side income', count: side.length),
          const SizedBox(height: 8),
          for (final c in side) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
        ],
        if (uncategorized.isNotEmpty) ...[
          if (hasCoreSections) const SizedBox(height: 12),
          _SectionHeader(title: 'Uncategorized', count: uncategorized.length),
          const SizedBox(height: 8),
          for (final c in uncategorized) ...[
            _CategoryTile(category: c, onEdit: () => onEdit(c)),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}
