import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
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
  bool _isAnonymous = false;
  String? _paymentProofUrl;
  bool _isUploading = false;
  final Map<String, int> _selectedItems = {}; // For in-kind donations
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _donationType = _tabController.index == 0
            ? DonationType.cash
            : DonationType.inKind;
      });
    });

    // Pre-fill form if editing existing donation
    if (widget.existingDonation != null) {
      _loadExistingDonation(widget.existingDonation!);
    } else {
      _selectedFamily = widget.selectedFamily;
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
    // Note: Family will be loaded separately via FutureBuilder
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _noteController.dispose();
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
            ? DonationStatus.underVerification
            : DonationStatus.draft,
        paymentProofUrl: _paymentProofUrl,
        donationNote: _noteController.text.isNotEmpty
            ? _noteController.text
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
        Navigator.pop(context);
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
          children: [_buildCashDonationForm(), _buildInKindDonationForm()],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildCashDonationForm() {
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

          // Amount field (optional)
          Text(
            'Donation Amount (Optional)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Enter amount in PKR',
              prefixText: 'Rs. ',
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
        ],
      ),
    );
  }

  Widget _buildInKindDonationForm() {
    final theme = Theme.of(context);

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

          if (_selectedFamily != null)
            ..._selectedFamily!.needs.entries.map((entry) {
              final itemName = entry.key;
              final neededQty = entry.value;
              final currentQty = _selectedItems[itemName] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            color: AppColors.donorGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              itemName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            'Needed: $neededQty',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            onPressed: currentQty > 0
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
                            icon: const Icon(Icons.remove_circle_outline),
                            color: AppColors.donorGreen,
                          ),
                          Expanded(
                            child: Text(
                              currentQty.toString(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedItems[itemName] = currentQty + 1;
                              });
                            },
                            icon: const Icon(Icons.add_circle_outline),
                            color: AppColors.donorGreen,
                          ),
                        ],
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

          // Optional fields
          _buildOptionalFields(),
        ],
      ),
    );
  }

  Widget _buildFamilySelectionCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.family_restroom, color: AppColors.donorGreen),
        title: Text(
          _selectedFamily != null ? _selectedFamily!.area : 'Select Family',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: _selectedFamily != null
            ? Text(
                '${_selectedFamily!.numberOfAdults} Adults • ${_selectedFamily!.numberOfChildren} Children',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            : Text(
                'Tap to choose a family',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
        onTap: () async {
          // Navigate to family selection screen
          final selected = await Navigator.push<Family>(
            context,
            MaterialPageRoute(builder: (_) => const FamilySelectionScreen()),
          );

          // Update selected family if user chose one
          if (selected != null) {
            setState(() {
              _selectedFamily = selected;
            });
          }
        },
      ),
    );
  }

  Widget _buildImageUploadCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: _isUploading ? null : _pickAndUploadImage,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (_isUploading)
                const CircularProgressIndicator()
              else if (_paymentProofUrl != null)
                Column(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.donorGreen,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payment proof uploaded',
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    TextButton(
                      onPressed: _pickAndUploadImage,
                      child: const Text('Change Image'),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 48,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to upload payment screenshot',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
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
