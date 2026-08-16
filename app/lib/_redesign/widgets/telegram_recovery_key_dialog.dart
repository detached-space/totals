import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:totals/services/telegram_backup/telegram_backup_crypto.dart';

typedef TelegramRecoveryKeyTextFilePicker = Future<String?> Function();

Future<String?> showTelegramRecoveryKeyDialog({
  required BuildContext context,
  required String title,
  required String description,
  required String recoveryKeyLabel,
  required String invalidKeyMessage,
  required String chooseFileLabel,
  required String invalidFileMessage,
  required String fileReadErrorMessage,
  required String cancelLabel,
  required String connectLabel,
  String? error,
  TelegramRecoveryKeyTextFilePicker? pickRecoveryKeyFile,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<String>(
    context: context,
    themes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierDismissible: false,
    builder: (_) => TelegramRecoveryKeyDialog(
      title: title,
      description: description,
      recoveryKeyLabel: recoveryKeyLabel,
      invalidKeyMessage: invalidKeyMessage,
      chooseFileLabel: chooseFileLabel,
      invalidFileMessage: invalidFileMessage,
      fileReadErrorMessage: fileReadErrorMessage,
      cancelLabel: cancelLabel,
      connectLabel: connectLabel,
      error: error,
      pickRecoveryKeyFile: pickRecoveryKeyFile,
    ),
  );

  final result = await navigator.push(route);
  // Navigator.push completes as soon as pop begins. Wait until the dialog's
  // reverse transition and inherited subtree teardown have both completed
  // before the caller continues pairing or opens another recovery prompt.
  await route.completed;
  return result;
}

Future<String?> pickTelegramRecoveryKeyTextFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choose your Totals recovery key',
    type: FileType.custom,
    allowedExtensions: ['txt'],
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.single;
  if (file.size > 64 * 1024) {
    throw const FormatException('Recovery key file is too large.');
  }
  if (file.bytes != null) return utf8.decode(file.bytes!);
  if (file.path != null) return File(file.path!).readAsString();
  throw const FileSystemException('The selected file could not be read.');
}

String? extractTelegramRecoveryKeyFromText(String contents) {
  final candidate = StringBuffer();

  String? takeCandidate() {
    final value = candidate.toString();
    candidate.clear();
    if (!TelegramBackupCrypto.isRecoveryKeyFormatValid(value)) return null;
    final normalized = value.toUpperCase();
    return List.generate(
      normalized.length ~/ 4,
      (index) => normalized.substring(index * 4, (index + 1) * 4),
    ).join('-');
  }

  for (final code in contents.runes) {
    final isHex = (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 70) ||
        (code >= 97 && code <= 102);
    final isSeparator =
        code == 45 || code == 9 || code == 10 || code == 13 || code == 32;
    if (isHex) {
      candidate.writeCharCode(code);
    } else if (!isSeparator) {
      final key = takeCandidate();
      if (key != null) return key;
    }
  }
  return takeCandidate();
}

class TelegramRecoveryKeyDialog extends StatefulWidget {
  const TelegramRecoveryKeyDialog({
    required this.title,
    required this.description,
    required this.recoveryKeyLabel,
    required this.invalidKeyMessage,
    required this.chooseFileLabel,
    required this.invalidFileMessage,
    required this.fileReadErrorMessage,
    required this.cancelLabel,
    required this.connectLabel,
    this.error,
    this.pickRecoveryKeyFile,
    super.key,
  });

  final String title;
  final String description;
  final String recoveryKeyLabel;
  final String invalidKeyMessage;
  final String chooseFileLabel;
  final String invalidFileMessage;
  final String fileReadErrorMessage;
  final String cancelLabel;
  final String connectLabel;
  final String? error;
  final TelegramRecoveryKeyTextFilePicker? pickRecoveryKeyFile;

  @override
  State<TelegramRecoveryKeyDialog> createState() =>
      _TelegramRecoveryKeyDialogState();
}

class _TelegramRecoveryKeyDialogState extends State<TelegramRecoveryKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _closing = false;
  bool _choosingFile = false;
  String? _fileError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_closing || _formKey.currentState?.validate() != true) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _cancel() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  Future<void> _chooseFile() async {
    if (_closing || _choosingFile) return;
    setState(() {
      _choosingFile = true;
      _fileError = null;
    });
    try {
      final contents = await (widget.pickRecoveryKeyFile ??
          pickTelegramRecoveryKeyTextFile)();
      if (!mounted) return;
      if (contents == null) {
        setState(() => _choosingFile = false);
        return;
      }

      final recoveryKey = extractTelegramRecoveryKeyFromText(contents);
      if (recoveryKey == null) {
        setState(() {
          _choosingFile = false;
          _fileError = widget.invalidFileMessage;
        });
        return;
      }

      _controller.text = recoveryKey;
      setState(() => _choosingFile = false);
      _submit();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _choosingFile = false;
        _fileError = widget.fileReadErrorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            if (widget.error != null) ...[
              const SizedBox(height: 10),
              Text(
                widget.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.recoveryKeyLabel,
                hintText: 'XXXX-XXXX-XXXX-…',
              ),
              validator: (value) {
                if (TelegramBackupCrypto.isRecoveryKeyFormatValid(
                  value?.trim() ?? '',
                )) {
                  return null;
                }
                return widget.invalidKeyMessage;
              },
              onChanged: (_) {
                if (_fileError != null) {
                  setState(() => _fileError = null);
                }
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _choosingFile ? null : _chooseFile,
                icon: _choosingFile
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(widget.chooseFileLabel),
              ),
            ),
            if (_fileError != null) ...[
              const SizedBox(height: 6),
              Text(
                _fileError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.connectLabel),
        ),
      ],
    );
  }
}
