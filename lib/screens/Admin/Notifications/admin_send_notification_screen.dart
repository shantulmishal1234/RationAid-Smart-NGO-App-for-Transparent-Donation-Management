import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/notification_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Send notification',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
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
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.notifications_active_outlined,
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
                            'Broadcast a notification',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Target specific roles or a single user with an in‑app notification.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _sectionTitle('Target'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(
                          'Role',
                          style: TextStyle(color: theme.colorScheme.onSurface),
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
                          style: TextStyle(color: theme.colorScheme.onSurface),
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
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
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

                const SizedBox(height: 24),

                _sectionTitle('Content'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Notification title',
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
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
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
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

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
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
                    label: Text(
                      _isLoading ? 'Sending...' : 'Send notification',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifications are stored in‑app. Push notifications to devices '
                          'require Firebase Cloud Messaging and Cloud Functions configuration.',
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
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
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
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: theme.dividerColor),
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
