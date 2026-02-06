import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/screens/Admin/widgets/family_voting_widget.dart';
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
  Family? _family; // Family model object
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
    _loadFamilyModel(); // Load Family model
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

  Future<void> _loadFamilyModel() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _family = Family.fromFirestore(doc);
        });
      }
    } catch (e) {
      // Silent fail, will use existing _familyData
    }
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
      if (!mounted) return;
      setState(() {
        _distributors = [
          {'uid': 'none', 'name': 'None'},
          ...list,
        ];
        if (_assignedVolunteerUid != null &&
            list.any((e) => e['uid'] == _assignedVolunteerUid)) {
          _selectedDistributorUid = _assignedVolunteerUid;
        } else {
          _selectedDistributorUid = 'none';
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

      setState(() {
        _familyData['status'] = _status;
        _familyData['remarks'] = _remarksController.text.trim();
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
      final familyName = _familyData['name'] ?? 'Unnamed family';

      if (uid == 'none') {
        // Unassign volunteer
        await FirebaseFirestore.instance
            .collection('families')
            .doc(widget.familyId)
            .update({
              'assignedVolunteerUid': FieldValue.delete(),
              'assignedVolunteerName': FieldValue.delete(),
            });

        await AuditService.logFamilyAction(
          action: 'Volunteer unassigned',
          familyId: widget.familyId,
          familyName: familyName,
          details: 'Volunteer removed from family',
        );

        if (!mounted) return;
        setState(() {
          _assignedVolunteerUid = null;
          _assignedVolunteerName = null;
          _selectedDistributorUid = 'none';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Volunteer unassigned successfully'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

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

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .update({'assignedVolunteerUid': uid, 'assignedVolunteerName': name});

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

  Future<void> _navigateToEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditFamilyScreen(familyId: widget.familyId),
      ),
    );

    if (result == true) {
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
    final decisions = List<Map<String, dynamic>>.from(
      _familyData['decisions'] ?? [],
    );

    return AdminScaffold(
      title: 'Family Details',
      actions: [
        IconButton(
          icon: Icon(Icons.edit, color: theme.colorScheme.primary),
          onPressed: _isLoading ? null : _navigateToEdit,
          tooltip: 'Edit family',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 32),

                  _buildSectionHeader(context, 'Demographics & Income'),
                  const SizedBox(height: 16),
                  FrostedPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildCompactInfoItem(
                            'Adults',
                            (_familyData['adults'] ?? 0).toString(),
                            Icons.person,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCompactInfoItem(
                            'Children',
                            (_familyData['children'] ?? 0).toString(),
                            Icons.child_care,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCompactInfoItem(
                            'Family Size',
                            (_familyData['familySize'] ?? 0).toString(),
                            Icons.groups,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCompactInfoItem(
                            'Income',
                            _familyData['monthlyIncome'] != null
                                ? _formatCurrency(_familyData['monthlyIncome'])
                                : '-',
                            Icons.attach_money,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_family != null && _family!.targetAmount > 0) ...[
                    _buildSectionHeader(context, 'Funding Progress'),
                    const SizedBox(height: 16),
                    FrostedPanel(child: _buildFundingSection(context)),
                    const SizedBox(height: 32),
                  ],

                  _buildSectionHeader(context, 'Contact & Location'),
                  const SizedBox(height: 16),
                  FrostedPanel(child: _buildContactInfo(context)),
                  const SizedBox(height: 32),

                  _buildSectionHeader(context, 'Assistance Needs'),
                  const SizedBox(height: 16),
                  FrostedPanel(child: _buildAssistanceChips(context)),
                  const SizedBox(height: 32),

                  _buildSectionHeader(context, 'Assigned Volunteer'),
                  const SizedBox(height: 16),
                  FrostedPanel(child: _buildVolunteerSection(context)),
                  const SizedBox(height: 32),

                  // Show voting UI for pending_review status, otherwise show decision section
                  if (_status == 'pending_review' && _family != null) ...[
                    _buildSectionHeader(context, 'Family Review - Voting'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: FamilyVotingWidget(
                        family: _family!,
                        onVoteSubmitted: () {
                          // Reload family data after vote
                          _loadFamilyModel();
                        },
                      ),
                    ),
                  ] else ...[
                    _buildSectionHeader(context, 'Verification Decision'),
                    const SizedBox(height: 16),
                    FrostedPanel(child: _buildDecisionSection(context)),
                  ],
                  const SizedBox(height: 32),

                  if (_documents.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Documents'),
                    const SizedBox(height: 16),
                    FrostedPanel(child: _buildDocumentsList(context)),
                    const SizedBox(height: 32),
                  ],

                  if (decisions.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Decision History'),
                    const SizedBox(height: 16),
                    FrostedPanel(
                      child: _buildHistorySection(context, decisions),
                    ),
                    const SizedBox(height: 32),
                  ],

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
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          child: Text(
            (_familyData['name'] as String? ?? '?')[0].toUpperCase(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _familyData['name'] ?? 'Unknown Family',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (_familyData['cnic'] != null &&
                  _familyData['cnic'].toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'CNIC: ${_familyData['cnic']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                'ID: ...${widget.familyId.substring(widget.familyId.length - 6)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                  fontFamily: 'Monospace',
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(_status).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _statusColor(_status).withOpacity(0.3)),
          ),
          child: Text(
            _status.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _statusColor(_status),
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
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

  Widget _buildContactInfo(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCompactInfoItem(
                'Phone',
                _familyData['phone'] ?? '-',
                Icons.phone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCompactInfoItem(
                'City',
                _familyData['city'] ?? '-',
                Icons.location_city,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildCompactInfoItem('Area', _familyData['area'] ?? '-', Icons.map),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.5),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _familyData['address'] ?? '-',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssistanceChips(BuildContext context) {
    final theme = Theme.of(context);
    if (_assistanceNeeds.isEmpty) {
      return Text(
        'No specific needs listed.',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Wrap(
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
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  Widget _buildVolunteerSection(BuildContext context) {
    final theme = Theme.of(context);
    final canAssign = _status == 'accepted';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _assignedVolunteerName != null
              ? 'Currently assigned to: $_assignedVolunteerName'
              : 'No volunteer assigned yet.',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withOpacity(0.7),
            fontStyle: _assignedVolunteerName == null ? FontStyle.italic : null,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingDistributors)
          const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_distributors.isEmpty)
          const Text(
            'No distributor accounts found in HRM.',
            style: TextStyle(fontSize: 12, color: Colors.red),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedDistributorUid,
                      items: _distributors.map((d) {
                        return DropdownMenuItem<String>(
                          value: d['uid'],
                          child: Text(
                            d['name'] ?? 'Unknown',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: canAssign
                          ? (value) {
                              setState(() => _selectedDistributorUid = value);
                            }
                          : null,
                      dropdownColor: theme.cardColor,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Select volunteer',
                        labelStyle: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.dividerColor),
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
                    onPressed: canAssign ? _assignVolunteerFromDropdown : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: theme.disabledColor.withOpacity(
                        0.1,
                      ),
                      disabledForegroundColor: theme.disabledColor,
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
              if (!canAssign) ...[
                const SizedBox(height: 8),
                Text(
                  'Volunteer assignment is only available for accepted households.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildDecisionSection(BuildContext context) {
    // Determine which status chips to show based on current status
    List<Map<String, String>> availableStatuses = [];

    if (_status == 'pending' || _status == 'pending_review') {
      // For pending families, show all options
      availableStatuses = [
        {'value': 'pending', 'label': 'Pending'},
        {'value': 'accepted', 'label': 'Accept'},
        {'value': 'rejected', 'label': 'Reject'},
        {'value': 'discarded', 'label': 'Discard'},
      ];
    } else if (_status == 'accepted') {
      // For accepted families, only show discard option
      availableStatuses = [
        {'value': 'accepted', 'label': 'Accepted'},
        {'value': 'discarded', 'label': 'Discard'},
      ];
    } else if (_status == 'rejected') {
      // For rejected families, only show discard option
      availableStatuses = [
        {'value': 'rejected', 'label': 'Rejected'},
        {'value': 'discarded', 'label': 'Discard'},
      ];
    } else if (_status == 'discarded') {
      // For discarded families, show read-only
      availableStatuses = [
        {'value': 'discarded', 'label': 'Discarded'},
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableStatuses.map((statusData) {
            return _statusChip(statusData['value']!, statusData['label']!);
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          enabled: _status != 'discarded', // Disable for discarded
          decoration: InputDecoration(
            labelText: 'Remarks / Reason',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isUpdatingStatus || _status == 'discarded'
                ? null
                : _updateStatus,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isUpdatingStatus
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Update Status',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsList(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _documents.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final doc = _documents[index] as Map;
        final url = doc['url'] as String? ?? '';
        final type = doc['type'] as String? ?? 'Document';
        final isPdf =
            type.toLowerCase().contains('pdf') ||
            url.toLowerCase().endsWith('.pdf');

        return InkWell(
          onTap: url.isEmpty ? null : () => _openDocument(url),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPdf
                        ? Colors.red.withOpacity(0.1)
                        : theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                    size: 20,
                    color: isPdf ? Colors.red : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (url.isNotEmpty)
                        Text(
                          'Tap to view',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    List<Map<String, dynamic>> decisions,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildTimelineItem(
          decisions.last,
          theme,
          isFirst: true,
          isLast: decisions.length == 1,
        ),
        if (decisions.length > 1)
          Theme(
            data: theme.copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'View past decisions (${decisions.length - 1})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              trailing: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: decisions.length - 1,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    final previousDecisions = decisions.reversed
                        .skip(1)
                        .toList();
                    final isLastItem = index == previousDecisions.length - 1;
                    return _buildTimelineItem(
                      previousDecisions[index],
                      theme,
                      isFirst: false,
                      isLast: isLastItem,
                    );
                  },
                ),
              ],
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

  Widget _buildCompactInfoItem(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary.withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    Map<String, dynamic> decision,
    ThemeData theme, {
    required bool isFirst,
    required bool isLast,
  }) {
    final status = (decision['status'] ?? 'pending') as String;
    final remarks = (decision['remarks'] ?? '') as String;
    final adminName = (decision['adminName'] ?? 'Unknown') as String;
    final ts = decision['decidedAt'] as Timestamp?;
    final when = ts != null ? _formatDate(ts.toDate()) : '-';
    final color = _statusColor(status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Expanded(
                  flex: isFirst ? 0 : 1,
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : theme.dividerColor.withOpacity(0.5),
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isFirst ? color : theme.scaffoldBackgroundColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFirst ? color : theme.dividerColor,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : theme.dividerColor.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isFirst
                              ? color
                              : theme.colorScheme.onSurface.withOpacity(0.7),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        when,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  if (remarks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      remarks,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'By: $adminName',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundingSection(BuildContext context) {
    if (_family == null) return const SizedBox();

    final theme = Theme.of(context);
    final target = _family!.targetAmount;
    final raised = _family!.raisedAmount;
    final percent = (raised / target).clamp(0.0, 1.0);
    final fullyFunded = raised >= target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Raised Amount',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: theme.textTheme.bodyLarge?.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                    children: [
                      TextSpan(text: raised.toStringAsFixed(0)),
                      TextSpan(
                        text: ' PKR',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Goal Amount',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: theme.textTheme.bodyLarge?.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    children: [
                      TextSpan(text: target.toStringAsFixed(0)),
                      TextSpan(
                        text: ' PKR',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 12,
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[200],
            color: fullyFunded ? Colors.green : Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(percent * 100).toInt()}% Funded',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: fullyFunded ? Colors.green : theme.colorScheme.primary,
              ),
            ),
            if (fullyFunded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'GOAL REACHED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              )
            else
              Text(
                'Gap: ${(target - raised).toStringAsFixed(0)} PKR',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange[700],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
