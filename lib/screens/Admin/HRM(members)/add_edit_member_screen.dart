import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class AddOrEditMemberScreen extends StatefulWidget {
  final String? uid;
  final Map<String, dynamic>? initialData;

  const AddOrEditMemberScreen({super.key, this.uid, this.initialData});

  bool get isEdit => uid != null;

  @override
  State<AddOrEditMemberScreen> createState() => _AddOrEditMemberScreenState();
}

class _AddOrEditMemberScreenState extends State<AddOrEditMemberScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _teamHeadIdCtrl = TextEditingController();

  String _department = 'Distribution';
  String _mainRole = 'distributor'; // purchaser or distributor
  String _level = 'member'; // head / sub_head / member

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.initialData != null) {
      final d = widget.initialData!;
      _nameCtrl.text = d['name'] ?? '';
      _emailCtrl.text = d['email'] ?? '';
      _phoneCtrl.text = d['phone'] ?? '';
      _designationCtrl.text = d['designation'] ?? '';
      _teamHeadIdCtrl.text = d['teamHeadId'] ?? '';

      _department = d['department'] ?? _department;

      final roles = List<String>.from(d['roles'] ?? []);
      if (roles.contains('purchaser')) {
        _mainRole = 'purchaser';
      } else if (roles.contains('distributor')) {
        _mainRole = 'distributor';
      }

      if (roles.contains('head')) {
        _level = 'head';
      } else if (roles.contains('sub_head')) {
        _level = 'sub_head';
      } else if (roles.contains('member')) {
        _level = 'member';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _designationCtrl.dispose();
    _teamHeadIdCtrl.dispose();
    super.dispose();
  }

  /// Check if the current user being edited is a donor
  bool _isDonor() {
    if (widget.initialData == null) return false;
    final roles = List<String>.from(widget.initialData!['roles'] ?? []);
    return roles.contains('donor');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      String uid = widget.uid ?? '';
      final isEdit = widget.isEdit;
      final memberName = _nameCtrl.text.trim();

      // 1. If add mode, create Auth user and send verification email
      if (!isEdit) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        uid = cred.user!.uid;
        await cred.user!.sendEmailVerification();
      }

      // 2. Build roles list
      final roles = <String>[];
      if (_mainRole == 'purchaser') {
        roles.add('purchaser');
      } else if (_mainRole == 'distributor') {
        roles.add('distributor');
      }
      if (_level == 'head') roles.add('head');
      if (_level == 'sub_head') roles.add('sub_head');
      if (_level == 'member') roles.add('member');

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final data = <String, dynamic>{
        'name': memberName,
        'email': _emailCtrl.text.trim(),
        'roles': roles,
        'designation': _designationCtrl.text.trim(),
        'department': _department,
        'phone': _phoneCtrl.text.trim(),
        'teamHeadId': _teamHeadIdCtrl.text.trim().isEmpty
            ? null
            : _teamHeadIdCtrl.text.trim(),
      };

      if (isEdit) {
        await docRef.update(data);

        await AuditService.logUserAction(
          action: 'Member profile updated',
          userId: uid,
          userName: memberName,
          details:
              'Updated roles: ${roles.join(", ")}, Department: $_department',
        );
      } else {
        await docRef.set({
          ...data,
          'joiningDate': FieldValue.serverTimestamp(),
          'deliveryCount': 0,
          'lastLoginAt': null,
          'lastActionAt': null,
        });

        await AuditService.logUserAction(
          action: 'New member created',
          userId: uid,
          userName: memberName,
          details: 'Role: $_mainRole, Level: $_level, Department: $_department',
        );
      }

      if (!mounted) return;

      if (!isEdit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Member created. Verification email sent to ${_emailCtrl.text.trim()}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      Navigator.pop(
        context,
        isEdit ? 'Member updated successfully' : 'Member created successfully',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auth error: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save member: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDeleteMember() async {
    final uid = widget.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete member'),
        content: const Text(
          'This will remove this member profile from HRM and they will no longer '
          'appear in the system. This does NOT automatically delete their '
          'Firebase login account.\n\nAre you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final memberName = widget.initialData?['name'] ?? 'Unknown member';

      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      await AuditService.logUserAction(
        action: 'Member deleted',
        userId: uid,
        userName: memberName,
        details: 'Member profile permanently removed from HRM',
      );

      if (!mounted) return;
      Navigator.pop(context, 'Member deleted successfully');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete member: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.isEdit;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          _isDonor()
              ? 'View donor account'
              : (isEdit ? 'Edit member' : 'Add member'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.badge,
                              color: AppColors.primaryBlue,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEdit
                                      ? 'Update member profile'
                                      : 'Create new member',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _sectionHeader('Basic information'),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _nameCtrl,
                        label: 'Full name',
                        hint: 'Enter full name',
                        icon: Icons.person,
                        enabled: !_isDonor(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\s]'),
                          ),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Name is required';
                          }
                          if (v.trim().length < 2) {
                            return 'Name must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _emailCtrl,
                        label: 'Email',
                        hint: 'Member email',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isEdit,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Valid email required';
                          }
                          if (!v.contains('@')) return 'Valid email required';
                          return null;
                        },
                      ),
                      if (!isEdit) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _passwordCtrl,
                          label: 'Temporary password',
                          hint: 'Minimum 6 characters',
                          icon: Icons.lock,
                          obscureText: true,
                          validator: (v) => v == null || v.length < 6
                              ? 'Min 6 characters'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _phoneCtrl,
                        label: 'Phone',
                        hint: 'Contact number (03XX-XXXXXXX)',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        enabled: !_isDonor(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return null; // Optional field
                          }
                          final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                          if (!cleaned.startsWith('03') ||
                              cleaned.length != 11) {
                            return 'Enter valid Pakistan phone (03XX-XXXXXXX)';
                          }
                          return null;
                        },
                      ),

                      // Hide designation and organization fields for donors
                      if (!_isDonor()) ...[
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _designationCtrl,
                          label: 'Designation (optional)',
                          hint: 'e.g. Field Officer, Delivery Coordinator',
                          icon: Icons.workspace_premium_outlined,
                        ),

                        const SizedBox(height: 20),
                        _sectionHeader('Organization'),
                        const SizedBox(height: 10),
                        _buildDropdown<String>(
                          label: 'Department',
                          value: _department,
                          items: const [
                            DropdownMenuItem(
                              value: 'Distribution',
                              child: Text('Distribution'),
                            ),
                            DropdownMenuItem(
                              value: 'Warehouse',
                              child: Text('Warehouse'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _department = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: 'Main role',
                          helperText:
                              'HRM can only create purchaser/distributor accounts',
                          value: _mainRole,
                          items: const [
                            DropdownMenuItem(
                              value: 'purchaser',
                              child: Text('Purchaser (Warehouse)'),
                            ),
                            DropdownMenuItem(
                              value: 'distributor',
                              child: Text('Distributor (Delivery)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _mainRole = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdown<String>(
                          label: 'Hierarchy level',
                          value: _level,
                          items: const [
                            DropdownMenuItem(
                              value: 'head',
                              child: Text('Head'),
                            ),
                            DropdownMenuItem(
                              value: 'sub_head',
                              child: Text('Sub-head'),
                            ),
                            DropdownMenuItem(
                              value: 'member',
                              child: Text('Member'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _level = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: _teamHeadIdCtrl,
                          label: 'Team head UID (optional)',
                          hint: 'UID of head / sub-head',
                          icon: Icons.group,
                        ),
                      ],

                      // Hide delete button for donors (view-only)
                      if (isEdit && !_isDonor()) ...[
                        const SizedBox(height: 24),
                        _sectionHeader('Danger zone'),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _confirmDeleteMember,
                            icon: const Icon(Icons.delete, color: Colors.red),
                            label: const Text(
                              'Delete member',
                              style: TextStyle(color: Colors.red),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sticky bottom save button (hide for donors - view-only)
          if (!_isDonor())
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
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
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isEdit ? 'Save changes' : 'Create member',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    final theme = Theme.of(context);
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
        const SizedBox(width: 6),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    String? helperText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        enabled: enabled,
        inputFormatters: inputFormatters,
        style: TextStyle(color: theme.colorScheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          helperMaxLines: 2,
          helperStyle: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          prefixIcon: icon != null
              ? Icon(
                  icon,
                  size: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    String? helperText,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: theme.cardColor,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        labelStyle: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
        helperStyle: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}
