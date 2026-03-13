import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/widgets/location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/services/assistance_pack_service.dart';

class AddFamilyScreen extends StatefulWidget {
  const AddFamilyScreen({super.key});

  @override
  State<AddFamilyScreen> createState() => _AddFamilyScreenState();
}

class _AddFamilyScreenState extends State<AddFamilyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _familyNameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _adultsController = TextEditingController(text: '0');
  final _childrenController = TextEditingController(text: '0');

  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  final _emergencyContactController = TextEditingController();
  final _incomeController = TextEditingController();
  final _notesController = TextEditingController();
  final _medicineBudgetController = TextEditingController();

  final Set<String> _assistanceNeeds = {};

  // Phase 3 Extended Controllers & State
  final _husbandNameController = TextEditingController();
  bool _isWidow = false;

  String _houseStatus = 'Rented'; // 'Rented' or 'Owned'
  final _rentAmountController = TextEditingController(text: '0');
  String _houseCondition = 'Average'; // 'Good', 'Average', 'Poor'
  final _houseSizeController = TextEditingController();

  final List<Map<String, dynamic>> _childrenDetails = [];

  bool _hasTransport = false;
  final _transportDetailsController = TextEditingController();

  final List<String> _availableElectronics = [
    'TV',
    'Fridge',
    'Washing Machine',
    'Water Pump (Motor)',
    'Oven',
    'Iron',
  ];
  final List<String> _selectedElectronics = [];

  final _biographyController = TextEditingController();

  String? _uploadedDocUrl;
  String? _uploadedFileName;
  bool _isUploadingDoc = false;
  bool _isSaving = false;

  // Location capture
  GeoPoint? _capturedLocation;
  String? _capturedAddress;

  @override
  void dispose() {
    _familyNameController.dispose();
    _cnicController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _incomeController.dispose();
    _notesController.dispose();
    _medicineBudgetController.dispose();

    _husbandNameController.dispose();
    _rentAmountController.dispose();
    _houseSizeController.dispose();
    _transportDetailsController.dispose();
    _biographyController.dispose();

    super.dispose();
  }

  int get _totalFamilySize {
    final adults = int.tryParse(_adultsController.text) ?? 0;
    final children = int.tryParse(_childrenController.text) ?? 0;
    return adults + children;
  }

  Future<void> _pickAndUploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _isUploadingDoc = true;
    });

    try {
      final file = File(result.files.single.path!);
      final url = await CloudinaryService.uploadImage(file);

      if (!mounted) return;

      if (url == null) {
        setState(() {
          _isUploadingDoc = false;
          _uploadedDocUrl = null;
          _uploadedFileName = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Document upload failed. Please check your internet connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isUploadingDoc = false;
        _uploadedDocUrl = url;
        _uploadedFileName = result.files.single.name;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document uploaded successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingDoc = false;
        _uploadedDocUrl = null;
        _uploadedFileName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _saveFamily() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Auto-assign pack logic
      String? assignedPackId;
      String? assignedPackName;
      double? assignedPackBudget;
      Map<String, num> initialNeeds = {};
      double initialTargetAmount = 0.0;

      if (_assistanceNeeds.contains('Food')) {
        try {
          final pack = await AssistancePackService.findMatchingPack(
            _totalFamilySize,
          );
          if (pack != null) {
            assignedPackId = pack.id;
            assignedPackName = pack.name;
            assignedPackBudget = pack.budgetAmount;
            initialTargetAmount = pack.budgetAmount;

            // Populate needs map from pack items
            for (var item in pack.items) {
              // Extract leading decimal number from quantity string
              // e.g. "5 kg" → 5, "3.5 kg" → 4, "15 kg" → 15
              final qtyMatch = RegExp(r'[\d.]+').firstMatch(item.quantity);
              final num qty = qtyMatch != null
                  ? (double.tryParse(qtyMatch.group(0)!) ?? 1.0)
                  : 1;
              initialNeeds[item.name] = qty;
            }
          }
        } catch (e) {
          print('Error finding pack: $e');
        }
      }

      // 2. Add custom medicine budget
      double customMedicineBudget = 0.0;
      if (_assistanceNeeds.contains('Medicine')) {
        customMedicineBudget =
            double.tryParse(_medicineBudgetController.text.trim()) ?? 0.0;
        initialTargetAmount += customMedicineBudget;
        initialNeeds['Medicine (Custom)'] = 1;
      }

      final List<Map<String, dynamic>> documents = _uploadedDocUrl == null
          ? []
          : [
              {
                'type': 'verification_document',
                'url': _uploadedDocUrl,
                'fileName': _uploadedFileName,
                'uploadedAt': DateTime.now(),
              },
            ];

      final docRef = await FirebaseFirestore.instance
          .collection('families')
          .add({
            'name': _familyNameController.text.trim(),
            'cnic': _cnicController.text.trim(),
            'adults': int.tryParse(_adultsController.text) ?? 0,
            'children': int.tryParse(_childrenController.text) ?? 0,
            'familySize': _totalFamilySize,
            'city': _cityController.text.trim(),
            'area': _areaController.text.trim(),
            'address': _addressController.text.trim(),
            'phone': _phoneController.text.trim(),
            'assistanceNeeds': _assistanceNeeds.toList(),
            'emergencyContact': _emergencyContactController.text.trim(),
            'monthlyIncome': int.tryParse(_incomeController.text) ?? 0,
            'remarks': _notesController.text.trim(),
            'status': 'pending_review',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'documents': documents,
            'decisions': [],
            // Pack Assignment
            'assignedPackId': assignedPackId,
            'assignedPackName': assignedPackName,
            'assignedPackBudget': assignedPackBudget,
            // Needs Map
            'needs': initialNeeds,
            // Extended Demographics & Housing
            'husbandName': _husbandNameController.text.trim(),
            'isWidow': _isWidow,
            'houseStatus': _houseStatus,
            'rentAmount': double.tryParse(_rentAmountController.text) ?? 0.0,
            'houseCondition': _houseCondition,
            'houseSize': _houseSizeController.text.trim(),
            'biography': _biographyController.text.trim(),
            'childrenDetails': _childrenDetails,
            'hasTransport': _hasTransport,
            'transportDetails': _transportDetailsController.text.trim(),
            'electronicsOwned': _selectedElectronics,
            // Location fields
            if (_capturedLocation != null) ...{
              'unverifiedLocation': _capturedLocation,
              'locationCapturedBy': FirebaseAuth.instance.currentUser?.uid,
              'locationCapturedAt': FieldValue.serverTimestamp(),
              'locationAddress': _capturedAddress,
            },
            // Review fields
            'reviewerIds': [],
            'approveCount': 0,
            'rejectCount': 0,
            'quorumThreshold': 3,
            'quorumReached': false,
            // Funding pool
            'targetAmount': initialTargetAmount,
            'raisedAmount': 0.0,
            'remainingAmount':
                initialTargetAmount, // Init remaining with target
            'customMedicineBudget': customMedicineBudget,
          });

      // Notify Admins
      await NotificationService.notifyNewFamily(
        docRef.id,
        _cityController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Family registered successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add family: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminScaffold(
      title: 'Add New Family',
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Identity Information'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isSmall = constraints.maxWidth < 450;
                          final spacing = 16.0;
                          final nameWidth = isSmall
                              ? constraints.maxWidth
                              : (constraints.maxWidth - spacing) * 0.6;
                          final cnicWidth = isSmall
                              ? constraints.maxWidth
                              : (constraints.maxWidth - spacing) * 0.4;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              SizedBox(
                                width: nameWidth,
                                child: _buildTextField(
                                  controller: _familyNameController,
                                  label: 'Family Head Name',
                                  hint: 'Full Name',
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z\s]'),
                                    ),
                                  ],
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(
                                width: cnicWidth,
                                child: _buildTextField(
                                  controller: _cnicController,
                                  label: 'CNIC',
                                  hint: 'XXXXX-XXXXXXX-X',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9\-]'),
                                    ),
                                  ],
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      if (value.length < 13) {
                                        return 'Invalid';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: _husbandNameController,
                            label: 'Spouse/Husband Name (If applicable)',
                            hint: 'Full Name',
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Is Widow?',
                              style: TextStyle(fontSize: 14),
                            ),
                            value: _isWidow,
                            onChanged: (val) => setState(() => _isWidow = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Family Composition & Dependents'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isSmall = constraints.maxWidth < 450;
                          final spacing = 16.0;
                          final adultChildWidth = isSmall
                              ? (constraints.maxWidth - spacing) / 2
                              : (constraints.maxWidth - spacing * 2) * 0.28;
                          final incomeWidth = isSmall
                              ? constraints.maxWidth
                              : (constraints.maxWidth - spacing * 2) * 0.44;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth,
                                child: Text(
                                  'Enter total number of adults and children.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: adultChildWidth,
                                child: _buildTextField(
                                  controller: _adultsController,
                                  label: 'Total Adults',
                                  hint: '0',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: adultChildWidth,
                                child: _buildTextField(
                                  controller: _childrenController,
                                  label: 'Children',
                                  hint: '0',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: incomeWidth,
                                child: _buildTextField(
                                  controller: _incomeController,
                                  label: 'Monthly Income',
                                  hint: 'PKR',
                                  keyboardType: TextInputType.number,
                                  prefixText: 'Rs. ',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    FrostedPanel(child: _buildChildrenDetailsSection()),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Financials & Housing'),
                    const SizedBox(height: 16),
                    _buildHousingSection(),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Assets (Transport & Electronics)'),
                    const SizedBox(height: 16),
                    _buildAssetsSection(),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Contact Details'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isSmall = constraints.maxWidth < 450;
                          final spacing = 16.0;
                          final itemWidth = isSmall
                              ? constraints.maxWidth
                              : (constraints.maxWidth - spacing) / 2;

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              SizedBox(
                                width: itemWidth,
                                child: _buildTextField(
                                  controller: _phoneController,
                                  label: 'Phone Number',
                                  hint: '03XX-XXXXXXX',
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(11),
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Phone number is required';
                                    }
                                    if (v.length != 11) {
                                      return 'Must be 11 digits';
                                    }
                                    if (!v.startsWith('03')) {
                                      return 'Must start with 03';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildTextField(
                                  controller: _emergencyContactController,
                                  label: 'Emergency Contact',
                                  hint: '03XX-XXXXXXX',
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(11),
                                  ],
                                  validator: (v) {
                                    if (v != null &&
                                        v.isNotEmpty &&
                                        v.length != 11) {
                                      return 'Must be 11 digits';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Location'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isSmall = constraints.maxWidth < 450;
                              final spacing = 16.0;
                              final itemWidth = isSmall
                                  ? constraints.maxWidth
                                  : (constraints.maxWidth - spacing) / 2;

                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: [
                                  SizedBox(
                                    width: itemWidth,
                                    child: _buildTextField(
                                      controller: _cityController,
                                      label: 'City',
                                      hint: 'City Name',
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'[a-zA-Z\s]'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: itemWidth,
                                    child: _buildTextField(
                                      controller: _areaController,
                                      label: 'Area',
                                      hint: 'Area Name',
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _addressController,
                            label: 'Full Address',
                            hint: 'House #, Street #, etc.',
                            maxLines: 1,
                          ),
                          const SizedBox(height: 20),
                          // GPS Location Capture
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'GPS Location (Required for Verification)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => LocationPicker(
                                  initialLocation: _capturedLocation != null
                                      ? LatLng(
                                          _capturedLocation!.latitude,
                                          _capturedLocation!.longitude,
                                        )
                                      : null,
                                  onLocationSelected: (location, address) {
                                    setState(() {
                                      _capturedLocation = GeoPoint(
                                        location.latitude,
                                        location.longitude,
                                      );
                                      _capturedAddress = address;
                                    });
                                  },
                                ),
                              );
                            },
                            icon: Icon(
                              _capturedLocation != null
                                  ? Icons.check_circle
                                  : Icons.add_location_alt,
                            ),
                            label: Text(
                              _capturedLocation != null
                                  ? 'Location Captured ✓'
                                  : 'Capture Location on Map',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _capturedLocation != null
                                  ? Colors.green
                                  : theme.colorScheme.primary,
                              side: BorderSide(
                                color: _capturedLocation != null
                                    ? Colors.green
                                    : theme.colorScheme.primary,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          if (_capturedAddress != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _capturedAddress!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Biography & Story'),
                    const SizedBox(height: 16),
                    _buildBiographySection(),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Assistance Requirements'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAssistanceChips(),
                          _buildMedicineBudgetField(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Additional Notes'),
                    const SizedBox(height: 12),
                    FrostedPanel(child: _buildNotesField()),
                    const SizedBox(height: 32),

                    _buildSectionHeader('Verification Documents'),
                    const SizedBox(height: 12),
                    FrostedPanel(child: _buildUploadZone()),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveFamily,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Submit Family'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- NEW PHASE 3 SECTIONS ---

  Widget _buildHousingSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Housing Ownership',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Rented', style: TextStyle(fontSize: 13)),
                  value: 'Rented',
                  groupValue: _houseStatus,
                  onChanged: (val) => setState(() => _houseStatus = val!),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Owned', style: TextStyle(fontSize: 13)),
                  value: 'Owned',
                  groupValue: _houseStatus,
                  onChanged: (val) {
                    setState(() {
                      _houseStatus = val!;
                      _rentAmountController.text = '0';
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
          if (_houseStatus == 'Rented') ...[
            const SizedBox(height: 16),
            _buildTextField(
              controller: _rentAmountController,
              label: 'Monthly Rent Amount',
              hint: 'e.g., 15000',
              prefixText: 'Rs. ',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'House Condition',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.surface
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.8),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _houseCondition,
                          isExpanded: true,
                          items: ['Good', 'Average', 'Poor', 'Kacha House'].map(
                            (c) {
                              return DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            },
                          ).toList(),
                          onChanged: (val) =>
                              setState(() => _houseCondition = val!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _houseSizeController,
                  label: 'House Size',
                  hint: 'e.g. 5 Marla',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBiographySection() {
    return FrostedPanel(
      child: _buildTextField(
        controller: _biographyController,
        label: 'Family Biography / Story',
        hint:
            'Describe the family situation, struggles, and why they need help...',
        maxLines: 4,
      ),
    );
  }

  Widget _buildChildrenDetailsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_childrenDetails.isNotEmpty) ...[
          // List children
          ..._childrenDetails.map(
            (child) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          child['name'] ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          (child['isStudying'] == true
                                  ? 'Studying at ${child['schoolName']} '
                                  : '') +
                              (child['isWorking'] == true
                                  ? '· Working (${child['workType']}) Rs.${child['earningAmount']}'
                                  : ''),
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
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _childrenDetails.remove(child);
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _showAddChildSheet,
          icon: const Icon(Icons.add),
          label: const Text('Add Child Details'),
        ),
      ],
    );
  }

  void _showAddChildSheet() {
    final nameCtrl = TextEditingController();
    bool isStudying = false;
    final schoolCtrl = TextEditingController();
    bool isWorking = false;
    final workCtrl = TextEditingController();
    final earningsCtrl = TextEditingController(text: '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Child Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Child Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Is Studying?'),
                      value: isStudying,
                      onChanged: (val) => setModalState(() => isStudying = val),
                    ),
                    if (isStudying)
                      TextField(
                        controller: schoolCtrl,
                        decoration: const InputDecoration(
                          labelText: 'School/College Name',
                        ),
                      ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Is Working?'),
                      value: isWorking,
                      onChanged: (val) => setModalState(() => isWorking = val),
                    ),
                    if (isWorking) ...[
                      TextField(
                        controller: workCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Type of Work',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: earningsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Monthly Earnings (Rs.)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () {
                          if (nameCtrl.text.isEmpty) return;
                          setState(() {
                            _childrenDetails.add({
                              'name': nameCtrl.text.trim(),
                              'isStudying': isStudying,
                              'schoolName': schoolCtrl.text.trim(),
                              'isWorking': isWorking,
                              'workType': workCtrl.text.trim(),
                              'earningAmount':
                                  int.tryParse(earningsCtrl.text) ?? 0,
                            });
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Save Child'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAssetsSection() {
    final theme = Theme.of(context);
    return FrostedPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text(
              'Owns Transport?',
              style: TextStyle(fontSize: 14),
            ),
            value: _hasTransport,
            onChanged: (val) {
              setState(() {
                _hasTransport = val;
                if (!val) _transportDetailsController.clear();
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          if (_hasTransport) ...[
            const SizedBox(height: 8),
            _buildTextField(
              controller: _transportDetailsController,
              label: 'Transport Details',
              hint: 'e.g., CD 70 Motorcycle, Rickshaw',
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Electronics Owned',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableElectronics.map((item) {
              final isSelected = _selectedElectronics.contains(item);
              return FilterChip(
                label: Text(item, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected)
                      _selectedElectronics.add(item);
                    else
                      _selectedElectronics.remove(item);
                  });
                },
                selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                checkmarkColor: theme.colorScheme.primary,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            prefixText: prefixText,
            prefixStyle: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surface
                : theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.8),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.8),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistanceChips() {
    final theme = Theme.of(context);
    final needs = ['Food', 'Medicine'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: needs.map((need) {
        final isSelected = _assistanceNeeds.contains(need);
        return FilterChip(
          label: Text(need),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                // Enforce single selection
                _assistanceNeeds.clear();
                _assistanceNeeds.add(need);

                // Clear the medicine budget if switching away from Medicine
                if (need != 'Medicine') {
                  _medicineBudgetController.clear();
                }
              } else {
                _assistanceNeeds.remove(need);
                if (need == 'Medicine') {
                  _medicineBudgetController.clear();
                }
              }
            });
          },
          selectedColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          checkmarkColor: theme.colorScheme.primary,
          labelStyle: TextStyle(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.8),
            ),
          ),
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        );
      }).toList(),
    );
  }

  Widget _buildMedicineBudgetField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _assistanceNeeds.contains('Medicine') ? null : 0,
      margin: EdgeInsets.only(
        top: _assistanceNeeds.contains('Medicine') ? 16 : 0,
      ),
      child: _assistanceNeeds.contains('Medicine')
          ? _buildTextField(
              controller: _medicineBudgetController,
              label: 'Monthly Medicine Cost (PKR)',
              hint: 'e.g., 2500',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (_assistanceNeeds.contains('Medicine')) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Medicine budget is required';
                  }
                  final val = double.tryParse(value);
                  if (val != null && val > 5000) {
                    return 'Max budget is Rs. 5000';
                  }
                }
                return null;
              },
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildNotesField() {
    return _buildTextField(
      controller: _notesController,
      label: 'Remarks / Notes',
      hint: 'Any additional details...',
      maxLines: 3,
    );
  }

  Widget _buildUploadZone() {
    final theme = Theme.of(context);

    return InkWell(
      onTap: _isUploadingDoc ? null : _pickAndUploadDocument,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor,
            style: BorderStyle
                .solid, // Dashed border needs custom painter, solid is fine for now or use DottedBorder package if available
          ),
        ),
        child: _isUploadingDoc
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Icon(
                    _uploadedDocUrl != null
                        ? Icons.check_circle
                        : Icons.cloud_upload_outlined,
                    size: 32,
                    color: _uploadedDocUrl != null
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _uploadedFileName ?? 'Tap to upload verification document',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_uploadedDocUrl == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Supports JPG, PNG',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
