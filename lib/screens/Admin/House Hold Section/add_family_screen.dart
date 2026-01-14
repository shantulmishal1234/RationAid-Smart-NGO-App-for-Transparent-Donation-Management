import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class AddFamilyScreen extends StatefulWidget {
  const AddFamilyScreen({super.key});

  @override
  State<AddFamilyScreen> createState() => _AddFamilyScreenState();
}

class _AddFamilyScreenState extends State<AddFamilyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basic Information Controllers
  final _familyNameController = TextEditingController();
  final _cnicController = TextEditingController();
  final _adultsController = TextEditingController(text: '0');
  final _childrenController = TextEditingController(text: '0');

  // Location & Contact Controllers
  final _areaController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  // Additional Information Controllers
  final _emergencyContactController = TextEditingController();
  final _incomeController = TextEditingController();
  final _notesController = TextEditingController();

  // State variables
  final Set<String> _assistanceNeeds = {};

  // Document upload
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

      await FirebaseFirestore.instance.collection('families').add({
        'name': _familyNameController.text.trim(),
        'cnic': _cnicController.text.trim(),
        'adults': int.tryParse(_adultsController.text) ?? 0,
        'children': int.tryParse(_childrenController.text) ?? 0,
        'familySize': _totalFamilySize,
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryBlue,
                AppColors.accentGreen.withOpacity(0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'Add new family',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFF7FF), Color(0xFFF8FBFF)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Scrollable Form Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row inside sheet
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primaryBlue.withOpacity(0.18),
                                  AppColors.accentGreen.withOpacity(0.12),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.family_restroom,
                              color: AppColors.primaryBlue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Family registration',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Capture household details for transparent support.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Basic Information Section
                      _buildSectionHeader('Basic information'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _familyNameController,
                        label: 'Family head name',
                        hint: 'Enter family name',
                        icon: Icons.person,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\s]'),
                          ),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return 'Family name is required';
                          if (value.trim().length < 2)
                            return 'Name must be at least 2 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _cnicController,
                        label: 'CNIC (optional)',
                        hint: 'XXXXX-XXXXXXX-X',
                        icon: Icons.badge,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return null; // Optional
                          final cleaned = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (cleaned.length != 13) {
                            return 'CNIC must be 13 digits (XXXXX-XXXXXXX-X)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Total Family Size Display
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.people,
                              color: AppColors.primaryBlue,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Total family size',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _totalFamilySize.toString(),
                                style: const TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Adults / Children row
                      Row(
                        children: [
                          Expanded(
                            child: _buildNumberField(
                              controller: _adultsController,
                              label: 'Adults',
                              icon: Icons.person,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildNumberField(
                              controller: _childrenController,
                              label: 'Children (under 18)',
                              icon: Icons.child_care,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Location & Contact Section
                      _buildSectionHeader('Location & contact'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _areaController,
                        label: 'Area / city',
                        hint: 'Enter area or city',
                        icon: Icons.location_city,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Area is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _addressController,
                        label: 'Full address',
                        hint: 'Street, house number, etc.',
                        icon: Icons.home,
                        maxLines: 2,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Address is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'Contact phone (Pakistan)',
                        hint: '03XX-XXXXXXX',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          final cleaned = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (!cleaned.startsWith('03') ||
                              cleaned.length != 11) {
                            return 'Enter valid Pakistan phone (03XX-XXXXXXX)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Assistance Needs Section
                      _buildSectionHeader('Assistance needs'),
                      const SizedBox(height: 8),
                      _buildAssistanceCheckboxes(),
                      const SizedBox(height: 24),

                      // Additional Information Section
                      _buildSectionHeader('Additional information'),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _emergencyContactController,
                        label: 'Emergency contact (phone)',
                        hint: '03XX-XXXXXXX',
                        icon: Icons.contact_phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return null; // Optional
                          final cleaned = value.replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (!cleaned.startsWith('03') ||
                              cleaned.length != 11) {
                            return 'Enter valid Pakistan phone (03XX-XXXXXXX)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _incomeController,
                        label: 'Monthly income (PKR)',
                        hint: 'Enter amount in PKR',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildNotesField(),
                      const SizedBox(height: 24),

                      // Verification Documents Section
                      _buildSectionHeader('Verification documents'),
                      const SizedBox(height: 8),
                      _buildDocumentUpload(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Submit Button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveFamily,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Submit for review',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          labelStyle: TextStyle(color: Colors.grey[700]),
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.grey[600], size: 20)
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Center(
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistanceCheckboxes() {
    final needs = [
      ('Food', Icons.restaurant),
      ('Medicine', Icons.medical_services),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: needs.map((need) {
          final isSelected = _assistanceNeeds.contains(need.$1);
          return CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _assistanceNeeds.add(need.$1);
                } else {
                  _assistanceNeeds.remove(need.$1);
                }
              });
            },
            title: Text(
              need.$1,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            secondary: Icon(need.$2, color: AppColors.primaryBlue, size: 20),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            activeColor: AppColors.primaryBlue,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNotesField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: TextFormField(
        controller: _notesController,
        maxLines: 4,
        maxLength: 500,
        buildCounter:
            (context, {required currentLength, required isFocused, maxLength}) {
              return Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  '$currentLength/500 characters',
                  style: TextStyle(
                    fontSize: 11,
                    color: currentLength > 500 ? Colors.red : Colors.grey[500],
                  ),
                ),
              );
            },
        decoration: InputDecoration(
          labelText: 'Additional notes (optional)',
          hintText: 'Any special circumstances or additional information...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          labelStyle: TextStyle(color: Colors.grey[700]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  Widget _buildDocumentUpload() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              const Text(
                'Upload verification documents',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID, proof of income, utility bills, etc.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (_uploadedFileName != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _uploadedFileName!,
                      style: TextStyle(fontSize: 12, color: Colors.green[900]),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.green[700], size: 18),
                    onPressed: () {
                      setState(() {
                        _uploadedDocUrl = null;
                        _uploadedFileName = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isUploadingDoc ? null : _pickAndUploadDocument,
              icon: _isUploadingDoc
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open, size: 18),
              label: Text(
                _isUploadingDoc ? 'Uploading...' : 'Choose files',
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
