import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class EditFamilyScreen extends StatefulWidget {
  final String familyId;

  const EditFamilyScreen({super.key, required this.familyId});

  @override
  State<EditFamilyScreen> createState() => _EditFamilyScreenState();
}

class _EditFamilyScreenState extends State<EditFamilyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers (same as AddFamilyScreen)
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

  String _houseStatus = 'Rented';
  final _rentAmountController = TextEditingController(text: '0');
  String _houseCondition = 'Average';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFamily();
  }

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

  Future<void> _loadFamily() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Family not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      final data = doc.data()!;
      _familyNameController.text = data['name'] ?? '';
      _cnicController.text = data['cnic'] ?? '';
      _adultsController.text = '${data['adults'] ?? 0}';
      _childrenController.text = '${data['children'] ?? 0}';
      _cityController.text = data['city'] ?? '';
      _areaController.text = data['area'] ?? '';
      _addressController.text = data['address'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _emergencyContactController.text = data['emergencyContact'] ?? '';
      final income =
          int.tryParse(data['monthlyIncome']?.toString() ?? '0') ?? 0;
      _incomeController.text = income > 0 ? income.toString() : '';
      _notesController.text = data['remarks'] ?? '';

      _husbandNameController.text = data['husbandName'] ?? '';
      _isWidow = data['isWidow'] ?? false;
      _houseStatus = data['houseStatus'] ?? 'Rented';
      _rentAmountController.text = '${data['rentAmount'] ?? 0}';
      _houseCondition = data['houseCondition'] ?? 'Average';
      _houseSizeController.text = data['houseSize'] ?? '';
      _childrenDetails.clear();
      if (data['childrenDetails'] != null) {
        _childrenDetails.addAll(
          List<Map<String, dynamic>>.from(
            (data['childrenDetails'] as List).map(
              (i) => Map<String, dynamic>.from(i as Map),
            ),
          ),
        );
      }
      _hasTransport = data['hasTransport'] ?? false;
      _transportDetailsController.text = data['transportDetails'] ?? '';
      _selectedElectronics.clear();
      _selectedElectronics.addAll(
        List<String>.from(data['electronicsOwned'] ?? []),
      );
      _biographyController.text = data['biography'] ?? '';

      final customMedicineBudget = (data['customMedicineBudget'] ?? 0.0)
          .toDouble();
      if (customMedicineBudget > 0) {
        _medicineBudgetController.text = customMedicineBudget
            .toInt()
            .toString();
      }

      _assistanceNeeds
        ..clear()
        ..addAll(List<String>.from(data['assistanceNeeds'] ?? []));

      final docsList = List<Map<String, dynamic>>.from(data['documents'] ?? []);
      if (docsList.isNotEmpty) {
        _uploadedDocUrl = docsList.first['url'] as String?;
        _uploadedFileName = docsList.first['fileName'] as String?;
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load family: $e'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
    }
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
      final Map<String, dynamic> updateData = {
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
        'updatedAt': FieldValue.serverTimestamp(),
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
        if (_assistanceNeeds.contains('Medicine'))
          'customMedicineBudget':
              double.tryParse(_medicineBudgetController.text.trim()) ?? 0.0
        else
          'customMedicineBudget': 0.0,
      };

      if (_uploadedDocUrl != null) {
        updateData['documents'] = FieldValue.arrayUnion([
          {
            'type': 'verification_document',
            'url': _uploadedDocUrl,
            'fileName': _uploadedFileName,
            'uploadedAt': DateTime.now(),
          },
        ]);
      }

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .update(updateData);

      // Audit Log for Family Edit
      await AuditService.logFamilyAction(
        action: 'Family profile updated',
        familyId: widget.familyId,
        familyName: _familyNameController.text.trim(),
        details: 'Admin modified family details/demographics',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Family updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update family: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminScaffold(
      title: 'Edit Family Profile',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Identity Information'),
                          const SizedBox(height: 16),
                          FrostedPanel(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
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
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Required';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
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
                                  onChanged: (val) =>
                                      setState(() => _isWidow = val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          _buildSectionHeader(
                            'Family Composition & Dependents',
                          ),
                          const SizedBox(height: 16),
                          FrostedPanel(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildNumberField(
                                    controller: _adultsController,
                                    label: 'Total Adults',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildNumberField(
                                    controller: _childrenController,
                                    label: 'Children',
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: _buildTextField(
                                    controller: _incomeController,
                                    label: 'Monthly Income',
                                    hint: 'PKR',
                                    keyboardType: TextInputType.number,
                                    prefixText: 'Rs. ',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          FrostedPanel(child: _buildChildrenDetailsSection()),
                          const SizedBox(height: 32),

                          _buildSectionHeader('Financials & Housing'),
                          const SizedBox(height: 16),
                          _buildHousingSection(),
                          const SizedBox(height: 32),

                          _buildSectionHeader(
                            'Assets (Transport & Electronics)',
                          ),
                          const SizedBox(height: 16),
                          _buildAssetsSection(),
                          const SizedBox(height: 32),

                          _buildSectionHeader('Contact Details'),
                          const SizedBox(height: 16),
                          FrostedPanel(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _phoneController,
                                    label: 'Phone Number',
                                    hint: '03XX-XXXXXXX',
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _emergencyContactController,
                                    label: 'Emergency Contact',
                                    hint: '03XX-XXXXXXX',
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          _buildSectionHeader('Location'),
                          const SizedBox(height: 16),
                          FrostedPanel(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
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
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _areaController,
                                        label: 'Area',
                                        hint: 'Area Name',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _addressController,
                                  label: 'Full Address',
                                  hint: 'House #, Street #, etc.',
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          _buildSectionHeader('Biography & Story'),
                          const SizedBox(height: 16),
                          _buildBiographySection(),
                          const SizedBox(height: 32),

                          _buildSectionHeader('Assistance Needs'),
                          const SizedBox(height: 12),
                          FrostedPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildAssistanceChips(),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  height: _assistanceNeeds.contains('Medicine')
                                      ? null
                                      : 0,
                                  margin: EdgeInsets.only(
                                    top: _assistanceNeeds.contains('Medicine')
                                        ? 16
                                        : 0,
                                  ),
                                  child: _assistanceNeeds.contains('Medicine')
                                      ? _buildTextField(
                                          controller: _medicineBudgetController,
                                          label: 'Monthly Medicine Cost (PKR)',
                                          hint: 'e.g., 2500',
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          validator: (value) {
                                            if (_assistanceNeeds.contains(
                                                  'Medicine',
                                                ) &&
                                                (value == null ||
                                                    value.trim().isEmpty)) {
                                              return 'Medicine budget is required';
                                            }
                                            return null;
                                          },
                                        )
                                      : const SizedBox.shrink(),
                                ),
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
                            : const Text('Save Changes'),
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

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
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
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
          ),
        ),
      ],
    );
  }

  Widget _buildAssistanceChips() {
    final theme = Theme.of(context);
    final needs = [
      ('Food', Icons.restaurant),
      ('Medicine', Icons.medical_services),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: needs.map((need) {
        final isSelected = _assistanceNeeds.contains(need.$1);
        return FilterChip(
          label: Text(need.$1),
          avatar: isSelected
              ? null
              : Icon(
                  need.$2,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          selected: isSelected,
          onSelected: (bool selected) {
            setState(() {
              if (selected) {
                // Enforce single selection
                _assistanceNeeds.clear();
                _assistanceNeeds.add(need.$1);

                // Clear the medicine budget if switching away from Medicine
                if (need.$1 != 'Medicine') {
                  _medicineBudgetController.clear();
                }
              } else {
                _assistanceNeeds.remove(need.$1);
                if (need.$1 == 'Medicine') {
                  _medicineBudgetController.clear();
                }
              }
            });
          },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.8),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        );
      }).toList(),
    );
  }

  Widget _buildNotesField() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextFormField(
      controller: _notesController,
      maxLines: 4,
      maxLength: 500,
      style: TextStyle(color: theme.colorScheme.onSurface),
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) {
            return Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                '$currentLength/500 characters',
                style: TextStyle(
                  fontSize: 11,
                  color: currentLength > 500
                      ? Colors.red
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            );
          },
      decoration: InputDecoration(
        labelText: 'Additional notes (optional)',
        hintText: 'Any special circumstances or additional information...',
        filled: true,
        fillColor: isDark
            ? theme.scaffoldBackgroundColor
            : theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  Widget _buildUploadZone() {
    final theme = Theme.of(context);

    return InkWell(
      onTap: _isUploadingDoc ? null : _pickAndUploadDocument,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor,
            style: BorderStyle.solid,
            width: 1,
          ),
        ),
        child: _uploadedFileName != null
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _uploadedFileName!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to replace',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onPressed: () {
                      setState(() {
                        _uploadedDocUrl = null;
                        _uploadedFileName = null;
                      });
                    },
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 32,
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isUploadingDoc ? 'Uploading...' : 'Tap to upload document',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supports JPG, PNG, PDF (Max 5MB)',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
