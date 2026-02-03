import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

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

  final Set<String> _assistanceNeeds = {};

  String? _uploadedDocUrl;
  String? _uploadedFileName;
  bool _isUploadingDoc = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _familyNameController.dispose();
    _cnicController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _incomeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _totalFamilySize {
    final adults = int.tryParse(_adultsController.text) ?? 0;
    final children = int.tryParse(_childrenController.text) ?? 0;
    return adults + children;
  }

  Future<void> _pickAndUploadDocument() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _isUploadingDoc = true;
    });

    try {
      final file = File(picked.path);
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
        _uploadedFileName = picked.name;
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
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'documents': documents,
            'decisions': [],
          });

      // Notify Admins
      NotificationService.sendToRole(
        role: 'admin',
        title: 'New Family Registration',
        body:
            'Family ${_familyNameController.text.trim()} has been registered and is pending review.',
        data: {'familyId': docRef.id, 'type': 'household'},
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              controller: _familyNameController,
                              label: 'Family Head Name',
                              hint: 'Full Name',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
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
                    const SizedBox(height: 32),

                    _buildSectionHeader('Demographics & Income'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _adultsController,
                              label: 'Adults',
                              hint: '0',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
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
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
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

                    _buildSectionHeader('Assistance Needs'),
                    const SizedBox(height: 12),
                    FrostedPanel(child: _buildAssistanceChips()),
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
                top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
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
            color: theme.colorScheme.onSurface.withOpacity(0.7),
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
              color: theme.colorScheme.onSurface.withOpacity(0.3),
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
                color: theme.dividerColor.withOpacity(0.8),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor.withOpacity(0.8),
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
                color: theme.colorScheme.error.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistanceChips() {
    final theme = Theme.of(context);
    final needs = ['Food', 'Medicine', 'Education'];

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
                _assistanceNeeds.add(need);
              } else {
                _assistanceNeeds.remove(need);
              }
            });
          },
          selectedColor: theme.colorScheme.primary.withOpacity(0.15),
          checkmarkColor: theme.colorScheme.primary,
          labelStyle: TextStyle(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.7),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withOpacity(0.8),
            ),
          ),
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        );
      }).toList(),
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
    final isDark = theme.brightness == Brightness.dark;

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
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_uploadedDocUrl == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Supports JPG, PNG',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
