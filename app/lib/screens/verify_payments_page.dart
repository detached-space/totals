import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';
import 'package:totals/models/account.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/constants/cash_constants.dart';

class VerifyPaymentsPage extends StatefulWidget {
  const VerifyPaymentsPage({super.key});

  @override
  State<VerifyPaymentsPage> createState() => _VerifyPaymentsPageState();
}

class _VerifyPaymentsPageState extends State<VerifyPaymentsPage> {
  final TextEditingController _referenceController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AccountRepository _accountRepo = AccountRepository();

  int _selectedMode = 1; // 0 = Image Capture, 1 = Reference Entry (default)
  File? _capturedImage;
  String? _uploadResponse;
  String? _enteredReference;
  bool _hasCameraPermission = false;
  bool _isCheckingPermission = true;
  bool _isUploading = false;
  List<Transaction> _foundTransactions = [];
  bool _isSearching = false;
  List<Account> _accounts = [];
  Account? _selectedAccount;
  bool? _verificationSuccess;
  Map<String, dynamic>? _verificationData;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    _loadAccounts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TransactionProvider>(context, listen: false).loadData();
    });
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _accountRepo.getAccounts();
    final filtered = accounts
        .where((account) => account.bank != CashConstants.bankId)
        .toList();
    if (mounted) {
      setState(() {
        _accounts = filtered;
        // Select first account by default
        if (filtered.isNotEmpty && _selectedAccount == null) {
          _selectedAccount = filtered.first;
        }
      });
    }
  }

  Future<void> _checkCameraPermission() async {
    final cameraStatus = await Permission.camera.status;

    if (mounted) {
      setState(() {
        _hasCameraPermission = cameraStatus.isGranted;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _requestCameraPermission() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();

    // Request storage permissions for older Android versions (API < 33)
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    if (mounted) {
      setState(() {
        _hasCameraPermission = cameraStatus.isGranted;
        _isCheckingPermission = false;
      });

      if (cameraStatus.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.l10nText('Camera Permission Required')),
              content: Text(
                context.l10nText(
                  'Camera access is required to capture images. Please enable it in app settings.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10nText('Cancel')),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: Text(context.l10nText('Open Settings')),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  void _onModeChanged(int index) {
    setState(() {
      _selectedMode = index;
      _capturedImage = null;
      _uploadResponse = null;
      _enteredReference = null;
      _foundTransactions = [];
      _verificationSuccess = null;
      _verificationData = null;
    });
  }

  String _formatVerificationData(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    data.forEach((key, value) {
      if (key != 'success') {
        buffer.writeln('$key: ${value.toString()}');
      }
    });
    return buffer.toString().trim();
  }

  Future<void> _captureImage() async {
    // Check and request camera permission
    if (!_hasCameraPermission) {
      await _requestCameraPermission();
      if (!_hasCameraPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10nTextRead(
                  'Camera permission is required to capture images',
                ),
              ),
            ),
          );
        }
        return;
      }
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70, // Reduced quality to reduce file size
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1920, // Limit width to reduce file size
        maxHeight: 1920, // Limit height to reduce file size
      );

      if (image != null && mounted) {
        setState(() {
          _capturedImage = File(image.path);
          _uploadResponse = null;
        });
        await _uploadImage(File(image.path));
      }
    } catch (e) {
      if (mounted) {
        print('Error capturing image: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Error capturing image')}: ${e.toString()}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _uploadImage(File imageFile) async {
    setState(() {
      _isUploading = true;
      _uploadResponse = null;
    });

    try {
      // Check file size (limit to 10MB)
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadResponse = context
                .l10nTextRead('Error: Image file is too large (max 10MB)');
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10nTextRead(
                  'Image file is too large. Please use a smaller image.',
                ),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://sms-parsing-visualizer.vercel.app/api/verify-image'),
      );

      // Add proper headers
      request.headers.addAll({
        'Accept': 'application/json',
      });

      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // Send request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60), // 60 second timeout for large files
        onTimeout: () {
          throw TimeoutException(
            context.l10nTextRead(
              'Upload timeout. Please check your connection and try again.',
            ),
          );
        },
      );

      final response = await http.Response.fromStream(streamedResponse).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            context.l10nTextRead('Response timeout. Please try again.'),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          if (response.statusCode == 200) {
            try {
              // Try to parse JSON response for better display
              final jsonResponse = response.body;
              _uploadResponse = jsonResponse;
            } catch (e) {
              _uploadResponse = response.body;
            }
          } else {
            try {
              // Try to parse error response
              final errorJson = response.body;
              _uploadResponse = 'Error ${response.statusCode}: $errorJson';
            } catch (e) {
              _uploadResponse =
                  'Error ${response.statusCode}: ${response.body}';
            }
          }
        });
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadResponse = '${context.l10nTextRead('Error')}: ${e.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? context.l10nTextRead('Upload timeout')),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadResponse =
              '${context.l10nTextRead('Connection error')}: ${e.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Connection error')}: ${e.message}. ${context.l10nTextRead('Please check your internet connection.')}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          final errorMessage = e.toString().toLowerCase();
          if (errorMessage.contains('broken pipe') ||
              errorMessage.contains('connection reset') ||
              errorMessage.contains('connection closed')) {
            _uploadResponse = context.l10nTextRead(
              'Connection error: The server closed the connection during upload. Please try again with a smaller image or check your internet connection.',
            );
          } else {
            _uploadResponse =
                '${context.l10nTextRead('Error uploading image')}: $e';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().toLowerCase().contains('broken pipe') ||
                      e.toString().toLowerCase().contains('connection reset')
                  ? context.l10nTextRead(
                      'Connection error: Please try again with a smaller image or check your internet connection.',
                    )
                  : '${context.l10nTextRead('Error uploading image')}: ${e.toString()}',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _verifyReference(String reference) async {
    if (reference.trim().isEmpty) return;

    if (_selectedAccount == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10nTextRead('Please select an account first'),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSearching = true;
      _foundTransactions = [];
      _uploadResponse = null;
    });

    try {
      final requestBody = {
        'reference': reference.trim(),
        'account': _selectedAccount!.accountNumber,
        'bankId': _selectedAccount!.bank,
      };

      final response = await http
          .post(
        Uri.parse('https://sms-parsing-visualizer.vercel.app/api/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            context.l10nTextRead('Verification timeout. Please try again.'),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isSearching = false;
          _enteredReference = reference.trim();
          if (response.statusCode == 200) {
            try {
              final jsonResponse =
                  jsonDecode(response.body) as Map<String, dynamic>;
              _verificationData = jsonResponse;
              // Handle different types of success value (bool, string, int)
              final successValue = jsonResponse['success'];
              if (successValue == null) {
                _verificationSuccess =
                    true; // Default to success if field missing
              } else if (successValue is bool) {
                _verificationSuccess = successValue;
              } else if (successValue is String) {
                _verificationSuccess = successValue.toLowerCase() == 'true';
              } else if (successValue is int) {
                _verificationSuccess = successValue == 1;
              } else {
                _verificationSuccess = true; // Default to success
              }
              _uploadResponse = response.body;
            } catch (e) {
              // If JSON parsing fails, treat as success if status is 200
              _verificationSuccess = true;
              _verificationData = null;
              _uploadResponse = response.body;
            }
          } else {
            try {
              final jsonResponse =
                  jsonDecode(response.body) as Map<String, dynamic>;
              _verificationData = jsonResponse;
              _verificationSuccess = false;
              _uploadResponse = response.body;
            } catch (e) {
              _verificationSuccess = false;
              _verificationData = null;
              _uploadResponse =
                  'Error ${response.statusCode}: ${response.body}';
            }
          }
        });
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _verificationSuccess = false;
          _verificationData = null;
          _uploadResponse = '${context.l10nTextRead('Error')}: ${e.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e.message ?? context.l10nTextRead('Verification timeout')),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _verificationSuccess = false;
          _verificationData = null;
          _uploadResponse =
              '${context.l10nTextRead('Connection error')}: ${e.message}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Connection error')}: ${e.message}. ${context.l10nTextRead('Please check your internet connection.')}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _verificationSuccess = false;
          _verificationData = null;
          _uploadResponse =
              '${context.l10nTextRead('Error verifying reference')}: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Error verifying reference')}: ${e.toString()}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _handleReferenceSubmit() {
    final reference = _referenceController.text.trim();
    if (reference.isNotEmpty) {
      _verifyReference(reference);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(context.l10nText('Verify Payments')),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if ((_capturedImage != null || _enteredReference != null) &&
              _foundTransactions.isEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _capturedImage = null;
                  _uploadResponse = null;
                  _enteredReference = null;
                  _foundTransactions = [];
                  _referenceController.clear();
                  _selectedAccount = null;
                });
              },
              tooltip: context.l10nText('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Mode selector
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ModeTab(
                    label: context.l10nText('Enter Reference'),
                    icon: Icons.edit,
                    isSelected: _selectedMode == 1,
                    onTap: () => _onModeChanged(1),
                  ),
                ),
                Expanded(
                  child: _ModeTab(
                    label: context.l10nText('Capture Image'),
                    icon: Icons.camera_alt,
                    isSelected: _selectedMode == 0,
                    onTap: () => _onModeChanged(0),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _selectedMode == 0
                ? _buildImageCaptureMode(theme, colorScheme)
                : _buildReferenceEntryMode(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCaptureMode(ThemeData theme, ColorScheme colorScheme) {
    if (_isCheckingPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCameraPermission) {
      return _buildPermissionRequest(theme, colorScheme);
    }

    if (_capturedImage != null) {
      return _buildImageResultView(theme, colorScheme);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10nText('Capture Payment Image'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10nText(
                'Take a photo of the payment receipt or QR code',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _captureImage,
              icon: const Icon(Icons.camera_alt),
              label: Text(context.l10nText('Capture Image')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageResultView(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_capturedImage != null) ...[
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  _capturedImage!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (_isUploading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Center(
              child: Text(context.l10nText('Uploading image...')),
            ),
          ] else if (_uploadResponse != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.l10nText('Upload Response'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: SelectableText(
                      _uploadResponse!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _capturedImage = null;
                  _uploadResponse = null;
                });
              },
              icon: const Icon(Icons.camera_alt),
              label: Text(context.l10nText('Capture Another Image')),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceEntryMode(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10nText('Enter Transaction Reference'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10nText(
              'Enter the transaction reference number to verify payment details',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          // Bank Account Selection
          if (_accounts.isNotEmpty) ...[
            Text(
              context.l10nText('Select Account'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: DropdownButton<Account?>(
                value: _selectedAccount,
                isExpanded: true,
                hint: Text(
                  context.l10nText('Select Account'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                underline: const SizedBox(),
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: colorScheme.onSurfaceVariant,
                ),
                items: _accounts.map((account) {
                  final banks = AllBanksFromAssets.getAllBanks();
                  final bank = banks.firstWhere(
                    (b) => b.id == account.bank,
                    orElse: () => banks.first,
                  );
                  return DropdownMenuItem<Account?>(
                    value: account,
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              bank.image,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.account_balance,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10nText(bank.shortName),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                account.accountNumber,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedAccount = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Reference Input
          TextField(
            controller: _referenceController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10nText('Enter transaction reference...'),
              prefixIcon: const Icon(Icons.receipt_long),
              suffixIcon: _referenceController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _referenceController.clear();
                        setState(() {
                          _enteredReference = null;
                          _foundTransactions = [];
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onSubmitted: (_) => _handleReferenceSubmit(),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _referenceController.text.trim().isEmpty || _isSearching
                      ? null
                      : _handleReferenceSubmit,
              icon: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _isSearching
                    ? context.l10nText('Verifying...')
                    : context.l10nText('Verify'),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colorScheme.surfaceVariant,
                disabledForegroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_enteredReference != null && _uploadResponse != null) ...[
            const SizedBox(height: 24),
            _buildVerificationResultsView(
                theme, colorScheme, _enteredReference!),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationResultsView(
      ThemeData theme, ColorScheme colorScheme, String reference) {
    final isSuccess = _verificationSuccess == true;
    final successColor = Colors.green;
    final errorColor = colorScheme.error;
    final iconColor = isSuccess ? successColor : errorColor;
    final bgColor =
        isSuccess ? successColor.withOpacity(0.1) : errorColor.withOpacity(0.1);
    final borderColor =
        isSuccess ? successColor.withOpacity(0.3) : errorColor.withOpacity(0.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSuccess ? Icons.check_circle : Icons.error,
                      color: iconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSuccess
                              ? context.l10nText('Verification Successful')
                              : context.l10nText('Verification Failed'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: iconColor,
                          ),
                        ),
                        if (_verificationData != null &&
                            _verificationData!['message'] != null)
                          Text(
                            _verificationData!['message'] as String,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                context.l10nText('Reference:'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: SelectableText(
                  reference,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (_verificationData != null &&
                  _verificationData!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  context.l10nText('Details:'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: SelectableText(
                    _formatVerificationData(_verificationData!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ] else if (_uploadResponse != null) ...[
                const SizedBox(height: 24),
                Text(
                  context.l10nText('Response:'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: SelectableText(
                    _uploadResponse!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _enteredReference = null;
                _uploadResponse = null;
                _verificationSuccess = null;
                _verificationData = null;
                _referenceController.clear();
              });
            },
            icon: const Icon(Icons.edit),
            label: Text(context.l10nText('Verify Another Reference')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionRequest(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10nText('Camera Permission Required'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10nText(
                'We need camera access to capture images for payment verification.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _requestCameraPermission,
              icon: const Icon(Icons.camera_alt),
              label: Text(context.l10nText('Grant Camera Permission')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _TransactionCard({
    required this.transaction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final banks = AllBanksFromAssets.getAllBanks();
    final bank = banks.firstWhere(
      (b) => b.id == transaction.bankId,
      orElse: () => banks.first,
    );

    final isCredit = transaction.type == 'CREDIT';
    final amountColor = isCredit ? Colors.green : colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        bank.image,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.account_balance,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10nText(bank.shortName),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (transaction.time != null)
                          Text(
                            _formatDate(transaction.time!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${isCredit ? '+' : '-'} ${context.l10nText('ETB')} ${formatNumberWithComma(transaction.amount.abs())}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: colorScheme.outline.withOpacity(0.2)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10nText('Reference'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          transaction.reference,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (transaction.creditor != null) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            context.l10nText(isCredit ? 'From' : 'To'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            transaction.creditor ??
                                transaction.receiver ??
                                context.l10nText('N/A'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface,
                            ),
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}
