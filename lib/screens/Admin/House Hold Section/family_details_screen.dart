import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

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
  bool _isSaving = false;

  List<dynamic> _documents = [];
  String? _assignedVolunteerUid;
  String? _assignedVolunteerName;

  // distributors list: each item { 'uid': ..., 'name': ... }
  List<Map<String, String>> _distributors = [];
  String? _selectedDistributorUid;
  bool _loadingDistributors = true;

  @override
  void initState() {
    super.initState();
    _status = widget.initialData['status'] ?? 'pending';
    _remarksController.text = widget.initialData['remarks'] ?? '';
    _documents = List<dynamic>.from(widget.initialData['documents'] ?? []);
    _assignedVolunteerUid = widget.initialData['assignedVolunteerUid'];
    _assignedVolunteerName = widget.initialData['assignedVolunteerName'];
    _selectedDistributorUid = _assignedVolunteerUid;
    _loadDistributors();
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

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final user = _currentUser;
      final data = widget.initialData;
      final familyName = data['name'] ?? 'Unnamed family';

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
      Navigator.pop(context);
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
        setState(() => _isSaving = false);
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
      final familyName = widget.initialData['name'] ?? 'Unnamed family';

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

  Future<void> _confirmDeleteFamily() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete family'),
        content: const Text(
          'Are you sure you want to delete this family record? '
          'This action cannot be undone.',
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

    if (confirm != true) return;

    try {
      final familyName = widget.initialData['name'] ?? 'Unnamed family';

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
      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final data = widget.initialData;
    final updatedAt = data['updatedAt'] as Timestamp?;
    final decisionByName = data['decisionByName'] as String?;
    final decisionByEmail = data['decisionByEmail'] as String?;
    final decisions = List<Map<String, dynamic>>.from(data['decisions'] ?? []);

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
          'Family details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete / archive',
            onPressed: _confirmDeleteFamily,
          ),
        ],
      ),
      body: Column(
        children: [
          // Main scrollable content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(color: Colors.transparent),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero header card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
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
                                  color: AppColors.primaryBlue.withOpacity(
                                    0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.family_restroom,
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
                                      data['name'] ?? 'Unnamed family',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            data['area'] ?? '',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (data['address'] != null &&
                              (data['address'] as String).isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.home,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    data['address'] ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(
                                    _status,
                                  ).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.brightness_1,
                                      size: 8,
                                      color: _statusColor(_status),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _statusColor(_status),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  updatedAt != null
                                      ? 'Last updated: ${_formatDate(updatedAt.toDate())}'
                                      : 'No decisions made yet',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          if (decisionByName != null || decisionByEmail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'By: ${decisionByName ?? decisionByEmail}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Family information
                    _buildInfoCard(
                      title: 'Family information',
                      icon: Icons.people,
                      children: [
                        _buildInfoRow(
                          'Total family size',
                          '${data['familySize'] ?? 0}',
                          Icons.groups,
                        ),
                        if (data['adults'] != null)
                          _buildInfoRow(
                            'Adults',
                            '${data['adults']}',
                            Icons.person,
                          ),
                        if (data['children'] != null)
                          _buildInfoRow(
                            'Children',
                            '${data['children']}',
                            Icons.child_care,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Contact information
                    _buildInfoCard(
                      title: 'Contact information',
                      icon: Icons.contact_phone,
                      children: [
                        if (data['phone'] != null &&
                            (data['phone'] as String).isNotEmpty)
                          _buildInfoRow('Phone', data['phone'], Icons.phone),
                        if (data['emergencyContact'] != null &&
                            (data['emergencyContact'] as String).isNotEmpty)
                          _buildInfoRow(
                            'Emergency contact',
                            data['emergencyContact'],
                            Icons.emergency,
                          ),
                        if (data['cnic'] != null &&
                            (data['cnic'] as String).isNotEmpty)
                          _buildInfoRow('CNIC', data['cnic'], Icons.badge),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Financial info
                    if (data['monthlyIncome'] != null &&
                        data['monthlyIncome'] != 0) ...[
                      _buildInfoCard(
                        title: 'Financial information',
                        icon: Icons.attach_money,
                        children: [
                          _buildInfoRow(
                            'Monthly income',
                            'PKR ${_formatCurrency((data['monthlyIncome'] as num).toInt())}',
                            Icons.account_balance_wallet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Assistance needs
                    if (data['assistanceNeeds'] != null &&
                        (data['assistanceNeeds'] as List).isNotEmpty) ...[
                      _buildInfoCard(
                        title: 'Assistance needs',
                        icon: Icons.volunteer_activism,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: (data['assistanceNeeds'] as List).map((
                              need,
                            ) {
                              return Chip(
                                label: Text(need.toString()),
                                avatar: Icon(
                                  need == 'Food'
                                      ? Icons.restaurant
                                      : Icons.medical_services,
                                  size: 16,
                                ),
                                backgroundColor: Colors.blue[50],
                                labelStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Assigned volunteer
                    _buildInfoCard(
                      title: 'Assigned volunteer',
                      icon: Icons.person_pin,
                      children: [
                        Text(
                          _assignedVolunteerName != null
                              ? '$_assignedVolunteerName ($_assignedVolunteerUid)'
                              : 'No volunteer assigned yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
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
                                  initialValue: _selectedDistributorUid,
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
                                  decoration: InputDecoration(
                                    labelText: 'Select volunteer',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
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

                    // Status & remarks
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _statusChip('pending', 'Pending'),
                        _statusChip('accepted', 'Accepted'),
                        _statusChip('rejected', 'Rejected'),
                        _statusChip('discarded', 'Discarded'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Remarks',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarksController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Add notes about this decision...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Decision history
                    Text(
                      'Decision history',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    decisions.isEmpty
                        ? Text(
                            'No past decisions recorded yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
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
                                    ? ts.toDate().toString().split('.').first
                                    : '-';

                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.history,
                                    size: 18,
                                    color: Colors.grey[600],
                                  ),
                                  title: Text(
                                    '$status • $when',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
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
                                      color: Colors.grey[600],
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
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _documents.isEmpty
                        ? Text(
                            'No documents uploaded.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
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
                                  ),
                                  title: Text(
                                    type,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  onTap: url.isEmpty
                                      ? null
                                      : () => _openDocument(url),
                                );
                              },
                            ),
                          ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),

          // Bottom save button
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
                onPressed: _isSaving ? null : _saveChanges,
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
                    : const Text(
                        'Save changes',
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
    final isSelected = _status == value;
    final color = _statusColor(value);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _status = value),
      selectedColor: color.withOpacity(0.15),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey[700],
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: isSelected ? color : Colors.grey[300]!),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} '
        'at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
