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
  bool _isSaving = false;
  StreamSubscription<DocumentSnapshot>? _familySubscription;

  // Hybrid Architecture — Giving Mode for CASH
  String _allocationMode = 'direct'; // 'direct' | 'smart' | 'general'

  // In-Kind Allocation Mode  mirrors Cash: direct | pool | smart (waterfall)
  String _inKindAllocationMode = 'direct'; // 'direct' | 'pool' | 'smart'
  Map<String, num> _overflowItems = {}; // items exceeding family need → pool
  List<InKindSplit> _smartSplits = []; // waterfall splits for Smart Give
  bool _isLoadingSmartSplits = false;

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
      // Pre-fill amount with remaining amount if available
      if (_selectedFamily != null &&
          _selectedFamily!.computedRemainingAmount > 0) {
        _amountController.text = _selectedFamily!.computedRemainingAmount
            .toStringAsFixed(0);
      }
    }
    _setupFamilyStream();
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
        tempItems.forEach((item, currentQty) {
          final needed = updatedFamily.needs[item] ?? 0;
          if (needed > 0) {
            _selectedItems[item] = currentQty > needed ? needed : currentQty;
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
      final imageUrl = await CloudinaryService.uploadImage(imageFile);

      setState(() {
        _paymentProofUrl = imageUrl;
        _isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment proof uploaded successfully')),
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
    if (_donationType == DonationType.cash) {
      if (_paymentProofUrl == null && submitForVerification) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment proof required for verification'),
          ),
        );
        return;
      }
    } else {
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

      // ── Multi-family In-Kind: create one donation doc per split ──────────
      if (_donationType == DonationType.inKind &&
          _inKindAllocationMode == 'multi' &&
          _smartSplits.isNotEmpty) {
        for (final split in _smartSplits) {
          final splitDonation = Donation(
            id: '',
            donorId: userId,
            donorName: widget.existingDonation?.donorName,
            donorEmail: widget.existingDonation?.donorEmail,
            familyId: split.familyId, // '' = pool split
            donationType: DonationType.inKind,
            amount: null,
            items: split.items,
            anonymous: _isAnonymous,
            status: submitForVerification
                ? DonationStatus.underVerification
                : DonationStatus.draft,
            paymentProofUrl: null,
            donationNote: _noteController.text.isNotEmpty
                ? _noteController.text
                : null,
            pickupAddress: _addressController.text,
            contactNumber: _contactController.text,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            statusHistory: [],
            allocationMode: split.isPool ? 'pool' : 'direct',
            effectiveAmount: 0,
            overflowAmount: 0,
            idempotencyKey: const Uuid().v4(),
          );
          await _donationService.createDonation(splitDonation);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Multi-family donation submitted (${_smartSplits.length} families)!',
              ),
            ),
          );
          Navigator.pop(context, true);
        }
        return;
      }

      // ── Determine familyId based on in-kind allocation mode ───────────
      String resolvedFamilyId;
      String resolvedMode;
      if (_donationType == DonationType.inKind) {
        switch (_inKindAllocationMode) {
          case 'pool':
            resolvedFamilyId = '';
            resolvedMode = 'pool';
          case 'smart':
            resolvedFamilyId =
                ''; // smart saves per-split above; fallthrough only
            resolvedMode = 'smart';
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
                  'Remaining Goal: PKR ${family.computedRemainingAmount.toStringAsFixed(0)}',
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
            'Payment Proof *',
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

  String _getFormattedQuantity(String itemName, num quantity) {
    final lower = itemName.toLowerCase();
    if (lower.contains('flour') ||
        lower.contains('aata') ||
        lower.contains('wheat')) {
      return '$quantity kg';
    } else if (lower.contains('oil') || lower.contains('ghee')) {
      return '$quantity Litres';
    } else if (lower.contains('sugar') ||
        lower.contains('rice') ||
        lower.contains('salt') ||
        lower.contains('daal') ||
        lower.contains('lentil')) {
      return '$quantity kg';
    } else if (lower.contains('soap') || lower.contains('wash')) {
      return '$quantity bars';
    } else if (lower.contains('dates')) {
      return '$quantity kg';
    } else if (lower.contains('rooh') || lower.contains('syrup')) {
      return '$quantity Bottles';
    }
    return '$quantity items';
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
                            : (split.family?.name ??
                                  split.family?.area ??
                                  'Family'),
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

  // ── Overflow Dialog ──────────────────────────────────────────────────────────
  Future<void> _showOverflowDialog(String itemName, num needed) async {
    final excess = (_selectedItems[itemName] ?? 0);
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('More Than Family Needs! 📦'),
        content: Text(
          'Family only needs $needed × $itemName.\n\n'
          'What should we do with the extra?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: Text(
              'Cap at $needed',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text(
              'Extra to Pool',
              style: TextStyle(color: Colors.teal),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 2),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.donorGreen,
            ),
            child: const Text(
              'All to Pool',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      if (choice == 0) {
        _selectedItems[itemName] = needed;
        _overflowItems.remove(itemName);
      } else if (choice == 1) {
        final overflow = excess - needed;
        _selectedItems[itemName] = needed;
        if (overflow > 0) _overflowItems[itemName] = overflow;
      } else {
        _overflowItems[itemName] = excess;
        _selectedItems.remove(itemName);
      }
    });
  }

  // ── Add Custom Item Dialog (Pool / Multi) ───────────────────────────────
  Future<void> _showAddCustomItemDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Item name (e.g. Rice)',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final qty = int.tryParse(qtyCtrl.text) ?? 1;
              if (name.isNotEmpty && qty > 0) {
                setState(
                  () =>
                      _selectedItems[name] = (_selectedItems[name] ?? 0) + qty,
                );
                if (_inKindAllocationMode == 'multi') _loadSmartMatch();
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.donorGreen,
            ),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Extracted Item Stepper Row ──────────────────────────────────────────────
  Widget _buildItemStepperRow({
    required String itemName,
    required num neededQty,
    required num currentQty,
    required ThemeData theme,
    required bool isDark,
    bool unlimitedQty = false,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
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
                      'Goal: ${_getFormattedQuantity(itemName, neededQty)}',
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
            Container(
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
                        color: currentQty > 0 ? Colors.black87 : Colors.grey,
                      ),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      currentQty > 0
                          ? _getFormattedQuantity(itemName, currentQty)
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

          // Items list
          if (isDirectMode && family != null)
            ...family.needs.entries.map((entry) {
              final String itemName = entry.key;
              final num neededQty = entry.value;
              final num currentQty = _selectedItems[itemName] ?? 0;
              return _buildItemStepperRow(
                itemName: itemName,
                neededQty: neededQty,
                currentQty: currentQty,
                theme: theme,
                isDark: isDark,
                onIncrement: () {
                  if (currentQty >= neededQty) {
                    // Trigger overflow dialog
                    setState(() => _selectedItems[itemName] = currentQty + 1);
                    _showOverflowDialog(itemName, neededQty);
                  } else {
                    setState(() => _selectedItems[itemName] = currentQty + 1);
                  }
                },
                onDecrement: () {
                  setState(() {
                    if (currentQty == 1) {
                      _selectedItems.remove(itemName);
                    } else {
                      _selectedItems[itemName] = currentQty - 1;
                    }
                  });
                },
              );
            })
          else if ((isPoolMode || isSmartMode) && _selectedItems.isNotEmpty)
            ..._selectedItems.entries.map((entry) {
              final String itemName = entry.key;
              final num currentQty = entry.value;
              return _buildItemStepperRow(
                itemName: itemName,
                neededQty: 9999,
                currentQty: currentQty,
                theme: theme,
                isDark: isDark,
                unlimitedQty: true,
                onIncrement: () {
                  setState(() => _selectedItems[itemName] = currentQty + 1);
                  if (isSmartMode) _loadSmartMatch();
                },
                onDecrement: () {
                  setState(() {
                    if (currentQty == 1) {
                      _selectedItems.remove(itemName);
                    } else {
                      _selectedItems[itemName] = currentQty - 1;
                    }
                  });
                  if (isSmartMode) _loadSmartMatch();
                },
              );
            })
          else
            // Empty state
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isPoolMode || isSmartMode
                        ? Icons.add_box_outlined
                        : Icons.family_restroom_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isPoolMode || isSmartMode
                        ? 'Tap “Add Item” below'
                        : 'No Family Selected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPoolMode || isSmartMode
                        ? 'Type any items you want to donate.'
                        : 'Select a family above to view their requested items.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // Add Item button for Pool/Multi
          if (isPoolMode || isSmartMode) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _showAddCustomItemDialog,
              icon: const Icon(
                Icons.add,
                color: AppColors.donorGreen,
                size: 18,
              ),
              label: const Text(
                'Add Item',
                style: TextStyle(color: AppColors.donorGreen),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.donorGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
            if (_amountController.text.isEmpty &&
                _selectedFamily!.computedRemainingAmount > 0) {
              _amountController.text = _selectedFamily!.computedRemainingAmount
                  .toStringAsFixed(0);
            }
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
                      'Payment Proof Uploaded!',
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
                      'Tap to Upload Payment Proof',
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
