import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/final_approval_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

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
  final _assignedAreaCtrl = TextEditingController();

  String _mainRole = 'distributor'; // purchaser or distributor
  bool _isSupervisor = false;
  bool _isFinalApprover = false;

  bool _isSaving = false;
  bool _isCurrentUserFinalApprover = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentUserPrivileges();
    if (widget.isEdit && widget.initialData != null) {
      final d = widget.initialData!;
      _nameCtrl.text = d['name'] ?? '';
      _emailCtrl.text = d['email'] ?? '';
      _phoneCtrl.text = d['phone'] ?? '';
      _designationCtrl.text = d['designation'] ?? '';
      _assignedAreaCtrl.text = d['assignedArea'] ?? '';

      final roles = List<String>.from(d['roles'] ?? []);
      if (roles.contains('purchaser')) {
        _mainRole = 'purchaser';
      } else if (roles.contains('distributor')) {
        _mainRole = 'distributor';
      }

      _isSupervisor = d['isSupervisor'] ?? false;
      _isFinalApprover = d['isFinalApprover'] ?? false;
    }
  }

  Future<void> _checkCurrentUserPrivileges() async {
    final isFA = await FinalApprovalService.isCurrentUserFinalApprover();
    if (mounted) {
      setState(() => _isCurrentUserFinalApprover = isFA);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _designationCtrl.dispose();
    _assignedAreaCtrl.dispose();
    super.dispose();
  }

  /// Check if the current member being edited is a donor
  bool _isDonor() {
    if (widget.initialData == null) return false;
    final roles = List<String>.from(widget.initialData!['roles'] ?? []);
    return roles.contains('donor');
  }

  /// Check if the current member being edited is an admin
  bool _isAdmin() {
    if (widget.initialData == null) return false;
    final roles = List<String>.from(widget.initialData!['roles'] ?? []);
    return roles.contains('admin');
  }

  /// Department is auto-derived from role — no manual override needed
  String get _department {
    if (_isAdmin()) return 'Administration';
    if (_isDonor()) return 'Donors';
    return _mainRole == 'purchaser' ? 'Warehouse' : 'Distribution';
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
      if (_isAdmin()) {
        roles.add('admin');
      } else if (_mainRole == 'purchaser') {
        roles.add('purchaser');
      } else if (_mainRole == 'distributor') {
        roles.add('distributor');
      }

      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

      final data = <String, dynamic>{
        'name': memberName,
        'email': _emailCtrl.text.trim(),
        'roles': roles,
        'designation': _designationCtrl.text.trim(),
        'department': _department,
        'phone': _phoneCtrl.text.trim(),
        'assignedArea': _assignedAreaCtrl.text.trim(),
        'isDeactivated': false,
      };

      if (isEdit) {
        final updateData = {...data, 'isSupervisor': _isSupervisor};
        // Only a Final Approver can change the isFinalApprover flag
        if (_isCurrentUserFinalApprover) {
          updateData['isFinalApprover'] = _isFinalApprover;
        }
        await docRef.update(updateData);

        await AuditService.logUserAction(
          action: 'Member profile updated',
          userId: uid,
          userName: memberName,
          details:
              'Updated roles: ${roles.join(", ")}, Department: $_department, Supervisor: $_isSupervisor, FinalApprover: $_isFinalApprover',
        );
      } else {
        await docRef.set({
          ...data,
          'isSupervisor': _isSupervisor,
          'isFinalApprover':
              false, // always false on creation — must be promoted deliberately
          'joiningDate': FieldValue.serverTimestamp(),
          'deliveryCount': 0,
          'procurementCount': 0,
          'lastLoginAt': null,
          'lastActionAt': null,
        });

        await AuditService.logUserAction(
          action: 'New member created',
          userId: uid,
          userName: memberName,
          details:
              'Role: $_mainRole, Department: $_department, Supervisor: $_isSupervisor',
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

  Future<void> _confirmDeactivateMember() async {
    final uid = widget.uid;
    if (uid == null) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text(
          'Deactivate member',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        content: Text(
          'This will mark this member as deactivated. They will no longer appear '
          'in the active HRM list and will be blocked on next sign-in.\n\n'
          'Their Firebase Auth account will be flagged as inactive via a Firestore flag. '
          'Are you sure you want to continue?',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
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
            child: const Text(
              'Deactivate',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final memberName = widget.initialData?['name'] ?? 'Unknown member';

      // Mark as deactivated instead of hard deleting — preserves audit history
      // and effectively blocks login via Firestore security rules check on isDeactivated
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isDeactivated': true,
        'deactivatedAt': FieldValue.serverTimestamp(),
      });

      await AuditService.logUserAction(
        action: 'Member deactivated',
        userId: uid,
        userName: memberName,
        details: 'Member account deactivated from HRM — login access revoked',
      );

      if (!mounted) return;
      Navigator.pop(context, 'Member deactivated successfully');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to deactivate member: $e'),
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

    return AdminScaffold(
      title: _isDonor()
          ? 'View Donor Account'
          : (isEdit ? 'Edit Member' : 'Add New Member'),
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
                    FrostedPanel(
                      child: Column(
                        children: [
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
                                return 'Email is required';
                              }
                              final emailRegex = RegExp(
                                r'^[\w.+\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$',
                              );
                              if (!emailRegex.hasMatch(v.trim())) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          if (!isEdit) ...[
                            const SizedBox(height: 16),
                            _buildPasswordField(),
                          ],
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _phoneCtrl,
                            label: 'Phone Number',
                            hint: '03XX-XXXXXXX',
                            keyboardType: TextInputType.phone,
                            enabled: !_isDonor(),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9\-]'),
                              ),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return null; // Optional field
                              }
                              final cleaned = v.replaceAll(
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
                        ],
                      ),
                    ),

                    // Hide designation and organization fields for donors and admins
                    if (_isAdmin()) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader('Administrator Account'),
                      const SizedBox(height: 16),
                      FrostedPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: theme.colorScheme.primary, size: 32),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  'This is an Administrator account. Organization role and supervisor settings are not applicable.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.8),
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (!_isDonor()) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader('Organization Role'),
                      const SizedBox(height: 16),
                      FrostedPanel(
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _designationCtrl,
                              label: 'Designation',
                              hint: 'e.g. Field Officer',
                            ),
                            const SizedBox(height: 16),

                            // Role selector
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

                            // Department — auto-locked based on role (read-only display)
                            _buildReadOnlyField(
                              label: 'Department',
                              value: _department,
                              helperText:
                                  'Auto-assigned based on role — Purchasers → Warehouse, Distributors → Distribution',
                            ),
                            const SizedBox(height: 16),

                            // Assigned Area — only for Distributors
                            if (_mainRole == 'distributor') ...[
                              _buildTextField(
                                controller: _assignedAreaCtrl,
                                label: 'Assigned Area',
                                hint: 'e.g. Lahore - Gulberg, Model Town',
                              ),
                              const SizedBox(height: 16),
                            ],

                            // isSupervisor — label adapts to role
                            _buildSwitchTile(
                              title: _mainRole == 'purchaser'
                                  ? 'Supervisor Purchaser'
                                  : 'Supervisor Distributor',
                              subtitle: _mainRole == 'purchaser'
                                  ? 'Grants access to team-wide procurement reports, inventory, and history.'
                                  : 'Grants access to team-wide delivery assignments, history, and performance.',
                              value: _isSupervisor,
                              onChanged: (val) =>
                                  setState(() => _isSupervisor = val),
                              activeColor: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ],

                    // isFinalApprover — only shown to admins if the current user is a Final Approver
                    if (_isAdmin() && _isCurrentUserFinalApprover) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader('Approval Privileges'),
                      const SizedBox(height: 16),
                      FrostedPanel(
                        child: _buildSwitchTile(
                          title: 'Final Approver',
                          subtitle:
                              'Grants power to make final approval/rejection decisions on families that have reached review quorum. Use with caution.',
                          value: _isFinalApprover,
                          onChanged: (val) =>
                              setState(() => _isFinalApprover = val),
                          activeColor: Colors.deepOrange,
                          icon: Icons.gavel_rounded,
                        ),
                      ),
                    ],

                    // Deactivate button (replaces hard delete)
                    if (isEdit && !_isDonor()) ...[
                      const SizedBox(height: 40),
                      Center(
                        child: TextButton.icon(
                          onPressed: _isSaving
                              ? null
                              : _confirmDeactivateMember,
                          icon: Icon(
                            Icons.person_off_outlined,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          label: Text(
                            'Deactivate member account',
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

  /// Password field with strength hint and visibility toggle
  Widget _buildPasswordField() {
    final theme = Theme.of(context);
    final password = _passwordCtrl.text;

    // Strength calculation
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 10) strength++;
    if (password.contains(RegExp(r'[A-Z]'))) strength++;
    if (password.contains(RegExp(r'[0-9]'))) strength++;
    if (password.contains(RegExp(r'[!@#\$%^&*]'))) strength++;

    Color strengthColor = Colors.red;
    String strengthLabel = 'Weak';
    if (strength >= 4) {
      strengthColor = Colors.green;
      strengthLabel = 'Strong';
    } else if (strength >= 2) {
      strengthColor = Colors.orange;
      strengthLabel = 'Fair';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Temporary Password',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          onChanged: (_) => setState(() {}),
          validator: (v) =>
              v == null || v.length < 6 ? 'Min 6 characters' : null,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Minimum 6 characters',
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
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
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (password.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              ...List.generate(5, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 4 ? 3 : 0),
                    decoration: BoxDecoration(
                      color: i < strength
                          ? strengthColor
                          : theme.dividerColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(
                strengthLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: strengthColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    String? helperText,
  }) {
    final theme = Theme.of(context);
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: SwitchListTile(
        secondary: icon != null
            ? Icon(
                icon,
                color: value
                    ? activeColor
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              )
            : null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        activeThumbColor: activeColor,
        onChanged: onChanged,
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
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

  Widget _buildDropdown<T>({
    required String label,
    String? helperText,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);

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
        DropdownButtonFormField<T>(
          initialValue: value,
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
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
}
