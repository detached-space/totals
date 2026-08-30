import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/transaction_location.dart';

enum SavedLocationEditorAction { save, delete }

class SavedLocationEditorResult {
  const SavedLocationEditorResult.save(this.name)
      : action = SavedLocationEditorAction.save;

  const SavedLocationEditorResult.delete()
      : action = SavedLocationEditorAction.delete,
        name = null;

  final SavedLocationEditorAction action;
  final String? name;
}

Future<SavedLocationEditorResult?> showSavedLocationEditorSheet({
  required BuildContext context,
  required String approximateName,
  String? initialName,
  bool allowDelete = false,
}) {
  return showModalBottomSheet<SavedLocationEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavedLocationEditorSheet(
      approximateName: approximateName,
      initialName: initialName,
      allowDelete: allowDelete,
    ),
  );
}

class _SavedLocationEditorSheet extends StatefulWidget {
  const _SavedLocationEditorSheet({
    required this.approximateName,
    required this.initialName,
    required this.allowDelete,
  });

  final String approximateName;
  final String? initialName;
  final bool allowDelete;

  @override
  State<_SavedLocationEditorSheet> createState() =>
      _SavedLocationEditorSheetState();
}

class _SavedLocationEditorSheetState extends State<_SavedLocationEditorSheet> {
  late final TextEditingController _nameController;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return AnimatedPadding(
      key: const ValueKey<String>('saved-location-editor-keyboard-inset'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Material(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.slate400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.map_pin_rounded,
                        color: AppColors.primaryLight,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10nText(
                              _isEditing
                                  ? 'Edit saved location'
                                  : 'Save this location',
                            ),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.approximateName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey<String>('saved-location-name-field'),
                  controller: _nameController,
                  autofocus: true,
                  maxLength: transactionPlaceNameMaxLength,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: context.l10nText('Location name'),
                    hintText: context.l10nText('Home'),
                    prefixIcon: const Icon(AppIcons.editOutlined, size: 20),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10nText(
                    _isEditing
                        ? 'Drag the marker on the map whenever you want to move it.'
                        : 'You can assign transactions to this place from their Location field.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (widget.allowDelete)
                      TextButton.icon(
                        key: const ValueKey<String>(
                          'saved-location-delete',
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          const SavedLocationEditorResult.delete(),
                        ),
                        icon: const Icon(AppIcons.delete_outline_rounded),
                        label: Text(context.l10nText('Delete')),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.red,
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10nText('Cancel')),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _nameController,
                      builder: (context, value, _) {
                        return FilledButton.icon(
                          key: const ValueKey<String>(
                            'saved-location-save',
                          ),
                          onPressed: value.text.trim().isEmpty ? null : _save,
                          icon: const Icon(AppIcons.check_rounded, size: 18),
                          label: Text(context.l10nText('Save location')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, SavedLocationEditorResult.save(name));
  }
}
