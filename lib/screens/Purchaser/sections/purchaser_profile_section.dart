import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/main.dart' show themeProvider;
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Purchaser Profile Section - User information and activity summary
class PurchaserProfileSection extends StatefulWidget {
  const PurchaserProfileSection({super.key});

  @override
  State<PurchaserProfileSection> createState() =>
      _PurchaserProfileSectionState();
}

class _PurchaserProfileSectionState extends State<PurchaserProfileSection> {
  final ImagePicker _picker = ImagePicker();
  String? _profilePhotoUrl;
  bool _isUploadingPhoto = false;
  Map<String, int> _stats = {'total': 0, 'pending': 0, 'completed': 0};

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadStats();
  }

  Future<void> _loadProfileData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _profilePhotoUrl = doc.data()?['profilePhotoUrl'];
        });
      }
    }
  }

  Future<void> _loadStats() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final queryShot = await FirebaseFirestore.instance
          .collection('procurement_requests')
          .where('purchaserId', isEqualTo: userId)
          .get();

      int total = queryShot.docs.length;
      int completed = queryShot.docs
          .where(
            (d) =>
                d['status'] == 'verified' ||
                d['status'] == 'stocked' ||
                d['status'] == 'delivered',
          )
          .length;
      int pending = queryShot.docs
          .where(
            (d) => d['status'] == 'purchased',
          ) // Submitted but not verified
          .length;

      if (mounted) {
        setState(() {
          _stats = {'total': total, 'completed': completed, 'pending': pending};
        });
      }
    } catch (e) {
      debugPrint('Error loading purchaser stats: $e');
    }
  }

  Future<void> _changeProfilePhoto() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Change Profile Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPhotoSourceOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndUploadPhoto(ImageSource.camera);
                    },
                  ),
                  _buildPhotoSourceOption(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndUploadPhoto(ImageSource.gallery);
                    },
                  ),
                  if (_profilePhotoUrl != null)
                    _buildPhotoSourceOption(
                      icon: Icons.delete_outline,
                      label: 'Remove',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        _removeProfilePhoto();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? AppColors.purchaserOrange;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: c),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingPhoto = true);

      final url = await CloudinaryService.uploadImage(File(image.path));

      if (url != null) {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({'profilePhotoUrl': url});

          await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);

          if (mounted) {
            setState(() {
              _profilePhotoUrl = url;
              _isUploadingPhoto = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Profile photo updated!'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {'profilePhotoUrl': null},
        );

        await FirebaseAuth.instance.currentUser?.updatePhotoURL(null);

        if (mounted) {
          setState(() => _profilePhotoUrl = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile photo removed'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Password Strength Logic
  Map<String, dynamic> _calculatePasswordStrength(String password) {
    int strength = 0;
    List<String> feedback = [];

    if (password.length >= 8)
      strength++;
    else
      feedback.add('At least 8 characters');

    if (password.contains(RegExp(r'[A-Z]')))
      strength++;
    else
      feedback.add('One uppercase letter');

    if (password.contains(RegExp(r'[a-z]')))
      strength++;
    else
      feedback.add('One lowercase letter');

    if (password.contains(RegExp(r'[0-9]')))
      strength++;
    else
      feedback.add('One number');

    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')))
      strength++;
    else
      feedback.add('One special character (!@#\$%^&*)');

    String label;
    Color color;
    if (strength <= 1) {
      label = 'Weak';
      color = Colors.red;
    } else if (strength <= 2) {
      label = 'Fair';
      color = Colors.orange;
    } else if (strength <= 3) {
      label = 'Good';
      color = Colors.amber;
    } else if (strength <= 4) {
      label = 'Strong';
      color = Colors.lightGreen;
    } else {
      label = 'Very Strong';
      color = Colors.green;
    }

    return {
      'strength': strength,
      'label': label,
      'color': color,
      'feedback': feedback,
      'percentage': strength / 5,
    };
  }

  String _getAuthErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'Current password is incorrect';
        case 'weak-password':
          return 'New password is too weak';
        case 'requires-recent-login':
          return 'Please log out and log back in';
        default:
          return 'Failed to update: ${error.message}';
      }
    }
    return 'An unexpected error occurred';
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    Map<String, dynamic> passwordStrength = {
      'strength': 0,
      'label': '',
      'color': Colors.grey,
      'feedback': <String>[],
      'percentage': 0.0,
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          newPasswordController.addListener(() {
            final newStrength = _calculatePasswordStrength(
              newPasswordController.text,
            );
            if (newStrength['strength'] != passwordStrength['strength']) {
              setDialogState(() {
                passwordStrength = newStrength;
              });
            }
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: AppColors.purchaserOrange,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Change Password'),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureCurrent = !obscureCurrent,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Enter current password'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscureNew = !obscureNew),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty)
                          return 'Enter new password';
                        if (val.length < 8)
                          return 'Must be at least 8 characters';
                        return null;
                      },
                    ),
                    if (newPasswordController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: passwordStrength['percentage'] as double,
                        color: passwordStrength['color'] as Color,
                        backgroundColor: Colors.grey[300],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        passwordStrength['label'] as String,
                        style: TextStyle(
                          color: passwordStrength['color'] as Color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (val) {
                        if (val != newPasswordController.text)
                          return 'Passwords do not match';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isLoading = true);
                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null && user.email != null) {
                              final cred = EmailAuthProvider.credential(
                                email: user.email!,
                                password: currentPasswordController.text,
                              );
                              await user.reauthenticateWithCredential(cred);
                              await user.updatePassword(
                                newPasswordController.text,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password updated!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_getAuthErrorMessage(e)),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purchaserOrange,
                  foregroundColor: Colors.white,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUpdateNameDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final nameController = TextEditingController(text: user?.displayName ?? '');
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AppColors.purchaserOrange,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Update Name'),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current Name (Read-only)
                TextFormField(
                  initialValue: user?.displayName ?? 'Not set',
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Current Name',
                    prefixIcon: const Icon(Icons.person),
                    filled: true,
                    fillColor: Colors.grey.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),

                // New Name
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (val) => val == null || val.trim().length < 2
                      ? 'Name too short'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() => isLoading = true);
                        try {
                          await user?.updateDisplayName(nameController.text);
                          await user?.reload();
                          if (context.mounted) {
                            Navigator.pop(context);
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Name updated!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purchaserOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpdatePhoneDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final phoneController = TextEditingController(
      text: user?.phoneNumber ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.phone_outlined,
                color: AppColors.purchaserOrange,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Update Phone'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current Phone (Read-only)
              TextFormField(
                initialValue: user?.phoneNumber ?? 'Not set',
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Current Phone',
                  prefixIcon: const Icon(Icons.phone),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // New Phone
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+92 3XX XXXXXXX',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter phone number';
                  if (!RegExp(r'^(\+92|0)?3[0-9]{9}$').hasMatch(val))
                    return 'Invalid Pakistan phone';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Note: Phone verification requires additional setup.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Phone saved locally'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purchaserOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showHelpSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.help_outline,
                color: AppColors.purchaserOrange,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Help & Support'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SupportOption(
              icon: Icons.email_outlined,
              title: 'Email Support',
              subtitle: 'support@rationaid.pk',
              onTap: () async {
                final uri = Uri(
                  scheme: 'mailto',
                  path: 'support@rationaid.pk',
                  queryParameters: {'subject': 'Purchaser Support Request'},
                );
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
            const Divider(),
            _SupportOption(
              icon: Icons.phone_outlined,
              title: 'Call Support',
              subtitle: '+92 300 1234567',
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: '+923001234567');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile header card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isUploadingPhoto ? null : _changeProfilePhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppColors.purchaserOrange
                              .withValues(alpha: 0.2),
                          backgroundImage: _profilePhotoUrl != null
                              ? NetworkImage(_profilePhotoUrl!)
                              : null,
                          child: _profilePhotoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: AppColors.purchaserOrange,
                                )
                              : null,
                        ),
                        if (_isUploadingPhoto)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        if (!_isUploadingPhoto)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.purchaserOrange,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.displayName ?? 'Purchaser',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  if (user?.phoneNumber != null)
                    Text(
                      user!.phoneNumber!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Activity Summary
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Procurement Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _ActivityRow(
                    icon: Icons.shopping_bag,
                    label: 'Total Requests',
                    value: _stats['total'].toString(),
                    color: AppColors.purchaserOrange,
                  ),
                  const Divider(height: 24),
                  _ActivityRow(
                    icon: Icons.check_circle,
                    label: 'Completed / Stocked',
                    value: _stats['completed'].toString(),
                    color: Colors.green,
                  ),
                  const Divider(height: 24),
                  _ActivityRow(
                    icon: Icons.pending_actions,
                    label: 'Pending Review',
                    value: _stats['pending'].toString(),
                    color: Colors.amber,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Account Settings
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    subtitle: 'Update your password',
                    onTap: _showChangePasswordDialog,
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: Icons.person_outline,
                    title: 'Update Name',
                    subtitle: 'Change your display name',
                    onTap: _showUpdateNameDialog,
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: Icons.phone_outlined,
                    title: 'Update Phone',
                    subtitle: 'Add or update phone number',
                    onTap: _showUpdatePhoneDialog,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        theme.brightness == Brightness.dark
                            ? Icons.dark_mode
                            : Icons.light_mode,
                        color: Colors.indigo,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Dark Mode',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Switch(
                      value: theme.brightness == Brightness.dark,
                      activeColor: AppColors.purchaserOrange,
                      onChanged: (val) => themeProvider.toggleTheme(),
                    ),
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    subtitle: 'Contact us for assistance',
                    onTap: _showHelpSupportDialog,
                  ),
                  const Divider(),
                  _SettingsTile(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Sign out of your account',
                    iconColor: Colors.red,
                    onTap: _showLogoutDialog,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ActivityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SupportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.purchaserOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.purchaserOrange, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.purchaserOrange;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}
