import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

class AdminSendNotificationScreen extends StatefulWidget {
  const AdminSendNotificationScreen({super.key});

  @override
  State<AdminSendNotificationScreen> createState() =>
      _AdminSendNotificationScreenState();
}

class _AdminSendNotificationScreenState
    extends State<AdminSendNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String _targetType = 'role'; // 'role' or 'user'
  String _selectedRole = 'purchaser';
  String? _selectedUserId;
  bool _isLoading = false;

  final List<Map<String, String>> _roles = [
    {'value': 'purchaser', 'label': 'Purchasers'},
    {'value': 'distributor', 'label': 'Distributors'},
    {'value': 'donor', 'label': 'Donors'},
    {'value': 'admin', 'label': 'Admins'},
    {'value': 'head', 'label': 'Heads'},
    {'value': 'sub_head', 'label': 'Sub-heads'},
    {'value': 'member', 'label': 'Members'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AdminScaffold(
      title: 'Send notification',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Target Selection Card (Matches Family Header)
              FrostedPanel(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.notifications_active,
                              color: AppColors.primaryBlue,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Broadcast Target',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Select who will receive this notification.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: Text(
                                'Role',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              value: 'role',
                              groupValue: _targetType,
                              onChanged: (value) {
                                setState(() {
                                  _targetType = value!;
                                  _selectedUserId = null;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              activeColor: AppColors.primaryBlue,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: Text(
                                'Specific user',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              value: 'user',
                              groupValue: _targetType,
                              onChanged: (value) {
                                setState(() {
                                  _targetType = value!;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              activeColor: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_targetType == 'role')
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Select role',
                            labelStyle: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.7,
                              ),
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
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          items: _roles.map((role) {
                            return DropdownMenuItem(
                              value: role['value'],
                              child: Text(role['label']!),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedRole = value!;
                            });
                          },
                        )
                      else
                        _buildUserSelector(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Message Details Card (Matches Required Items)
              FrostedPanel(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Notification title',
                          labelStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          prefixIcon: Icon(
                            Icons.title,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a title';
                          }
                          return null;
                        },
                        maxLength: 50,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bodyController,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'Notification message',
                          labelStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          prefixIcon: Icon(
                            Icons.message,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                        maxLength: 200,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a message';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Send Button (Matches Donate Button)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _sendNotification,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isLoading ? 'Sending...' : 'Send Notification'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Info Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: isDark ? Colors.blue[200] : Colors.blue[700],
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Notifications are stored in‑app. Push notifications to devices '
                        'require Firebase Cloud Messaging configuration.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.blue[100] : Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserSelector() {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final users = snapshot.data!.docs;

        return DropdownButtonFormField<String>(
          initialValue: _selectedUserId,
          dropdownColor: theme.cardColor,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'Select user',
            labelStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
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
              horizontal: 16,
              vertical: 16,
            ),
          ),
          items: users.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = data['fullName'] ?? data['name'] ?? 'Unknown';
            final email = data['email'] ?? '';
            return DropdownMenuItem(
              value: doc.id,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14)),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedUserId = value;
            });
          },
          validator: (value) {
            if (_targetType == 'user' && value == null) {
              return 'Please select a user';
            }
            return null;
          },
        );
      },
    );
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    if (_targetType == 'user' && _selectedUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a user')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final title = _titleController.text.trim();
      final body = _bodyController.text.trim();

      if (_targetType == 'role') {
        await NotificationService.sendToRole(
          role: _selectedRole,
          title: title,
          body: body,
        );

        await AuditService.logSystemAction(
          action: 'Notification sent to role',
          details: 'Sent to role: $_selectedRole - Title: $title',
        );
      } else {
        await NotificationService.sendToUser(
          userId: _selectedUserId!,
          title: title,
          body: body,
        );

        await AuditService.logSystemAction(
          action: 'Notification sent to user',
          details: 'Sent to user: $_selectedUserId - Title: $title',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        _titleController.clear();
        _bodyController.clear();
        setState(() {
          _selectedUserId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
