import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/funding_service.dart';
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

  // Removed explicit volunteer assignment variables as Distributors utilize a pooling system

  @override
  void initState() {
    super.initState();
    _familyData = widget.initialData;
    _loadFamilyModel(); // Load Family model
    _status = _familyData['status'] ?? 'pending';
    _remarksController.text = _familyData['remarks'] ?? '';
    _documents = List<dynamic>.from(_familyData['documents'] ?? []);
    _assistanceNeeds = List<String>.from(_familyData['assistanceNeeds'] ?? []);
    // Removed _loadDistributors() call
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

  // Removed _loadDistributors()

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

  // Removed _assignVolunteerFromDropdown()

  // ─── Pool Management ────────────────────────────────────────────────────────

  Widget _buildPoolManagementSection(BuildContext context) {
    final theme = Theme.of(context);
    final family = _family;
    if (family == null) return const SizedBox.shrink();

    final surplus = family.surplusAmount;
    final remaining = family.remainingAmount;
    final isOverFunded = surplus > 0;
    final isUnderfunded = remaining > 0;

    if (!isOverFunded && !isUnderfunded) return const SizedBox.shrink();

    return FrostedPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: isOverFunded ? Colors.deepOrange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(
                'Pool Management',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (isOverFunded)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+ PKR ${surplus.toStringAsFixed(0)} Surplus',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isUnderfunded)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showGRFAllocationDialog(context, family),
                icon: const Icon(Icons.monetization_on, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Allocate from GRF (Gap: PKR ${remaining.toStringAsFixed(0)})',
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
              ),
            ),
          if (isUnderfunded && isOverFunded) const SizedBox(height: 8),
          if (isOverFunded)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showSurplusTransferDialog(context, family),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Transfer Surplus (PKR ${surplus.toStringAsFixed(0)})',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showGRFAllocationDialog(
    BuildContext context,
    Family family,
  ) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController(
      text: 'Allocated from General Relief Fund pool',
    );
    bool isProcessing = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Allocate from GRF Pool'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Transfer funds from the General Relief Fund to this family\'s funding pool.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Family Gap: PKR ${family.remainingAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (PKR)',
                  prefixText: 'PKR ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isProcessing
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid amount')),
                        );
                        return;
                      }
                      setDlgState(() => isProcessing = true);
                      try {
                        await FundingService.allocateFromGRF(
                          targetFamilyId: widget.familyId,
                          amount: amount,
                          adminNote: noteController.text.trim(),
                          adminUid: _currentUser?.uid,
                        );
                        if (context.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _loadFamilyModel();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ PKR ${amount.toStringAsFixed(0)} allocated from GRF',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isProcessing = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Allocate'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    noteController.dispose();
  }

  Future<void> _showSurplusTransferDialog(
    BuildContext context,
    Family family,
  ) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController(text: 'Surplus transfer');
    String? selectedTargetId;
    String selectedTargetName = '';
    bool isProcessing = false;

    // Load accepted families for the picker
    List<Map<String, String>> families = [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();
      families = snap.docs
          .where((d) => d.id != widget.familyId)
          .map(
            (d) => {
              'id': d.id,
              'name':
                  (d.data()['registeredName'] ??
                          d.data()['area'] ??
                          'Family ${d.id.substring(0, 6)}')
                      as String,
            },
          )
          .toList();
      // Add GRF as an option
      families.insert(0, {
        'id': 'general_relief_fund',
        'name': 'General Relief Fund',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load families: $e')));
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Transfer Surplus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Transfer the surplus amount to another family or back to GRF.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Available Surplus: PKR ${family.surplusAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedTargetId,
                hint: const Text('Select destination'),
                items: families
                    .map(
                      (f) => DropdownMenuItem(
                        value: f['id'],
                        child: Text(
                          f['name']!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setDlgState(() {
                    selectedTargetId = val;
                    selectedTargetName =
                        families.firstWhere((f) => f['id'] == val)['name'] ??
                        '';
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Transfer To',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (PKR)',
                  prefixText: 'PKR ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isProcessing
                  ? null
                  : () async {
                      if (selectedTargetId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a destination'),
                          ),
                        );
                        return;
                      }
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid amount')),
                        );
                        return;
                      }
                      setDlgState(() => isProcessing = true);
                      try {
                        await FundingService.transferSurplus(
                          fromFamilyId: widget.familyId,
                          toFamilyId: selectedTargetId!,
                          amount: amount,
                          adminNote: noteController.text.trim(),
                          adminUid: _currentUser?.uid,
                        );
                        if (context.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _loadFamilyModel();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ PKR ${amount.toStringAsFixed(0)} transferred to $selectedTargetName',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isProcessing = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Transfer'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    noteController.dispose();
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
            // Removed volunteer assignments loading
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isSmall = constraints.maxWidth < 400;
                        final crossAxisCount = isSmall ? 2 : 4;
                        final spacing = 12.0;
                        final itemWidth =
                            (constraints.maxWidth -
                                (spacing * (crossAxisCount - 1))) /
                            crossAxisCount;

                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            SizedBox(
                              width: itemWidth,
                              child: _buildCompactInfoItem(
                                'Adults',
                                (_familyData['adults'] ?? 0).toString(),
                                Icons.person,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _buildCompactInfoItem(
                                'Children',
                                (_familyData['children'] ?? 0).toString(),
                                Icons.child_care,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _buildCompactInfoItem(
                                'Family Size',
                                (_familyData['familySize'] ?? 0).toString(),
                                Icons.groups,
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: _buildCompactInfoItem(
                                'Income',
                                _familyData['monthlyIncome'] != null
                                    ? _formatCurrency(
                                        _familyData['monthlyIncome'],
                                      )
                                    : '-',
                                Icons.attach_money,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_family != null && _family!.targetAmount > 0) ...[
                    _buildSectionHeader(context, 'Funding Progress'),
                    const SizedBox(height: 16),
                    FrostedPanel(child: _buildFundingSection(context)),
                    const SizedBox(height: 16),
                    // Pool Management Actions
                    _buildPoolManagementSection(context),
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

                  // Removed volunteer section UI

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
          backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
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
                softWrap: true,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_familyData['cnic'] != null &&
                  _familyData['cnic'].toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'CNIC: ${_familyData['cnic']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                'ID: ...${widget.familyId.substring(widget.familyId.length - 6)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontFamily: 'Monospace',
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor(_status).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _statusColor(_status).withValues(alpha: 0.3),
            ),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final isVerySmall = constraints.maxWidth < 250;
            final spacing = 12.0;
            final itemWidth = isVerySmall
                ? constraints.maxWidth
                : (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _buildCompactInfoItem(
                    'Phone',
                    _familyData['phone'] ?? '-',
                    Icons.phone,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _buildCompactInfoItem(
                    'City',
                    _familyData['city'] ?? '-',
                    Icons.location_city,
                  ),
                ),
              ],
            );
          },
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
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
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
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _familyData['address'] ?? '-',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.8),
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
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  // Removed _buildVolunteerSection as volunteers now use pooling.

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
                        ? Colors.red.withValues(alpha: 0.1)
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
      selectedColor: color.withValues(alpha: 0.15),
      backgroundColor: isDark ? theme.cardColor : Colors.white,
      labelStyle: TextStyle(
        color: isSelected
            ? color
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                        : theme.dividerColor.withValues(alpha: 0.5),
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
                        : theme.dividerColor.withValues(alpha: 0.5),
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
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        when,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'By: $adminName',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
    final surplus = _family!.surplusAmount;
    final percent = ((raised + surplus) / target).clamp(0.0, 1.0);
    final fullyFunded = (raised + surplus) >= target;
    final isOverFunded = surplus > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Raised Amount',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                            color: Colors.green.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Goal Amount',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
            color: isOverFunded
                ? Colors.deepOrange
                : (fullyFunded ? Colors.green : Colors.blue),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${(percent * 100).toInt()}% Funded',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isOverFunded
                        ? Colors.deepOrange
                        : (fullyFunded
                              ? Colors.green
                              : theme.colorScheme.primary),
                  ),
                ),
                if (isOverFunded) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+${surplus.toInt()} Surplus',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (fullyFunded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isOverFunded ? Colors.deepOrange : Colors.green)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isOverFunded ? 'OVER-FUNDED' : 'GOAL REACHED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isOverFunded ? Colors.deepOrange : Colors.green,
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
