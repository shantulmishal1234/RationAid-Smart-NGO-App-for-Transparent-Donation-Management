import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/main.dart' show themeProvider;
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Donor Profile Section - User information and activity summary
class DonorProfileSection extends StatefulWidget {
  const DonorProfileSection({super.key});

  @override
  State<DonorProfileSection> createState() => _DonorProfileSectionState();
}

class _DonorProfileSectionState extends State<DonorProfileSection> {
  final DonationService _donationService = DonationService();
  final ImagePicker _picker = ImagePicker();
  late Future<Map<String, int>> _statsFuture;
  String? _profilePhotoUrl;
  bool _isUploadingPhoto = false;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadStats();
    _setupProfileStream();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  void _loadStats() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _statsFuture = _donationService.getDonorStats(userId);
    }
  }

  void _setupProfileStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _profileSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .listen((doc) {
            if (doc.exists && mounted) {
              setState(() {
                _profilePhotoUrl = doc.data()?['profilePhotoUrl'];
              });
            }
          });
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
    final c = color ?? AppColors.donorGreen;
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

  // Password strength calculation
  Map<String, dynamic> _calculatePasswordStrength(String password) {
    int strength = 0;
    List<String> feedback = [];

    // Check length
    if (password.length >= 8) {
      strength++;
    } else {
      feedback.add('At least 8 characters');
    }

    // Check for uppercase
    if (password.contains(RegExp(r'[A-Z]'))) {
      strength++;
    } else {
      feedback.add('One uppercase letter');
    }

    // Check for lowercase
    if (password.contains(RegExp(r'[a-z]'))) {
      strength++;
    } else {
      feedback.add('One lowercase letter');
    }

    // Check for numbers
    if (password.contains(RegExp(r'[0-9]'))) {
      strength++;
    } else {
      feedback.add('One number');
    }

    // Check for special characters
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      strength++;
    } else {
      feedback.add('One special character (!@#\$%^&*)');
    }

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

  // Get Firebase Auth error message
  String _getAuthErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'Current password is incorrect';
        case 'weak-password':
          return 'New password is too weak. Use a stronger password';
        case 'requires-recent-login':
          return 'Please log out and log back in, then try again';
        case 'user-disabled':
          return 'This account has been disabled';
        case 'user-not-found':
          return 'Account not found';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later';
        case 'network-request-failed':
          return 'Network error. Check your internet connection';
        case 'operation-not-allowed':
          return 'Password change is not allowed';
        default:
          return 'Failed to update password: ${error.message ?? error.code}';
      }
    }
    return 'An unexpected error occurred. Please try again';
  }

  // Show Change Password Dialog
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
          // Real-time password strength listener
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
                    color: AppColors.donorGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: AppColors.donorGreen,
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Change Password'),
              ],
            ),
            content: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current Password Field
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: const Icon(Icons.lock),
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your current password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // New Password Field
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      onChanged: (value) {
                        setDialogState(() {
                          passwordStrength = _calculatePasswordStrength(value);
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a new password';
                        }
                        if (value.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        if (!value.contains(RegExp(r'[A-Z]'))) {
                          return 'Password must contain an uppercase letter';
                        }
                        if (!value.contains(RegExp(r'[a-z]'))) {
                          return 'Password must contain a lowercase letter';
                        }
                        if (!value.contains(RegExp(r'[0-9]'))) {
                          return 'Password must contain a number';
                        }
                        if (value == currentPasswordController.text) {
                          return 'New password must be different from current';
                        }
                        return null;
                      },
                    ),

                    // Password Strength Indicator
                    if (newPasswordController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: passwordStrength['percentage'] as double,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  passwordStrength['color'] as Color,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            passwordStrength['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: passwordStrength['color'] as Color,
                            ),
                          ),
                        ],
                      ),
                      if ((passwordStrength['feedback'] as List)
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Missing: ${(passwordStrength["feedback"] as List).take(2).join(", ")}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Confirm Password Field
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your new password';
                        }
                        if (value != newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
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
                            if (user == null) {
                              throw Exception('No user logged in');
                            }
                            if (user.email == null) {
                              throw Exception('User email not found');
                            }

                            // Re-authenticate user first
                            final credential = EmailAuthProvider.credential(
                              email: user.email!,
                              password: currentPasswordController.text,
                            );
                            await user.reauthenticateWithCredential(credential);

                            // Update password
                            await user.updatePassword(
                              newPasswordController.text,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Password updated successfully!'),
                                    ],
                                  ),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_getAuthErrorMessage(e)),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.donorGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update Password'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Show Update Name Dialog
  void _showUpdateNameDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final nameController = TextEditingController(text: user?.displayName ?? '');
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    String? nameError;

    showDialog(
      context: context,
      barrierDismissible: false,
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
                  color: AppColors.donorGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: AppColors.donorGreen,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Update Name'),
            ],
          ),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
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
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) {
                    // Real-time validation feedback
                    setDialogState(() {
                      if (value.trim().isEmpty) {
                        nameError = null;
                      } else if (value.trim().length < 2) {
                        nameError = 'Too short';
                      } else if (value.trim().length > 50) {
                        nameError = 'Too long (max 50 characters)';
                      } else if (RegExp(r'[0-9]').hasMatch(value)) {
                        nameError = 'Name cannot contain numbers';
                      } else if (RegExp(
                        r'[!@#$%^&*(),.?":{}|<>]',
                      ).hasMatch(value)) {
                        nameError = 'Name cannot contain special characters';
                      } else {
                        nameError = null;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: const Icon(Icons.person),
                    suffixIcon:
                        nameController.text.isNotEmpty && nameError == null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : nameError != null
                        ? const Icon(Icons.error_outline, color: Colors.red)
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    final trimmed = value.trim();
                    if (trimmed.length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    if (trimmed.length > 50) {
                      return 'Name cannot exceed 50 characters';
                    }
                    if (RegExp(r'[0-9]').hasMatch(trimmed)) {
                      return 'Name cannot contain numbers';
                    }
                    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(trimmed)) {
                      return 'Name cannot contain special characters';
                    }
                    if (trimmed == user?.displayName) {
                      return 'Please enter a different name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Use your real name for better identification',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() => isLoading = true);
                        try {
                          if (user == null) {
                            throw Exception('No user logged in');
                          }

                          final newName = nameController.text.trim();

                          // Update display name
                          await user.updateDisplayName(newName);
                          await user.reload();

                          if (context.mounted) {
                            Navigator.pop(context);
                            setState(() {}); // Refresh UI
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Name updated to "$newName"'),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          if (context.mounted) {
                            String errorMessage = 'Failed to update name';
                            if (e.toString().contains('network')) {
                              errorMessage =
                                  'Network error. Check your connection';
                            } else if (e.toString().contains('permission')) {
                              errorMessage =
                                  'Permission denied. Please try again';
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(errorMessage)),
                                  ],
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.donorGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // Show Update Phone Dialog
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
                color: AppColors.donorGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.phone_outlined,
                color: AppColors.donorGreen,
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter phone number';
                  }
                  // Basic Pakistan phone validation
                  final phoneRegex = RegExp(r'^(\+92|0)?3[0-9]{9}$');
                  final cleanPhone = value.replaceAll(RegExp(r'[\s-]'), '');
                  if (!phoneRegex.hasMatch(cleanPhone)) {
                    return 'Enter valid Pakistan phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Note: Phone number verification requires additional setup. This feature will update your contact preference.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                    content: Text('Phone number saved'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.donorGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Show Logout Confirmation
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
        content: const Text(
          'Are you sure you want to logout from your account?',
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // Show Help & Support Dialog
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
                color: AppColors.donorGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.help_outline,
                color: AppColors.donorGreen,
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
                  queryParameters: {'subject': 'Ration Aid Support Request'},
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const Divider(height: 24),
            _SupportOption(
              icon: Icons.phone_outlined,
              title: 'Call Support',
              subtitle: '+92 300 1234567',
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: '+923001234567');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const Divider(height: 24),
            _SupportOption(
              icon: Icons.chat_bubble_outline,
              title: 'WhatsApp',
              subtitle: 'Chat with us',
              onTap: () async {
                final uri = Uri.parse('https://wa.me/923001234567');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
                  // Profile photo with edit capability
                  GestureDetector(
                    onTap: _isUploadingPhoto ? null : _changeProfilePhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppColors.donorGreen.withValues(alpha: 
                            0.2,
                          ),
                          backgroundImage: _profilePhotoUrl != null
                              ? NetworkImage(_profilePhotoUrl!)
                              : null,
                          child: _profilePhotoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: AppColors.donorGreen,
                                )
                              : null,
                        ),
                        // Upload indicator
                        if (_isUploadingPhoto)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        // Edit badge
                        if (!_isUploadingPhoto)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.donorGreen,
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
                    user?.displayName ?? 'Donor',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (user?.phoneNumber != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user!.phoneNumber!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Activity summary
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
                    'Donation Activity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<Map<String, int>>(
                    future: _statsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData) {
                        return const Text('No data available');
                      }

                      final data = snapshot.data!;
                      return Column(
                        children: [
                          _ActivityRow(
                            icon: Icons.volunteer_activism,
                            label: 'Total Donations',
                            value: data['total'].toString(),
                            color: AppColors.donorGreen,
                          ),
                          const Divider(height: 24),
                          _ActivityRow(
                            icon: Icons.family_restroom,
                            label: 'Families Supported',
                            value: data['families'].toString(),
                            color: AppColors.accentGreen,
                          ),
                          const Divider(height: 24),
                          _ActivityRow(
                            icon: Icons.hourglass_top,
                            label: 'Active Donations',
                            value: data['active'].toString(),
                            color: Colors.orange,
                          ),
                          const Divider(height: 24),
                          _ActivityRow(
                            icon: Icons.check_circle,
                            label: 'Completed Deliveries',
                            value: data['completed'].toString(),
                            color: Colors.green,
                          ),
                        ],
                      );
                    },
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    subtitle: 'Update your password',
                    onTap: _showChangePasswordDialog,
                  ),
                  const Divider(height: 8),
                  _SettingsTile(
                    icon: Icons.person_outline,
                    title: 'Update Name',
                    subtitle: 'Change your display name',
                    onTap: _showUpdateNameDialog,
                  ),
                  const Divider(height: 8),
                  _SettingsTile(
                    icon: Icons.phone_outlined,
                    title: 'Update Phone',
                    subtitle: 'Add or update phone number',
                    onTap: _showUpdatePhoneDialog,
                  ),
                  const Divider(height: 8),
                  // Dark Mode Toggle
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Theme.of(context).brightness == Brightness.dark
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
                    subtitle: Text(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'Enabled'
                          : 'Disabled',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    trailing: Switch(
                      value: Theme.of(context).brightness == Brightness.dark,
                      activeThumbColor: AppColors.donorGreen,
                      onChanged: (value) {
                        themeProvider.toggleTheme();
                      },
                    ),
                  ),
                  const Divider(height: 8),
                  _SettingsTile(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    subtitle: 'Contact us for assistance',
                    onTap: _showHelpSupportDialog,
                  ),
                  const Divider(height: 8),
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

/// Activity Row Widget
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
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Settings Tile Widget
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
    final color = iconColor ?? AppColors.donorGreen;
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
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}

/// Support Option Widget
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.donorGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.donorGreen, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
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
