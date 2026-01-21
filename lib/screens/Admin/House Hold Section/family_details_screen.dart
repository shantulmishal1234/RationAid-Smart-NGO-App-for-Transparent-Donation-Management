import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'edit_family_screen.dart';

class FamilyDetailScreen extends StatefulWidget {
  final String familyId;
  final Map<String, dynamic> initialData;

  const FamilyDetailScreen({
    super.key,
    required this.familyId,
    required this.initialData,
  });

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  final _auth = FirebaseAuth.instance;
  User? get _currentUser => _auth.currentUser;

  late String _status;
  final _remarksController = TextEditingController();
  bool _isUpdatingStatus = false;
  bool _isLoading = false;

  late Map<String, dynamic> _familyData;
  List<dynamic> _documents = [];
  List<String> _assistanceNeeds = [];

  // Volunteer assignment variables
  String? _assignedVolunteerUid;
  String? _assignedVolunteerName;
  List<Map<String, String>> _distributors = [];
  String? _selectedDistributorUid;
  bool _loadingDistributors = true;

  @override
  void initState() {
    super.initState();
    _familyData = widget.initialData;
    _status = _familyData['status'] ?? 'pending';
    _remarksController.text = _familyData['remarks'] ?? '';
    _documents = List<dynamic>.from(_familyData['documents'] ?? []);
    _assistanceNeeds = List<String>.from(_familyData['assistanceNeeds'] ?? []);
    _assignedVolunteerUid = _familyData['assignedVolunteerUid'];
    _assignedVolunteerName = _familyData['assignedVolunteerName'];
    _selectedDistributorUid = _assignedVolunteerUid;
    _loadDistributors();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadDistributors() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('roles', arrayContains: 'distributor')
          .get();

      final list = <Map<String, String>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final name = (d['name'] ?? d['email'] ?? 'Unknown') as String;
        list.add({'uid': doc.id, 'name': name});
      }

      if (!mounted) return;
      setState(() {
        _distributors = list;
        if (_assignedVolunteerUid != null &&
            list.any((e) => e['uid'] == _assignedVolunteerUid)) {
          _selectedDistributorUid = _assignedVolunteerUid;
        } else if (list.isNotEmpty && _selectedDistributorUid == null) {
          _selectedDistributorUid = list.first['uid'];
        }
        _loadingDistributors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDistributors = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load distributors: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateStatus() async {
    setState(() => _isUpdatingStatus = true);
    try {
      final user = _currentUser;
      final familyName = _familyData['name'] ?? 'Unnamed family';

      final ref = FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId);

      await ref.update({
        'status': _status,
        'remarks': _remarksController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'decisionByUid': user?.uid,
        'decisionByName': user?.displayName ?? user?.email ?? 'Unknown admin',
        'decisionByEmail': user?.email,
        'decisions': FieldValue.arrayUnion([
          {
            'status': _status,
            'remarks': _remarksController.text.trim(),
            'decidedAt': Timestamp.now(),
            'adminUid': user?.uid,
            'adminName': user?.displayName ?? user?.email ?? 'Unknown admin',
            'adminEmail': user?.email,
          },
        ]),
      });

      // Log the action to audit trail
      await AuditService.logFamilyAction(
        action: 'Family status updated to $_status',
        familyId: widget.familyId,
        familyName: familyName,
        details: _remarksController.text.trim().isEmpty
            ? 'No remarks provided'
            : _remarksController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Update local data to reflect changes immediately
      setState(() {
        _familyData['status'] = _status;
        _familyData['remarks'] = _remarksController.text.trim();
        // Add to decisions list locally if needed, but reloading might be better
        // For now just updating main fields
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _assignVolunteerFromDropdown() async {
    final uid = _selectedDistributorUid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a volunteer to assign'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected user not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userData = userDoc.data()!;
      final name =
          (userData['name'] ?? userData['email'] ?? 'Unknown') as String;
      final familyName = _familyData['name'] ?? 'Unnamed family';

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .update({'assignedVolunteerUid': uid, 'assignedVolunteerName': name});

      // Log volunteer assignment to audit trail
      await AuditService.logFamilyAction(
        action: 'Volunteer assigned to family',
        familyId: widget.familyId,
        familyName: familyName,
        details: 'Assigned volunteer: $name',
      );

      if (!mounted) return;
      setState(() {
        _assignedVolunteerUid = uid;
        _assignedVolunteerName = name;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Volunteer assigned successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign volunteer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        title: Text(
          'Delete family',
          style: TextStyle(color: theme.colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to delete this family record? '
          'This action cannot be undone.',
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

    if (confirm != true) return;

    try {
      final familyName = _familyData['name'] ?? 'Unnamed family';

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .delete();

      // Log family deletion to audit trail
      await AuditService.logFamilyAction(
        action: 'Family deleted',
        familyId: widget.familyId,
        familyName: familyName,
        details: 'Family record permanently removed from system',
      );

      if (!mounted) return;
      Navigator.pop(context); // Go back to list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open document'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _navigateToEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditFamilyScreen(familyId: widget.familyId),
      ),
    );

    if (result == true) {
      // Reload data if edited
      setState(() => _isLoading = true);
      try {
        final doc = await FirebaseFirestore.instance
            .collection('families')
            .doc(widget.familyId)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _familyData = doc.data()!;
            _status = _familyData['status'] ?? 'pending';
            _remarksController.text = _familyData['remarks'] ?? '';
            _documents = List<dynamic>.from(_familyData['documents'] ?? []);
            _assistanceNeeds = List<String>.from(
              _familyData['assistanceNeeds'] ?? [],
            );
            _assignedVolunteerUid = _familyData['assignedVolunteerUid'];
            _assignedVolunteerName = _familyData['assignedVolunteerName'];
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error reloading data: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Extract decision history for display
    final decisions = List<Map<String, dynamic>>.from(
      _familyData['decisions'] ?? [],
    );
    final updatedAt = _familyData['updatedAt'] as Timestamp?;
    final decisionByName = _familyData['decisionByName'] as String?;
    final decisionByEmail = _familyData['decisionByEmail'] as String?;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      theme.scaffoldBackgroundColor,
                      theme.scaffoldBackgroundColor,
                    ]
                  : [
                      AppColors.primaryBlue,
                      AppColors.accentGreen.withOpacity(0.85),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: isDark
                ? Border(bottom: BorderSide(color: theme.dividerColor))
                : null,
          ),
        ),
        title: const Text(
          'Family details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _isLoading ? null : _navigateToEdit,
            tooltip: 'Edit family',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor,
                        ]
                      : [
                          theme.scaffoldBackgroundColor,
                          theme.scaffoldBackgroundColor,
                        ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Card: Status & Basic Info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.2 : 0.05,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(
                                    _status,
                                  ).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _statusColor(
                                      _status,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _statusColor(_status),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Text(
                                'ID: ...${widget.familyId.substring(widget.familyId.length - 6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                  fontFamily: 'Monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: AppColors.primaryBlue.withOpacity(
                              0.1,
                            ),
                            child: Text(
                              (_familyData['name'] as String? ?? '?')[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _familyData['name'] ?? 'Unknown Family',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (_familyData['cnic'] != null &&
                              _familyData['cnic'].toString().isNotEmpty)
                            Text(
                              'CNIC: ${_familyData['cnic']}',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem(
                                'Members',
                                '${_familyData['familySize'] ?? 0}',
                                Icons.people,
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: theme.dividerColor,
                              ),
                              _buildStatItem(
                                'Income',
                                'Rs. ${_formatCurrency(_familyData['monthlyIncome'] ?? 0)}',
                                Icons.attach_money,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Contact & Location
                    _buildInfoCard(
                      title: 'Contact & location',
                      icon: Icons.location_on,
                      children: [
                        _buildInfoRow(
                          'Phone',
                          _familyData['phone'] ?? '-',
                          Icons.phone,
                        ),
                        _buildInfoRow(
                          'City',
                          _familyData['city'] ?? '-',
                          Icons.location_city,
                        ),
                        _buildInfoRow(
                          'Area',
                          _familyData['area'] ?? '-',
                          Icons.map,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.dividerColor.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Full address',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _familyData['address'] ?? '-',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.8),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Assistance Needs
                    _buildInfoCard(
                      title: 'Assistance needs',
                      icon: Icons.volunteer_activism,
                      children: [
                        if (_assistanceNeeds.isEmpty)
                          Text(
                            'No specific needs listed.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _assistanceNeeds.map((need) {
                              return Chip(
                                label: Text(
                                  need,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                backgroundColor: theme.colorScheme.primary
                                    .withOpacity(0.1),
                                side: BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Assigned volunteer
                    _buildInfoCard(
                      title: 'Assigned volunteer',
                      icon: Icons.person_pin,
                      children: [
                        Text(
                          _assignedVolunteerName != null
                              ? '$_assignedVolunteerName'
                              : 'No volunteer assigned yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingDistributors)
                          const SizedBox(
                            height: 40,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_distributors.isEmpty)
                          const Text(
                            'No distributor accounts found in HRM.',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedDistributorUid,
                                  items: _distributors
                                      .map(
                                        (d) => DropdownMenuItem<String>(
                                          value: d['uid'],
                                          child: Text(
                                            d['name'] ?? 'Unknown',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(
                                      () => _selectedDistributorUid = value,
                                    );
                                  },
                                  dropdownColor: theme.cardColor,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Select volunteer',
                                    labelStyle: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.7),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: theme.dividerColor,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: theme.dividerColor,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _assignVolunteerFromDropdown,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Assign'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Admin Actions
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.2 : 0.05,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings,
                                size: 20,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.7,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Verification decision',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _statusChip('pending', 'Pending'),
                                const SizedBox(width: 8),
                                _statusChip('accepted', 'Approve'),
                                const SizedBox(width: 8),
                                _statusChip('rejected', 'Reject'),
                                const SizedBox(width: 8),
                                _statusChip('discarded', 'Discard'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _remarksController,
                            maxLines: 3,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Add remarks for decision...',
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: theme.scaffoldBackgroundColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.dividerColor,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: theme.dividerColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.primaryBlue,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _isUpdatingStatus
                                  ? null
                                  : _updateStatus,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: _isUpdatingStatus
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Update status',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Decision history
                    Text(
                      'Decision history',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    decisions.isEmpty
                        ? Text(
                            'No past decisions recorded yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(8),
                              itemCount: decisions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 8),
                              itemBuilder: (context, index) {
                                final d = decisions[index];
                                final status =
                                    (d['status'] ?? 'pending') as String;
                                final remarks = (d['remarks'] ?? '') as String;
                                final adminName =
                                    (d['adminName'] ?? 'Unknown') as String;
                                final ts = d['decidedAt'] as Timestamp?;
                                final when = ts != null
                                    ? _formatDate(ts.toDate())
                                    : '-';

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.history,
                                    size: 18,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                  title: Text(
                                    '$status • $when',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (remarks.isNotEmpty)
                                        'Remarks: $remarks',
                                      'By: $adminName',
                                    ].join('\n'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 16),

                    // Documents section
                    Text(
                      'Documents',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _documents.isEmpty
                        ? Text(
                            'No documents uploaded.',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.6,
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _documents.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final doc = _documents[index] as Map;
                                final url = doc['url'] as String? ?? '';
                                final type =
                                    doc['type'] as String? ?? 'Document';

                                final isPdf =
                                    type.toLowerCase().contains('pdf') ||
                                    url.toLowerCase().endsWith('.pdf');

                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isPdf
                                        ? Icons.picture_as_pdf
                                        : Icons.insert_drive_file,
                                    size: 20,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                  title: Text(
                                    type,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                  onTap: url.isEmpty
                                      ? null
                                      : () => _openDocument(url),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 24),

                    // Delete Button
                    Center(
                      child: TextButton.icon(
                        onPressed: _confirmDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        label: Text(
                          'Delete family record',
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          backgroundColor: theme.colorScheme.error.withOpacity(
                            0.1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'discarded':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Widget _statusChip(String value, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _status == value;
    final color = _statusColor(value);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _status = value),
      selectedColor: color.withOpacity(0.15),
      backgroundColor: isDark ? theme.cardColor : Colors.white,
      labelStyle: TextStyle(
        color: isSelected
            ? color
            : theme.colorScheme.onSurface.withOpacity(0.7),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      side: BorderSide(
        color: isSelected ? color : theme.dividerColor,
        width: isSelected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} '
        'at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withOpacity(0.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
