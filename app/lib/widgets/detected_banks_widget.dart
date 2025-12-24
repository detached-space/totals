import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/services/bank_detection_service.dart';
import 'package:totals/widgets/add_account_form.dart';

/// Widget that displays banks detected from user's SMS
/// and allows quick account registration
class DetectedBanksWidget extends StatefulWidget {
  final VoidCallback onAccountAdded;
  final bool hasExistingAccounts;

  const DetectedBanksWidget({
    required this.onAccountAdded,
    this.hasExistingAccounts = false,
    super.key,
  });

  @override
  State<DetectedBanksWidget> createState() => _DetectedBanksWidgetState();
}

class _DetectedBanksWidgetState extends State<DetectedBanksWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final BankDetectionService _detectionService = BankDetectionService();
  List<DetectedBank> _detectedBanks = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _needsSmsPermission = false;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadDetectedBanks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_needsSmsPermission) return;
    _loadDetectedBanks();
  }

  Future<void> _loadDetectedBanks({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _needsSmsPermission = false;
    });

    try {
      final permissionStatus = await Permission.sms.status;
      if (!permissionStatus.isGranted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _needsSmsPermission = true;
          });
        }
        return;
      }

      final banks = await _detectionService.detectUnregisteredBanks(
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _detectedBanks = banks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("debug: Error loading detected banks: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (!mounted) return;

    if (status.isGranted) {
      await _loadDetectedBanks();
      return;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    setState(() {
      _needsSmsPermission = true;
      _isLoading = false;
    });
  }

  void _openRegistrationForm({Bank? bank}) {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            height: MediaQuery.of(context).size.height * 0.83,
            child: SingleChildScrollView(
              child: RegisterAccountForm(
                initialBankId: bank?.id,
                onSubmit: () {
                  widget.onAccountAdded();
                  _loadDetectedBanks();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // If user has existing accounts, just show the add account card
    if (widget.hasExistingAccounts) {
      return _buildAddAccountCard();
    }

    if (_isLoading) {
      return _buildSkeletonLoading();
    }

    if (_needsSmsPermission) {
      return _buildPermissionState();
    }

    if (_hasError) {
      return _buildErrorState();
    }

    if (_detectedBanks.isEmpty) {
      return _buildEmptyState();
    }

    return _buildDetectedBanksContent();
  }

  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Header skeleton
            Row(
              children: [
                _buildShimmerBox(24, 24, borderRadius: 6),
                const SizedBox(width: 8),
                _buildShimmerBox(180, 24, borderRadius: 6),
              ],
            ),
            const SizedBox(height: 8),
            _buildShimmerBox(220, 16, borderRadius: 4),
            const SizedBox(height: 24),

            // Grid skeleton
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: 4, // Show 4 skeleton cards
              itemBuilder: (context, index) {
                return _buildSkeletonCard();
              },
            ),

            const SizedBox(height: 32),

            // Divider skeleton
            Row(
              children: [
                Expanded(child: _buildShimmerBox(double.infinity, 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildShimmerBox(20, 14, borderRadius: 4),
                ),
                Expanded(child: _buildShimmerBox(double.infinity, 1)),
              ],
            ),

            const SizedBox(height: 24),

            // Button skeleton
            Center(child: _buildShimmerBox(160, 40, borderRadius: 20)),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo skeleton
                _buildShimmerBox(64, 64, borderRadius: 32),
                const SizedBox(height: 12),
                // Name skeleton
                _buildShimmerBox(60, 16, borderRadius: 4),
                const SizedBox(height: 8),
                // Badge skeleton
                _buildShimmerBox(80, 20, borderRadius: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox(double width, double height,
      {double borderRadius = 0}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final shimmerColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.08);
        final highlightColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.2)
            : Colors.black.withOpacity(0.04);

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
              end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
              colors: [
                shimmerColor,
                highlightColor,
                shimmerColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              "Could not scan messages",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadDetectedBanks,
              child: const Text("Try Again"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              "No Bank Messages Found",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We couldn't find any bank SMS.\nAdd an account manually to get started.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            _buildManualAddButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sms_failed_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              "Allow SMS access",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We use SMS to detect your banks. You can still add accounts manually.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _requestSmsPermission,
              child: const Text("Allow SMS access"),
            ),
            const SizedBox(height: 8),
            _buildManualAddButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedBanksContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            // Header
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "We found your banks!",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Tap a bank to add your account details",
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Detected Banks Grid (includes manual add card at the end)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: _detectedBanks.length + 1,
              itemBuilder: (context, index) {
                if (index == _detectedBanks.length) {
                  return _buildManualAddGridCard();
                }
                return _buildBankCard(_detectedBanks[index]);
              },
            ),

            const SizedBox(height: 100), // Bottom padding for nav
          ],
        ),
      ),
    );
  }

  Widget _buildBankCard(DetectedBank detectedBank) {
    return GestureDetector(
      onTap: () => _openRegistrationForm(bank: detectedBank.bank),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Bank Logo
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        detectedBank.bank.image,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Bank Name
                  Text(
                    detectedBank.bank.shortName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Message count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${detectedBank.messageCount} messages",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Add icon indicator
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddAccountCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: GestureDetector(
        onTap: () => _openRegistrationForm(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Add Account",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Register a new bank account",
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualAddButton() {
    return TextButton.icon(
      onPressed: () => _openRegistrationForm(),
      icon: Icon(
        Icons.add_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(
        "Add account manually",
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildManualAddGridCard() {
    return GestureDetector(
      onTap: () => _openRegistrationForm(),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.add_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Add Account",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Register new bank",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
