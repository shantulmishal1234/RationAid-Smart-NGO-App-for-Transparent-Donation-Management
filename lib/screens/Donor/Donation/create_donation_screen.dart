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
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/donation_service.dart';

import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';
import 'package:ration_aid/screens/Donor/Donation/donation_success_screen.dart';

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
  final Map<String, int> _selectedItems = {}; // For in-kind donations
  bool _isSaving = false;
  StreamSubscription<DocumentSnapshot>? _familySubscription;

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
      // Pre-fill amount with remaining amount if available
      if (_selectedFamily != null && _selectedFamily!.remainingAmount > 0) {
        _amountController.text = _selectedFamily!.remainingAmount
            .toStringAsFixed(0);
      }
    }
    _setupFamilyStream();
  }

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

    _selectedItems.forEach((item, qty) {
      final needed = updatedFamily.needs[item] ?? 0;
      if (qty > needed) {
        adjustedItems.add('$item ($qty -> $needed)');
        needsUpdate = true;
      }
    });

    if (needsUpdate && mounted) {
      setState(() {
        // Create a copy of keys to avoid concurrent modification during iteration if we used forEach
        final keys = List<String>.from(_selectedItems.keys);
        for (final item in keys) {
          final currentQty = _selectedItems[item]!;
          final needed = updatedFamily.needs[item] ?? 0;

          if (needed == 0) {
            _selectedItems.remove(item);
          } else if (currentQty > needed) {
            _selectedItems[item] = needed;
          }
        }
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
    if (_selectedFamily == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a family')));
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

      final donation = Donation(
        id:
            widget.existingDonation?.id ??
            '', // Use existing ID or empty for new
        donorId: userId,
        donorName: widget.existingDonation?.donorName, // Preserve donor name
        donorEmail: widget.existingDonation?.donorEmail, // Preserve donor email
        familyId: _selectedFamily!.id,
        donationType: _donationType,
        amount:
            _donationType == DonationType.cash &&
                _amountController.text.isNotEmpty
            ? double.tryParse(_amountController.text)
            : null,
        items: _donationType == DonationType.inKind ? _selectedItems : null,
        anonymous: _isAnonymous,
        status: submitForVerification
            ? DonationStatus
                  .underVerification // FIX: was 'pending', admin notifications require 'underVerification'
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
      );

      // Update existing or create new
      if (widget.existingDonation != null) {
        await _donationService.updateDonation(donation.id, donation);
      } else {
        await _donationService.createDonation(donation);
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

        // Navigate to success screen instead of just popping
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DonationSuccessScreen(donation: donation),
          ),
        );
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
      appBarBottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        tabs: const [
          Tab(text: 'Cash Donation'),
          Tab(text: 'In-Kind Donation'),
        ],
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildCashDonationForm(_selectedFamily),
            _buildInKindDonationForm(_selectedFamily),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildCashDonationForm(Family? family) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family selection card
          _buildFamilySelectionCard(),
          const SizedBox(height: 16),

          // Amount field
          Text(
            'Donation Amount',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.donorGreen,
            ),
            decoration: InputDecoration(
              hintText: '0',
              prefixText: 'Rs. ',
              prefixStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
          if (family != null && family.targetAmount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Remaining need: PKR ${family.remainingAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.donorGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Payment proof upload
          Text(
            'Payment Proof *',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _buildImageUploadCard(),
          const SizedBox(height: 16),

          // Optional fields
          _buildOptionalFields(),
          const SizedBox(height: 100), // Bottom padding for scrolling
        ],
      ),
    );
  }

  Widget _buildInKindDonationForm(Family? family) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Family selection card
          _buildFamilySelectionCard(),
          const SizedBox(height: 16),

          // Items selection
          Text(
            'Select Items to Donate',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          if (family != null)
            ...family.needs.entries.map((entry) {
              final itemName = entry.key;
              final neededQty = entry.value;
              final currentQty = _selectedItems[itemName] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: currentQty > 0
                      ? BorderSide(color: AppColors.donorGreen, width: 2)
                      : BorderSide.none,
                ),
                elevation: currentQty > 0 ? 4 : 1,
                shadowColor: AppColors.donorGreen.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: currentQty > 0
                                  ? AppColors.donorGreen.withOpacity(0.1)
                                  : theme.dividerColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.inventory_2,
                              color: currentQty > 0
                                  ? AppColors.donorGreen
                                  : theme.iconTheme.color?.withOpacity(0.5),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  'Needed: $neededQty',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _QuantityButton(
                              icon: Icons.remove,
                              onTap: currentQty > 0
                                  ? () {
                                      setState(() {
                                        if (currentQty == 1) {
                                          _selectedItems.remove(itemName);
                                        } else {
                                          _selectedItems[itemName] =
                                              currentQty - 1;
                                        }
                                      });
                                    }
                                  : null,
                              color: AppColors.donorGreen,
                            ),
                            Text(
                              currentQty.toString(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: currentQty > 0
                                    ? AppColors.donorGreen
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            _QuantityButton(
                              icon: Icons.add,
                              onTap: () {
                                setState(() {
                                  _selectedItems[itemName] = currentQty + 1;
                                });
                              },
                              color: AppColors.donorGreen,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            })
          else
            Center(
              child: Text(
                'Please select a family first',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),

          const SizedBox(height: 16),

          const SizedBox(height: 16),

          // Contact Information
          Text(
            'Pickup Information',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // Contact Number
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter contact number';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Pickup Address
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter pickup address';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Optional fields
          _buildOptionalFields(),
          const SizedBox(height: 100), // Bottom padding for scrolling
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
          MaterialPageRoute(builder: (_) => const FamilySelectionScreen()),
        );

        if (selected != null) {
          setState(() {
            _selectedFamily = selected;
            if (_amountController.text.isEmpty &&
                _selectedFamily!.remainingAmount > 0) {
              _amountController.text = _selectedFamily!.remainingAmount
                  .toStringAsFixed(0);
            }
            _setupFamilyStream();
          });
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.donorGreen.withOpacity(isDark ? 0.15 : 0.08)
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
                  ? AppColors.donorGreen.withOpacity(0.1)
                  : Colors.black.withOpacity(0.05),
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
                    _selectedFamily!.id == 'general_relief_fund'
                        ? Text(
                            'Emergency Support Fund',
                            style: TextStyle(
                              color: AppColors.donorGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          )
                        : Text(
                            '${_selectedFamily!.numberOfAdults} Adults • ${_selectedFamily!.numberOfChildren} Children',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.7,
                              ),
                              fontSize: 13,
                            ),
                          )
                  else
                    Text(
                      'Tap to choose a family to support',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
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
                  : theme.colorScheme.onSurface.withOpacity(0.3),
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
                ? AppColors.donorGreen.withOpacity(0.05)
                : (isDark
                      ? Colors.grey[800]!.withOpacity(0.5)
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
                            color: Colors.black.withOpacity(0.05),
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
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
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
              color: theme.colorScheme.onSurface.withOpacity(0.7),
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

  Widget _buildBottomActions() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () => _saveDonation(submitForVerification: false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.donorGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () => _saveDonation(submitForVerification: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.donorGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit for Verification',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  const _QuantityButton({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null
          ? Colors.grey.withOpacity(0.1)
          : color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            color: onTap == null ? Colors.grey : color,
            size: 20,
          ),
        ),
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
