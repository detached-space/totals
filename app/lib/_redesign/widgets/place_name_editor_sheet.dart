import 'package:flutter/material.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/transaction_location.dart';

Future<PlaceNameEditResult?> showPlaceNameEditorSheet({
  required BuildContext context,
  required String? initialValue,
}) {
  return showModalBottomSheet<PlaceNameEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PlaceNameEditorSheet(initialValue: initialValue),
  );
}

class PlaceNameEditResult {
  const PlaceNameEditResult(this.value);

  final String? value;
}

class _PlaceNameEditorSheet extends StatefulWidget {
  const _PlaceNameEditorSheet({required this.initialValue});

  final String? initialValue;

  @override
  State<_PlaceNameEditorSheet> createState() => _PlaceNameEditorSheetState();
}

class _PlaceNameEditorSheetState extends State<_PlaceNameEditorSheet> {
  late final TextEditingController _controller;

  bool get _hasCustomName => widget.initialValue != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;

    return AnimatedPadding(
      key: const ValueKey('place-name-editor-keyboard-inset'),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: keyboardInset + keyboardLiftBuffer,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hasCustomName
                    ? context.l10nText('Edit place name')
                    : context.l10nText('Name this place'),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10nText(
                  'Use a private name you will recognize, like Home, Office, or a favorite café.',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: transactionPlaceNameMaxLength,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10nText('Place name'),
                  hintText: context.l10nText('Home'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('place-name-editor-actions'),
                children: [
                  if (_hasCustomName)
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const PlaceNameEditResult(null),
                      ),
                      child: Text(context.l10nText('Remove name')),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.l10nText('Cancel')),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final name = value.text.trim();
                      return FilledButton(
                        key: const ValueKey('place-name-editor-save'),
                        onPressed: name.isEmpty
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  PlaceNameEditResult(name),
                                ),
                        child: Text(context.l10nText('Save')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
