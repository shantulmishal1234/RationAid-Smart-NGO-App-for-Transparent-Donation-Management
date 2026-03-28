import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/screens/Donor/Family/family_selection_screen.dart';
import 'package:ration_aid/services/allocation_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:uuid/uuid.dart';

import 'package:ration_aid/services/assistance_pack_service.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';
import 'package:ration_aid/screens/Donor/Donation/donation_success_screen.dart';
import 'package:ration_aid/screens/Donor/Donation/donation_tracking_screen.dart';

/// Create Donation Screen - Complete donation creation flow
/// Supports both Cash and In-Kind donations
/// Can also edit existing donations when existingDonation is provided
class CreateDonationScreen extends StatefulWidget {
  final Family? selectedFamily;
  final Donation? existingDonation; // For editing

  const CreateDonationScreen({
    super.key,
    this.selectedFamily,
    this.existingDonation,
  });

  @override
  State<CreateDonationScreen> createState() => _CreateDonationScreenState();
}

class _CreateDonationScreenState extends State<CreateDonationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DonationService _donationService = DonationService();
  final _formKey = GlobalKey<FormState>();

  // Form fields
  Family? _selectedFamily;
  DonationType _donationType = DonationType.cash;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  bool _isAnonymous = false;
  String? _paymentProofUrl;
  bool _isUploading = false;
  final Map<String, num> _selectedItems = {}; // For in-kind donations
  final Map<String, String> _selectedItemUnits = {}; // New: capture units
  bool _isSaving = false;
  StreamSubscription<DocumentSnapshot>? _familySubscription;

  // Hybrid Architecture — Giving Mode for CASH
  String _allocationMode = 'direct'; // 'direct' | 'smart' | 'general'

  // In-Kind Allocation Mode  mirrors Cash: direct | pool | smart (waterfall)
  String _inKindAllocationMode = 'direct'; // 'direct' | 'pool' | 'smart'
  Map<String, num> _overflowItems = {}; // items exceeding family need → pool
  List<InKindSplit> _smartSplits = []; // waterfall splits for Smart Give
  bool _isLoadingSmartSplits = false;

  // Cash Smart Give — live split preview
  List<Map<String, dynamic>> _cashSmartSplits = [];
  bool _isLoadingCashSplits = false;
  Timer? _cashPreviewDebounce;

  // Standardized Items for Pool & Smart modes
  List<PackItem> _availablePackItems = [];
  bool _isLoadingPacks = true;

  /// Generated once per form open — prevents double-tap duplicate submissions
  final String _idempotencyKey = const Uuid().v4();

  // Fix #11 — tracks whether the selected family accepts in-kind donations.
  // Recomputed on every family selection change via _updateTabsForFamily().
  bool _allowInKind = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _donationType = _tabController.index == 0
            ? DonationType.cash
            : DonationType.inKind;

        if (_donationType == DonationType.inKind && _selectedFamily != null) {
          _adjustSelectedItems(_selectedFamily!);
        }
      });
    });

    // Pre-fill form if editing existing donation
    if (widget.existingDonation != null) {
      _loadExistingDonation(widget.existingDonation!);
    } else {
      _selectedFamily = widget.selectedFamily;
      _allowInKind = _selectedFamily?.acceptsInKind ?? true;
    }
    _setupFamilyStream();
    _fetchPackItems();
    // Live preview for Cash Smart Give — debounced on amount changes
    _amountController.addListener(_onCashAmountChanged);
  }

  Future<void> _fetchPackItems() async {
    try {
      final packs = await AssistancePackService.getActivePacks();
      final Map<String, PackItem> uniqueItems = {};

      for (var pack in packs) {
        for (var item in pack.items) {
          // Use name + qty as a unique key (e.g., "Flour_15.0") so donors don't
          // see duplicate listings if multiple packs use the exact same 15kg flour bag.
          final key = '${item.name}_${item.quantityNum}';
          if (!uniqueItems.containsKey(key)) {
            uniqueItems[key] = item;
          }
        }
      }

      if (mounted) {
        setState(() {
          _availablePackItems = uniqueItems.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _isLoadingPacks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPacks = false);
      }
    }
  }

  /// Fix #11 — When a new family is selected, rebuild tabs to hide In-Kind
  /// if the family is Medicine-only.
  /// Fix #11 + P4 Fix — When a new family is selected, update the tab
  /// visibility flag. TabController is NEVER disposed inside build();
  /// instead, the controller always has 2 slots and we animate to slot 0
  /// when In-Kind becomes unavailable. This avoids StateError from
  /// disposing and re-creating a controller on rapid build() calls.
  void _updateTabsForFamily(Family? family) {
    final allow = family?.acceptsInKind ?? true;
    if (allow == _allowInKind) return;
    setState(() {
      _allowInKind = allow;
      // If In-Kind tab was active and is now prohibited, switch to Cash
      if (!allow && _tabController.index == 1) {
        _tabController.animateTo(0);
        _donationType = DonationType.cash;
      }
    });
  }

  /// P5 Fix — _setupFamilyStream already cancels and returns early when
  /// _selectedFamily is null (which happens in Smart/General modes).
  /// This means switching modes implicitly stops the listener as long as
  /// _selectedFamily is cleared before calling _setupFamilyStream().
  void _setupFamilyStream() {
    _familySubscription?.cancel();

    if (_selectedFamily == null ||
        _selectedFamily!.id == 'general_relief_fund') {
      return;
    }

    _familySubscription = FirebaseFirestore.instance
        .collection('families')
        .doc(_selectedFamily!.id)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final updatedFamily = Family.fromFirestore(snapshot);
            _adjustSelectedItems(updatedFamily);
            if (mounted) {
              setState(() {
                _selectedFamily = updatedFamily;
              });
            }
          }
        });
  }

  void _adjustSelectedItems(Family updatedFamily) {
    if (_donationType != DonationType.inKind) return;

    final List<String> adjustedItems = [];
    bool needsUpdate = false;
    final Map<String, num> tempItems = Map.from(_selectedItems);

    tempItems.forEach((item, currentQty) {
      final needed = updatedFamily.needs[item] ?? 0;
      if (needed == 0) {
        // Family no longer needs this item
        adjustedItems.add('$item (Removed)');
        needsUpdate = true;
      } else if (currentQty > needed) {
        // Donor selected more than what's needed now
        adjustedItems.add('$item ($currentQty -> $needed)');
        needsUpdate = true;
      }
    });

    if (needsUpdate && mounted) {
      setState(() {
        _selectedItems.clear();
        _selectedItemUnits.clear();
        tempItems.forEach((item, currentQty) {
          final needed = updatedFamily.needs[item] ?? 0;
          if (needed > 0) {
            _selectedItems[item] = currentQty > needed ? needed : currentQty;
            _selectedItemUnits[item] = updatedFamily.itemUnits[item] ?? '';
          }
        });
      });

      if (adjustedItems.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Needs updated by another donor!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Adjusted: ${adjustedItems.join(", ")}'),
              ],
            ),
            backgroundColor: Colors.orange[800],
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Load existing donation data for editing
  void _loadExistingDonation(Donation donation) {
    _donationType = donation.donationType;
    _tabController.index = donation.donationType == DonationType.cash ? 0 : 1;
    _isAnonymous = donation.anonymous;
    _paymentProofUrl = donation.paymentProofUrl;

    if (donation.amount != null) {
      _amountController.text = donation.amount!.toStringAsFixed(0);
    }
    if (donation.donationNote != null) {
      _noteController.text = donation.donationNote!;
    }
    if (donation.items != null) {
      _selectedItems.addAll(donation.items!);
    }
    if (donation.itemUnits != null) {
      _selectedItemUnits.addAll(donation.itemUnits!);
    }
    if (donation.contactNumber != null) {
      _contactController.text = donation.contactNumber!;
    }
    if (donation.pickupAddress != null) {
      _addressController.text = donation.pickupAddress!;
    }
    // Note: Family will be loaded separately via FutureBuilder
  }

  @override
  void dispose() {
    _familySubscription?.cancel();
    _cashPreviewDebounce?.cancel();
    _tabController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final imageFile = File(image.path);
      final response = await CloudinaryService.uploadImage(imageFile);

      setState(() {
        _paymentProofUrl = response.url;
        _isUploading = false;
      });

      if (response.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment proof uploaded successfully')),
        );
      } else if (!response.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.errorMessage ?? 'Payment proof upload failed',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _saveDonation({bool submitForVerification = false}) async {
    if (!_formKey.currentState!.validate()) return;

    // Family required only for: cash-direct AND in-kind-direct
    final bool needsFamily =
        (_donationType == DonationType.cash && _allocationMode == 'direct') ||
        (_donationType == DonationType.inKind &&
            _inKindAllocationMode == 'direct');
    if (needsFamily && _selectedFamily == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a family')));
      return;
    }

    // Smart Give mode requires at least one item to be added
    if (_donationType == DonationType.inKind &&
        _inKindAllocationMode == 'smart' &&
        _selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add items first so Smart Give can find the best families.',
          ),
        ),
      );
      return;
    }

    // Validation based on donation type
    if (submitForVerification && _paymentProofUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _donationType == DonationType.cash
                ? 'Payment proof required for verification'
                : 'Item photo proof required for verification',
          ),
        ),
      );
      return;
    }

    if (_donationType == DonationType.inKind) {
      if (_selectedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one item')),
        );
        return;
      }
      if (_contactController.text.isEmpty || _addressController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide contact number and pickup address'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not logged in');

      // ── Determine familyId based on in-kind allocation mode ───────────
      String resolvedFamilyId;
      String resolvedMode;
      List<Map<String, dynamic>>? effectiveSmartSplits;

      if (_donationType == DonationType.inKind) {
        switch (_inKindAllocationMode) {
          case 'pool':
            resolvedFamilyId = 'general_relief_fund';
            resolvedMode = 'pool';
          case 'smart':
            resolvedFamilyId = 'smart_allocation';
            resolvedMode = 'smart';
            // P16 Fix — Consolidate splits into a single document for professional alignment
            effectiveSmartSplits = _smartSplits.map((s) => s.toMap()).toList();
          default: // direct
            resolvedFamilyId = _selectedFamily?.id ?? '';
            resolvedMode = 'direct';
        }
      } else {
        // Cash: use existing _allocationMode logic
        resolvedFamilyId = _allocationMode == 'general'
            ? 'general_relief_fund'
            : _allocationMode == 'smart'
            ? 'smart_allocation'
            : _selectedFamily!.id;
        resolvedMode = _allocationMode;
        effectiveSmartSplits = _smartSplits.map((s) => s.toMap()).toList();
      }

      var donation = Donation(
        id: widget.existingDonation?.id ?? '',
        donorId: userId,
        donorName: widget.existingDonation?.donorName,
        donorEmail: widget.existingDonation?.donorEmail,
        familyId: resolvedFamilyId,
        donationType: _donationType,
        amount:
            _donationType == DonationType.cash &&
                _amountController.text.isNotEmpty
            ? double.tryParse(_amountController.text)
            : null,
        items: _donationType == DonationType.inKind ? _selectedItems : null,
        itemUnits: _donationType == DonationType.inKind
            ? _selectedItemUnits
            : null,
        anonymous: _isAnonymous,
        status: submitForVerification
            ? DonationStatus.underVerification
            : DonationStatus.draft,
        paymentProofUrl: _paymentProofUrl,
        donationNote: _noteController.text.isNotEmpty
            ? _noteController.text
            : null,
        pickupAddress: _donationType == DonationType.inKind
            ? _addressController.text
            : null,
        contactNumber: _donationType == DonationType.inKind
            ? _contactController.text
            : null,
        createdAt: widget.existingDonation?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        statusHistory: widget.existingDonation?.statusHistory ?? [],
        allocationMode: resolvedMode,
        effectiveAmount: double.tryParse(_amountController.text) ?? 0,
        overflowAmount: 0,
        idempotencyKey: _idempotencyKey,
        smartSplits: effectiveSmartSplits,
      );

      // Update existing or create new
      if (widget.existingDonation != null) {
        await _donationService.updateDonation(donation.id, donation);
      } else {
        final newId = await _donationService.createDonation(donation);
        donation = donation.copyWith(id: newId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingDonation != null
                  ? 'Donation updated successfully!'
                  : (submitForVerification
                        ? 'Donation submitted for verification!'
                        : 'Donation saved as draft'),
            ),
          ),
        );

        if (submitForVerification) {
          // Navigate to success screen and wait for it to pop (after 3 seconds)
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DonationSuccessScreen(donation: donation),
            ),
          );

          if (!mounted) return;

          // After success screen pops, replace this creation screen with the tracking screen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DonationTrackingScreen(donation: donation),
            ),
          );
        } else {
          // If just saving as draft, pop back to the previous screen (Home/Tracking)
          Navigator.pop(context, true); // true indicates success
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DonorScaffold(
      title: 'Make a Donation',
      showBackButton: true,
      body: Form(
        key: _formKey,
        child: Stack(
          children: [
            Column(
              children: [
                _buildSegmentedControl(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics:
                        const NeverScrollableScrollPhysics(), // Prevent swipe to enforce tab tap interactions
                    children: [
                      _buildCashDonationForm(_selectedFamily),
                      _allowInKind
                          ? _buildInKindDonationForm(_selectedFamily)
                          : _buildDisabledInKindMessage(),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildStickyBottomActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildSegmentTab(0, 'Cash', Icons.attach_money),
          _buildSegmentTab(1, 'In-Kind', Icons.inventory_2_outlined),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(int index, String title, IconData icon) {
    final isSelected = _tabController.index == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (index == 1 && !_allowInKind) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('In-Kind donations not accepted by this family'),
              ),
            );
            return;
          }
          _tabController.animateTo(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.grey[700] : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? AppColors.donorGreen
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisabledInKindMessage() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'In-Kind Not Accepted',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This family requires cash donations (e.g., for medicine). Please switch to the Cash Donation tab.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartGiveTrustBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Give (Waterfall Engine)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your donation will be automatically split to completely fund the highest-priority families first. Any excess gracefully cascades into the General Relief Fund.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGRFTrustBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'General Relief Fund',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Contributions to the GRF are 100% audited and strictly utilized for mass-procurement, emergency distress relief, and pooling for immediate large-scale needs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashDonationForm(Family? family) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family selection card (only for Direct Give mode)
          if (_allocationMode == 'direct') ...[
            _buildFamilySelectionCard(),
            const SizedBox(height: 16),
          ],

          // ── Giving Mode Selector ──────────────────────────────────────
          _buildGivingModeSelector(),
          const SizedBox(height: 16),

          // ── Massive Amount Input ──────────────────────────────────────
          Center(
            child: Text(
              'Enter Amount',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: AppColors.donorGreen,
              letterSpacing: -1.0,
            ),
            // Fix #6 — amount validator: min PKR 10, max PKR 1,000,000
            validator: (value) {
              final amt = double.tryParse(value ?? '');
              if (amt == null || amt <= 0) return 'Invalid';
              if (amt < 10) return 'Min \nPKR 10';
              if (amt > 1000000) return 'Max \n10L';
              return null;
            },
            decoration: InputDecoration(
              hintText: '0',
              prefixText: 'PKR ',
              prefixStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),

          if (family != null && family.targetAmount > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.donorGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Remaining Goal: PKR ${family.remainingCashNeeded.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.donorGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 24),

          // ── Quick Amount Chips ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Please enter the exact amount as shown on your transaction screenshot.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 48),

          // ── Transparency Banners (Dynamic) ────────────────────────────
          if (_allocationMode == 'smart') _buildSmartGiveTrustBanner(theme),
          if (_allocationMode == 'general') _buildGRFTrustBanner(theme),

          // ── Cash Smart Give Split Preview ─────────────────────────────
          if (_allocationMode == 'smart') ...[
            const SizedBox(height: 16),
            _buildCashSmartSplitPreview(theme),
          ],

          if (_allocationMode != 'direct') const SizedBox(height: 32),

          // ── Payment Proof & Trust Section ─────────────────────────────
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                '100% Secure & Audited',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Payment Proof *', // Cash donation section
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _buildImageUploadCard(),
          const SizedBox(height: 24),

          // Optional fields
          _buildOptionalFields(),
          const SizedBox(height: 100), // Bottom padding for scrolling
        ],
      ),
    );
  }

  // ── Giving Mode Selector ────────────────────────────────────────────────
  Widget _buildGivingModeSelector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const modes = [
      ('direct', Icons.person_outline, 'Direct Give', 'Pick a family'),
      (
        'smart',
        Icons.auto_awesome_outlined,
        'Smart Give',
        'Highest need first',
      ),
      ('general', Icons.public_outlined, 'General Fund', 'Relief pool'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How would you like to donate?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: modes.map((m) {
            final isSelected = _allocationMode == m.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _allocationMode = m.$1;
                    if (_allocationMode != 'direct') {
                      _selectedFamily = null;
                      _familySubscription?.cancel();
                    }
                    // Clear cash preview when leaving Smart mode
                    if (m.$1 != 'smart') {
                      _cashSmartSplits = [];
                      _cashPreviewDebounce?.cancel();
                    } else {
                      // Trigger preview immediately if amount is already entered
                      _onCashAmountChanged();
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.donorGreen.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[850] : Colors.white),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.donorGreen
                          : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        m.$2,
                        size: 24,
                        color: isSelected
                            ? AppColors.donorGreen
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.$3,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.donorGreen
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.$4,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            child: _allocationMode == 'smart'
                ? _buildModeHelperText(
                    Icons.lightbulb_outline,
                    'System allocates automatically to highest-priority unfunded families.',
                  )
                : _allocationMode == 'general'
                ? _buildModeHelperText(
                    Icons.maps_home_work_outlined,
                    'Funds go to the collective General Relief Pool for administrative allocation.',
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildModeHelperText(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.donorGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.donorGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.donorGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.donorGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a quantity with unit.
  /// [unit] — when provided (from `family.itemUnits`), it is used directly and
  /// keyword matching is skipped.  This is the canonical, accurate path.
  /// Keyword fallback is only used for legacy / pool / smart modes where no
  /// family context is available.
  String _getFormattedQuantity(String itemName, num quantity, {String? unit}) {
    // Format the numeric part (strip trailing zeros)
    String qtStr;
    if (quantity % 1 == 0) {
      qtStr = quantity.toInt().toString();
    } else {
      String s = quantity.toStringAsFixed(2);
      s = s.replaceAll(RegExp(r'0+$'), '');
      s = s.replaceAll(RegExp(r'\.$'), '');
      qtStr = s;
    }

    // ── Use exact unit from the pack whenever it is available ──────────────
    if (unit != null && unit.isNotEmpty) {
      return '$qtStr $unit'.trim();
    }

    // ── Keyword fallback (Pool / Smart Give — no family context) ────────────
    final lower = itemName.toLowerCase();
    if (lower.contains('flour') ||
        lower.contains('wheat') ||
        lower.contains('rice')) {
      return '$qtStr kg';
    } else if (lower.contains('sugar') ||
        lower.contains('salt') ||
        lower.contains('daal') ||
        lower.contains('lentil') ||
        lower.contains('tea') ||
        lower.contains('besan')) {
      // Smart Fallback: if quantity is large (e.g. 500, 250), it's likely grams.
      // If it's small (e.g. 1, 2, 5), it's likely kg.
      if (quantity >= 100) return '$qtStr g';
      return '$qtStr kg';
    } else if (lower.contains('oil') || lower.contains('ghee')) {
      return '$qtStr L';
    } else if (lower.contains('soap') || lower.contains('wash')) {
      return '$qtStr bars';
    } else if (lower.contains('dates') || lower.contains('khajoor')) {
      return '$qtStr kg';
    } else if (lower.contains('rooh') || lower.contains('syrup')) {
      return '$qtStr bottles';
    }
    return '$qtStr units';
  }

  // ── In-Kind Giving Mode Selector ────────────────────────────────────
  Widget _buildInKindGivingModeSelector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const modes = [
      ('direct', Icons.person_outline, 'Direct', 'Pick family'),
      ('pool', Icons.handshake_outlined, 'NGO Pool', 'We assign'),
      ('smart', Icons.auto_awesome_outlined, 'Smart Give', 'Best fit · Splits'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How would you like to donate?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: modes.map((m) {
            final isSelected = _inKindAllocationMode == m.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _inKindAllocationMode = m.$1;
                    _overflowItems = {};
                    _smartSplits = [];
                    _smartSplits = [];
                    _selectedItems.clear();
                    if (m.$1 != 'direct') {
                      _selectedFamily = null;
                      _familySubscription?.cancel();
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.donorGreen.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[850] : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.donorGreen
                          : (isDark ? Colors.grey[800]! : Colors.grey[200]!),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        m.$2,
                        size: 20,
                        color: isSelected
                            ? AppColors.donorGreen
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.$3,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.donorGreen
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        m.$4,
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Trust banners for in-kind modes ───────────────────────────────────
  Widget _buildInKindPoolBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.handshake_outlined, color: Colors.teal, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NGO Pool Donation',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Our team will match your items to the family with the highest need. '
                  "You'll be notified once assigned. Items are tracked end-to-end.",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.teal.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInKindSmartBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart In-Kind Match',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'System finds the highest-priority family that needs the items '
                  "you're offering. Select items below to see your match.",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primaryBlue.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Smart Give Waterfall Preview Card (mirrors Cash Smart Give) ──────────
  Widget _buildSmartGiveCard() {
    final theme = Theme.of(context);
    if (_isLoadingSmartSplits) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Finding best families…'),
          ],
        ),
      );
    }
    if (_smartSplits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Add items above — Smart Give will automatically split them\nacross the most-needy families, just like Cash Smart Give.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }
    // Show full waterfall split preview
    final familyCount = _smartSplits.where((s) => !s.isPool).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              color: AppColors.donorGreen,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Smart Split Preview — $familyCount ${familyCount == 1 ? 'family' : 'families'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.donorGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._smartSplits.map((split) {
          final isPool = split.isPool;
          final color = isPool ? Colors.teal : AppColors.donorGreen;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isPool ? Icons.handshake_outlined : Icons.family_restroom,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPool
                            ? 'NGO Pool (leftover)'
                            : (split.family != null
                                  ? () {
                                      final area = split.family!.area;
                                      final city = split.family!.city;
                                      final loc = area.isNotEmpty
                                          ? area
                                          : 'Unknown Area';
                                      return 'Family · $loc${city.isNotEmpty ? ', $city' : ''}';
                                    }()
                                  : 'Family'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      Text(
                        split.items.isNotEmpty
                            ? split.items.entries
                                  .map((e) => '${e.key}×${e.value}')
                                  .join(', ')
                            : split.reason,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _loadSmartMatch,
          icon: const Icon(
            Icons.refresh,
            size: 16,
            color: AppColors.donorGreen,
          ),
          label: const Text(
            'Recalculate',
            style: TextStyle(color: AppColors.donorGreen, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ── Smart Give Loader — runs full waterfall (same as Cash Smart Give) ────
  Future<void> _loadSmartMatch() async {
    if (_selectedItems.isEmpty) {
      setState(() => _smartSplits = []);
      return;
    }
    setState(() => _isLoadingSmartSplits = true);
    try {
      final splits = await AllocationService.previewInKindWaterfall(
        _selectedItems,
      );
      if (mounted) {
        setState(() {
          _smartSplits = splits;
          _isLoadingSmartSplits = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSmartSplits = false);
    }
  }

  // ── Cash Smart Give — debounce listener ─────────────────────────────────
  void _onCashAmountChanged() {
    if (_allocationMode != 'smart') return;
    _cashPreviewDebounce?.cancel();
    _cashPreviewDebounce = Timer(
      const Duration(milliseconds: 600),
      _loadCashSmartPreview,
    );
  }

  // ── Cash Smart Give — fetch preview from AllocationService ───────────────
  Future<void> _loadCashSmartPreview() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount < 10) {
      if (mounted) setState(() => _cashSmartSplits = []);
      return;
    }
    if (mounted) setState(() => _isLoadingCashSplits = true);
    try {
      final splits = await AllocationService.previewSmartAllocation(amount);
      if (mounted) {
        setState(() {
          _cashSmartSplits = splits;
          _isLoadingCashSplits = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCashSplits = false);
    }
  }

  // ── Cash Smart Give — split preview card ─────────────────────────────────
  Widget _buildCashSmartSplitPreview(ThemeData theme) {
    if (_isLoadingCashSplits) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Calculating split…'),
          ],
        ),
      );
    }

    if (_cashSmartSplits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Enter an amount above — Smart Give will show exactly how\nyour donation splits across families in real time.',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    final familyCount = _cashSmartSplits
        .where((s) => s['familyId'] != 'general_relief_fund')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              color: AppColors.donorGreen,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Smart Split Preview — $familyCount ${familyCount == 1 ? 'family' : 'families'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.donorGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._cashSmartSplits.map((split) {
          final isGRF = split['familyId'] == 'general_relief_fund';
          final family = split['family'] as Family?;
          final contribution = (split['contribution'] as num?)?.toDouble() ?? 0;
          final reason = split['reason'] as String? ?? '';
          final color = isGRF ? Colors.orange : AppColors.donorGreen;

          // Build privacy-safe location label
          String label;
          if (isGRF) {
            label = 'General Relief Fund';
          } else if (family != null) {
            final area = family.area.isNotEmpty ? family.area : 'Unknown Area';
            final city = family.city.isNotEmpty ? ', ${family.city}' : '';
            label = 'Family · $area$city';
          } else {
            label = 'Family';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isGRF ? Icons.public : Icons.family_restroom,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      if (reason.isNotEmpty)
                        Text(
                          reason,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'PKR ${contribution.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _loadCashSmartPreview,
          icon: const Icon(
            Icons.refresh,
            size: 16,
            color: AppColors.donorGreen,
          ),
          label: const Text(
            'Recalculate',
            style: TextStyle(color: AppColors.donorGreen, fontSize: 12),
          ),
        ),
      ],
    );
  }

  IconData _getIconForPackItem(String itemName) {
    final lower = itemName.toLowerCase();
    if (lower.contains('flour') || lower.contains('wheat')) return Icons.grass;
    if (lower.contains('rice') ||
        lower.contains('daal') ||
        lower.contains('lentil')) {
      return Icons.rice_bowl_outlined;
    }
    if (lower.contains('oil') || lower.contains('ghee')) {
      return Icons.water_drop_outlined;
    }
    if (lower.contains('sugar') || lower.contains('salt')) return Icons.grain;
    if (lower.contains('soap') || lower.contains('wash')) {
      return Icons.clean_hands_outlined;
    }
    if (lower.contains('date')) return Icons.spa_outlined;
    return Icons.inventory_2_outlined;
  }

  Future<void> _showAddItemBottomSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // For Direct mode, we can still allow custom. For Pool/Smart, strict standard only.
    final bool isStrictStandard = _inKindAllocationMode != 'direct';

    PackItem? selectedPackItem;
    final qtyCtrl = TextEditingController(text: '1');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'What would you like to donate?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isStrictStandard)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    'To ensure fair distribution, NGO Pool donations only accept standard packages.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 12),
              // Items grid
              Flexible(
                child: _isLoadingPacks
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Standard Care Packages',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_availablePackItems.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'No standard items available right now.',
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availablePackItems.map((item) {
                                  final isSelected = selectedPackItem == item;
                                  return GestureDetector(
                                    onTap: () => setInner(() {
                                      if (selectedPackItem == item) {
                                        selectedPackItem = null;
                                      } else {
                                        selectedPackItem = item;
                                      }
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.donorGreen
                                            : (isDark
                                                  ? Colors.grey[800]
                                                  : Colors.grey[100]),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppColors.donorGreen
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getIconForPackItem(item.name),
                                            size: 14,
                                            color: isSelected
                                                ? Colors.white
                                                : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${item.name} (${item.quantity})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white
                                                  : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 24),
                            // Quantity
                            if (selectedPackItem != null) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: qtyCtrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Number of Units/Bags',
                                        helperText:
                                            'e.g., entering "2" means 2 × ${selectedPackItem!.quantity}',
                                        suffixText: 'Units',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Real-time calculation helper
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: qtyCtrl,
                                builder: (context, value, child) {
                                  final units = int.tryParse(value.text) ?? 0;
                                  if (units <= 0) {
                                    return const SizedBox.shrink();
                                  }

                                  final totalNum =
                                      units * selectedPackItem!.quantityNum;
                                  // Format cleanly (e.g. 30.0 -> 30)
                                  final formattedTotal = totalNum % 1 == 0
                                      ? totalNum.toInt().toString()
                                      : totalNum.toStringAsFixed(2);

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8.0,
                                      left: 4.0,
                                    ),
                                    child: Text(
                                      'Total Donation: $formattedTotal ${selectedPackItem!.unit} of ${selectedPackItem!.name}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.donorGreen,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
              ),
              // Confirm button
              Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  top: 8,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedPackItem == null
                        ? null
                        : () {
                            final units = int.tryParse(qtyCtrl.text) ?? 1;
                            if (units > 0) {
                              // The user selects "Units", but we store the metric absolute quantity
                              // because family.needs tracks absolute metric quantity (e.g. 30 kg).
                              final absoluteAmount =
                                  units * selectedPackItem!.quantityNum;
                              final rawName = selectedPackItem!.name;

                              setState(() {
                                _selectedItems[rawName] =
                                    (_selectedItems[rawName] ?? 0) +
                                    absoluteAmount;
                              });
                              if (_inKindAllocationMode == 'smart') {
                                _loadSmartMatch();
                              }
                            }
                            Navigator.pop(ctx);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.donorGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add to Donation',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pledge Card — Direct Give (one card per needed item) ─────────────────
  Widget _buildPledgeCard({
    required String itemName,
    required num neededQty,
    String? unit, // Unit from family.itemUnits — accurate first-class unit
    required bool isPledged,
    bool isDonated = false,
    required ThemeData theme,
    required bool isDark,
    required VoidCallback onToggle,
  }) {
    final itemColor = isDonated ? Colors.grey : AppColors.donorGreen;
    final nameLower = itemName.toLowerCase();
    IconData itemIcon = Icons.inventory_2_outlined;
    if (nameLower.contains('flour') ||
        nameLower.contains('wheat') ||
        nameLower.contains('aata')) {
      itemIcon = Icons.grass;
    } else if (nameLower.contains('oil') || nameLower.contains('ghee')) {
      itemIcon = Icons.water_drop_outlined;
    } else if (nameLower.contains('sugar') || nameLower.contains('salt')) {
      itemIcon = Icons.grain;
    } else if (nameLower.contains('soap') || nameLower.contains('wash')) {
      itemIcon = Icons.clean_hands_outlined;
    } else if (nameLower.contains('rice') ||
        nameLower.contains('daal') ||
        nameLower.contains('lentil')) {
      itemIcon = Icons.rice_bowl_outlined;
    } else if (nameLower.contains('date') || nameLower.contains('khajoor')) {
      itemIcon = Icons.spa_outlined;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isPledged
            ? itemColor.withValues(alpha: 0.08)
            : (isDark ? Colors.grey[850] : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPledged
              ? itemColor
              : theme.dividerColor.withValues(alpha: 0.2),
          width: isPledged ? 2 : 1,
        ),
        boxShadow: isPledged
            ? [
                BoxShadow(
                  color: itemColor.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPledged
                    ? itemColor
                    : itemColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                itemIcon,
                color: isPledged ? Colors.white : itemColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDonated
                        ? 'Fully Supported: ${_getFormattedQuantity(itemName, neededQty, unit: unit)}'
                        : 'Needed: ${_getFormattedQuantity(itemName, neededQty, unit: unit)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDonated
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : isPledged
                          ? itemColor
                          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      decoration: isDonated ? TextDecoration.lineThrough : null,
                      fontWeight: isPledged && !isDonated
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: isDonated ? null : onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDonated
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.1)
                      : isPledged
                      ? itemColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDonated
                        ? Colors.transparent
                        : isPledged
                        ? itemColor
                        : theme.dividerColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDonated
                          ? Icons.check_circle
                          : isPledged
                          ? Icons.check_circle_outline
                          : Icons.volunteer_activism_outlined,
                      size: 16,
                      color: isDonated
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : isPledged
                          ? Colors.white
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isDonated
                          ? 'Donated ✓'
                          : isPledged
                          ? 'Committed ✓'
                          : 'I Can Donate',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDonated
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                            : isPledged
                            ? Colors.white
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Old stepper row — still used for Pool/Smart free quantity entry ─────────
  Widget _buildItemStepperRow({
    required String itemName,
    required num neededQty,
    required num currentQty,
    String? unit, // New: optional unit for accuracy
    required ThemeData theme,
    required bool isDark,
    bool unlimitedQty = false,
    bool allOrNothing = false,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
    VoidCallback? onDelete,
  }) {
    final isSelected = currentQty > 0;
    const itemColor = AppColors.donorGreen;
    final nameLower = itemName.toLowerCase();
    IconData itemIcon = Icons.inventory_2_outlined;
    if (nameLower.contains('flour') ||
        nameLower.contains('wheat') ||
        nameLower.contains('aata')) {
      itemIcon = Icons.grass;
    } else if (nameLower.contains('oil') || nameLower.contains('ghee')) {
      itemIcon = Icons.water_drop_outlined;
    } else if (nameLower.contains('sugar') || nameLower.contains('salt')) {
      itemIcon = Icons.grain;
    } else if (nameLower.contains('soap') || nameLower.contains('wash')) {
      itemIcon = Icons.clean_hands_outlined;
    } else if (nameLower.contains('rice') ||
        nameLower.contains('daal') ||
        nameLower.contains('lentil')) {
      itemIcon = Icons.rice_bowl_outlined;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? itemColor.withValues(alpha: 0.05)
            : (isDark ? Colors.grey[850] : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? itemColor.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? itemColor
                    : itemColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                itemIcon,
                color: isSelected ? Colors.white : itemColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (!unlimitedQty)
                    Text(
                      'Goal: ${_getFormattedQuantity(itemName, neededQty, unit: unit)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.redAccent,
                onPressed: onDelete,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(right: 8),
              ),
            allOrNothing
                ? Switch(
                    value: currentQty > 0,
                    onChanged: (val) {
                      if (val) {
                        onIncrement();
                      } else {
                        onDecrement();
                      }
                    },
                    activeThumbColor: itemColor,
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: currentQty > 0 ? onDecrement : null,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: currentQty > 0
                                  ? Colors.white
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              boxShadow: currentQty > 0
                                  ? [
                                      const BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              Icons.remove,
                              size: 16,
                              color: currentQty > 0
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 40),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            currentQty > 0
                                ? _getFormattedQuantity(
                                    itemName,
                                    currentQty,
                                    unit: unit,
                                  )
                                : '0',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14, // Slightly smaller to fit units
                              color: isSelected
                                  ? itemColor
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onIncrement,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: unlimitedQty || currentQty < neededQty
                                  ? itemColor
                                  : Colors.orange.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: unlimitedQty || currentQty < neededQty
                                  ? Colors.white
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Main In-Kind Donation Form ───────────────────────────────────────────────
  Widget _buildInKindDonationForm(Family? family) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDirectMode = _inKindAllocationMode == 'direct';
    final isPoolMode = _inKindAllocationMode == 'pool';
    final isSmartMode = _inKindAllocationMode == 'smart';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode selector (always at top)
          _buildInKindGivingModeSelector(),
          const SizedBox(height: 14),

          // Trust banners
          if (isPoolMode) ...[
            _buildInKindPoolBanner(),
            const SizedBox(height: 14),
          ],
          if (isSmartMode) ...[
            _buildInKindSmartBanner(),
            const SizedBox(height: 14),
          ],

          // Family picker (Direct only)
          if (isDirectMode) ...[
            _buildFamilySelectionCard(),
            const SizedBox(height: 14),
          ],

          // Smart match result
          if (isSmartMode) ...[
            _buildSmartGiveCard(),
            const SizedBox(height: 14),
          ],

          // Items section header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Items to Donate',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (_selectedItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.donorGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selectedItems.length} selected',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.donorGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── DIRECT: Show Pledge Cards ────────────────────────────────────
          if (isDirectMode && family != null && family.needs.isNotEmpty) ...[
            // All-or-nothing notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.donorGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.donorGreen.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.donorGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Commit to donating items in full quantities for efficient logistics. Each item is collected as a whole unit.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.donorGreen.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Pledge summary chip
            if (_selectedItems.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.donorGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '✅ ${_selectedItems.length} of ${family.needs.length} items committed',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.donorGreen,
                  ),
                ),
              ),
            // Donation commitment cards
            ...(family.originalNeeds.isNotEmpty
                    ? family.originalNeeds
                    : family.needs)
                .entries
                .map((entry) {
                  final String itemName = entry.key;
                  final num originalQty = entry.value;
                  // Use the unit stored in family.itemUnits for accurate display.
                  // This value comes directly from the assistance pack definition.
                  final String? itemUnit =
                      family.itemUnits[itemName]?.isNotEmpty == true
                      ? family.itemUnits[itemName]
                      : null;
                  final bool isDonated =
                      family.needs.containsKey(itemName) &&
                      family.needs[itemName]! <= 0;
                  final bool isPledged = _selectedItems.containsKey(itemName);
                  return _buildPledgeCard(
                    itemName: itemName,
                    neededQty: originalQty,
                    unit: itemUnit,
                    isPledged: isPledged,
                    isDonated: isDonated,
                    theme: theme,
                    isDark: isDark,
                    onToggle: () {
                      if (isDonated) return;
                      setState(() {
                        if (isPledged) {
                          _selectedItems.remove(itemName);
                        } else {
                          _selectedItems[itemName] = originalQty;
                        }
                      });
                    },
                  );
                }),
          ] else if (isDirectMode && family == null)
            // No family selected empty state
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.family_restroom_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Family Selected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a family above to see their requested items.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          // ── POOL / SMART: Show selected items as chiplist + stepper ──────
          else if ((isPoolMode || isSmartMode) && _selectedItems.isNotEmpty)
            ..._selectedItems.entries.map((entry) {
              final String itemName = entry.key;
              final num currentQty = entry.value;

              // Find standard pack step size
              final standardItem = _availablePackItems
                  .where((p) => p.name == itemName)
                  .firstOrNull;
              final num stepSize = standardItem?.quantityNum ?? 1;

              return _buildItemStepperRow(
                itemName: itemName,
                neededQty: 9999,
                currentQty: currentQty,
                unit: standardItem?.unit,
                theme: theme,
                isDark: isDark,
                unlimitedQty: true,
                allOrNothing: false,
                onIncrement: () {
                  setState(
                    () => _selectedItems[itemName] = currentQty + stepSize,
                  );
                  if (isSmartMode) _loadSmartMatch();
                },
                onDecrement: () {
                  setState(() {
                    if (currentQty <= stepSize) {
                      _selectedItems.remove(itemName);
                    } else {
                      _selectedItems[itemName] = currentQty - stepSize;
                    }
                  });
                  if (isSmartMode) _loadSmartMatch();
                },
                onDelete: () {
                  setState(() {
                    _selectedItems.remove(itemName);
                  });
                  if (isSmartMode) _loadSmartMatch();
                },
              );
            })
          else if (isPoolMode || isSmartMode)
            // Empty state for pool/smart
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_box_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isSmartMode
                        ? 'Add items to find the best family'
                        : 'Add items to donate',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSmartMode
                        ? 'The system will automatically split items across families with the highest need.'
                        : 'Our team will assign your donated items to the family with the greatest need.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          // Add Item button for Pool/Smart — uses guided bottom sheet
          if (isPoolMode || isSmartMode) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAddItemBottomSheet,
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.donorGreen,
                  size: 18,
                ),
                label: const Text(
                  'Add Item to Donate',
                  style: TextStyle(
                    color: AppColors.donorGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppColors.donorGreen,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],

          // Overflow summary banner
          if (_overflowItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz, color: Colors.teal, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Overflow → Pool: ${_overflowItems.entries.map((e) => '${e.key}×${e.value}').join(', ')}',
                      style: const TextStyle(
                        color: Colors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Pickup Information
          Text(
            'Pickup Information',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactController,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Contact Number',
              hintText: '03XX-XXXXXXX',
              prefixIcon: const Icon(Icons.phone, color: AppColors.donorGreen),
              filled: true,
              fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.donorGreen,
                  width: 2,
                ),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please enter contact number' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressController,
            maxLines: 2,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Pickup Address',
              hintText: 'Enter full address for pickup',
              prefixIcon: const Icon(
                Icons.location_on,
                color: AppColors.donorGreen,
              ),
              filled: true,
              fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.donorGreen,
                  width: 2,
                ),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Please enter pickup address' : null,
          ),
          const SizedBox(height: 24),
          Text(
            '📸 Item Photo Proof',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildImageUploadCard(),
          const SizedBox(height: 16),
          _buildOptionalFields(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildFamilySelectionCard() {
    final isSelected = _selectedFamily != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () async {
        final selected = await Navigator.push<Family>(
          context,
          MaterialPageRoute(
            builder: (_) => FamilySelectionScreen(
              // Fix #13 — when in In-Kind tab, only show Food/combined families
              inKindOnly: _donationType == DonationType.inKind,
            ),
          ),
        );

        if (selected != null) {
          setState(() {
            _selectedFamily = selected;
            _setupFamilyStream();
          });
          // Fix #11 — update tab visibility for the newly selected family
          _updateTabsForFamily(selected);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.donorGreen.withValues(alpha: isDark ? 0.15 : 0.08)
              : (isDark ? Colors.grey[800] : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.donorGreen
                : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.donorGreen.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.donorGreen
                    : (isDark ? Colors.grey[700] : Colors.grey[100]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.family_restroom,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey[400] : Colors.grey[500]),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSelected ? _selectedFamily!.area : 'Select Family',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isSelected)
                    Text(
                      '${_selectedFamily!.numberOfAdults} Adults • ${_selectedFamily!.numberOfChildren} Children',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 13,
                      ),
                    )
                  else
                    Text(
                      'Tap to choose a family to support',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isSelected
                  ? AppColors.donorGreen
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageUploadCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: _isUploading ? null : _pickAndUploadImage,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: _paymentProofUrl != null
              ? AppColors.donorGreen
              : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
          strokeWidth: 2,
          gap: 6,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _paymentProofUrl != null
                ? AppColors.donorGreen.withValues(alpha: 0.05)
                : (isDark
                      ? Colors.grey[800]!.withValues(alpha: 0.5)
                      : Colors.grey[50]!),
          ),
          child: Column(
            children: [
              if (_isUploading)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Uploading proof...'),
                  ],
                )
              else if (_paymentProofUrl != null)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: AppColors.donorGreen,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _donationType == DonationType.inKind
                          ? 'Item Photo Uploaded! ✓'
                          : 'Payment Proof Uploaded!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickAndUploadImage,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Replace Image'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.donorGreen,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: 32,
                        color: AppColors.donorGreen,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _donationType == DonationType.inKind
                          ? 'Tap to Upload Item Photo'
                          : 'Tap to Upload Payment Proof',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Screenshots or photos accepted',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionalFields() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Anonymous checkbox
        CheckboxListTile(
          value: _isAnonymous,
          onChanged: (value) {
            setState(() => _isAnonymous = value ?? false);
          },
          title: Text(
            'Anonymous Donation',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
          subtitle: Text(
            'Your name will not be shared with the family',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          activeColor: AppColors.donorGreen,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),

        // Donation note
        Text(
          'Donation Note (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _noteController,
          maxLines: 3,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Add a message or note...',
            filled: true,
            fillColor:
                theme.inputDecorationTheme.fillColor ??
                (isDark ? Colors.grey[800] : Colors.white),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyBottomActions() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () => _saveDonation(submitForVerification: false),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.donorGreen.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Draft',
                        style: TextStyle(
                          color: AppColors.donorGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _saveDonation(submitForVerification: true),
                icon: const Icon(
                  Icons.verified_user,
                  size: 20,
                  color: Colors.white,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.donorGreen,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                label: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Complete Donation',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.gap = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(16),
        ),
      );

    final Path dashPath = Path();
    final double dashWidth = 8.0;
    final double dashSpace = gap;
    double distance = 0.0;

    for (final ui.PathMetric metric in path.computeMetrics()) {
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
