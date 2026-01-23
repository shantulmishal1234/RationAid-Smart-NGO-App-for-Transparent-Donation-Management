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

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text(
          'Delete member',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        content: Text(
          'This will remove this member profile from HRM and they will no longer '
          'appear in the system. This does NOT automatically delete their '
          'Firebase login account.\n\nAre you sure you want to continue?',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isDonor()
              ? 'View Donor Account'
              : (isEdit ? 'Edit Member' : 'Add New Member'),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.dividerColor.withOpacity(0.2),
            height: 1,
          ),
        ),
      ),
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
                    _buildSectionHeader('Basic Information'),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _nameCtrl,
                      label: 'Full Name',
                      hint: 'Enter full name',
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
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailCtrl,
                      label: 'Email Address',
                      hint: 'member@example.com',
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
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _passwordCtrl,
                        label: 'Temporary Password',
                        hint: 'Minimum 6 characters',
                        obscureText: true,
                        validator: (v) => v == null || v.length < 6
                            ? 'Min 6 characters'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneCtrl,
                      label: 'Phone Number',
                      hint: '03XX-XXXXXXX',
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
                        if (!cleaned.startsWith('03') || cleaned.length != 11) {
                          return 'Enter valid Pakistan phone (03XX-XXXXXXX)';
                        }
                        return null;
                      },
                    ),

                    // Hide designation and organization fields for donors
                    if (!_isDonor()) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader('Organization Role'),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _designationCtrl,
                        label: 'Designation',
                        hint: 'e.g. Field Officer',
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      _buildDropdown<String>(
                        label: 'Main Role',
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
                      const SizedBox(height: 16),
                      _buildDropdown<String>(
                        label: 'Hierarchy Level',
                        value: _level,
                        items: const [
                          DropdownMenuItem(value: 'head', child: Text('Head')),
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
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _teamHeadIdCtrl,
                        label: 'Team Head UID (Optional)',
                        hint: 'UID of head / sub-head',
                      ),
                    ],

                    // Hide delete button for donors (view-only)
                    if (isEdit && !_isDonor()) ...[
                      const SizedBox(height: 40),
                      Center(
                        child: TextButton.icon(
                          onPressed: _isSaving ? null : _confirmDeleteMember,
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          label: Text(
                            'Delete member profile',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),

          // Sticky bottom save button (hide for donors - view-only)
          if (!_isDonor())
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
                    onPressed: _isSaving ? null : _save,
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
                        : Text(isEdit ? 'Save Changes' : 'Create Member'),
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
    String? helperText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
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
          obscureText: obscureText,
          enabled: enabled,
          inputFormatters: inputFormatters,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            helperMaxLines: 2,
            helperStyle: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.3),
              fontSize: 14,
              fontWeight: FontWeight.normal,
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

  Widget _buildDropdown<T>({
    required String label,
    String? helperText,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
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
        DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          dropdownColor: theme.cardColor,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            helperText: helperText,
            helperStyle: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
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
          ),
        ),
      ],
    );
  }
}
