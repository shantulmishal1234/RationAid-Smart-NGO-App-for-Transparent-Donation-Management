import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/services/funding_service.dart';
import 'package:ration_aid/services/notification_service.dart';

class DonationDetailScreen extends StatefulWidget {
  final String donationId;
  // initialData kept for backward compatibility but optional
  final Map<String, dynamic>? initialData;

  const DonationDetailScreen({
    super.key,
    required this.donationId,
    this.initialData,
  });

  @override
  State<DonationDetailScreen> createState() => _DonationDetailScreenState();
}

class _DonationDetailScreenState extends State<DonationDetailScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _remarksController = TextEditingController(); // For rejection reason
  bool _isProcessing = false;

  User? get _currentUser => _auth.currentUser;

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _openProof(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open proof document')),
        );
      }
    }
  }

  // Action: Verify Donation
  Future<void> _verifyDonation(Donation donation) async {
    final isInKind = donation.donationType == DonationType.inKind;
    final declaredValueController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Donation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will mark the donation as verified and update funding calculations. This action cannot be undone.',
            ),
            if (isInKind) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '📦 In-Kind Donation',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Optionally enter the monetary equivalent of the donated items. This will count toward the family\'s funding progress.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: declaredValueController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Declared Value (PKR)',
                  hintText: 'e.g. 5000',
                  prefixText: 'PKR ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Verify'),
          ),
        ],
      ),
    );

    declaredValueController.dispose();
    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      // If admin entered a declared value for In-Kind, save it first
      final declaredValue = double.tryParse(
        declaredValueController.text.trim(),
      );
      if (isInKind && declaredValue != null && declaredValue > 0) {
        await _firestore.collection('donations').doc(donation.id).update({
          'amount': declaredValue,
          'declaredValue': declaredValue,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // FIX Bug#3: Route through FundingService.verifyDonation so that:
      // 1. Status is updated properly with history
      // 2. In-Kind donations call _processInKindDonation (decrement family needs)
      // 3. recalculateFamilyFunding is triggered with correct In-Kind type check
      await FundingService.verifyDonation(donation.id);

      // Also add an audit log entry from admin context
      final user = _currentUser;
      await _firestore.collection('donations').doc(donation.id).update({
        'decisionByUid': user?.uid,
        'decisionByName': user?.displayName ?? user?.email ?? 'Unknown admin',
        'decisionByEmail': user?.email,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notify donor
      await NotificationService.sendToUser(
        userId: donation.donorId,
        title: 'Donation Verified! ✅',
        body: 'Your donation has been verified. Thank you for your support!',
        data: {
          'type': 'donation_update',
          'donationId': donation.id,
          'status': 'verified',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isInKind && declaredValue != null && declaredValue > 0
                  ? '✅ In-Kind donation verified (PKR ${declaredValue.toStringAsFixed(0)} credited to funding)'
                  : 'Donation verified successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Action: Reject Donation
  Future<void> _rejectDonation(Donation donation) async {
    _remarksController.clear();
    final remark = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Donation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please provide a reason for rejection. This will be visible to the donor.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _remarksController,
              decoration: const InputDecoration(
                hintText: 'Rejection reason...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_remarksController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reason is required')),
                );
                return;
              }
              Navigator.pop(context, _remarksController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject Donation'),
          ),
        ],
      ),
    );

    if (remark == null) return;

    setState(() => _isProcessing = true);
    try {
      // 1. Update Donation Status
      await _updateStatus(
        donation: donation,
        newStatus: DonationStatus.rejected,
        remarks: remark,
        rejectionReason: remark,
      );

      // 2. Notify Donor
      await NotificationService.sendToUser(
        userId: donation.donorId,
        title: 'Donation Update',
        body: 'Your donation was rejected. Reason: $remark',
        data: {
          'type': 'donation_update',
          'donationId': donation.id,
          'status': 'rejected',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Donation rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Action: Start Verification (Pending -> Under Verification)
  Future<void> _startVerification(Donation donation) async {
    setState(() => _isProcessing = true);
    try {
      await _updateStatus(
        donation: donation,
        newStatus: DonationStatus.underVerification,
        remarks: 'Verification started by admin',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification started'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting verification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Backend Update Logic
  Future<void> _updateStatus({
    required Donation donation,
    required DonationStatus newStatus,
    required String remarks,
    String? rejectionReason,
  }) async {
    final user = _currentUser;
    final ref = FirebaseFirestore.instance
        .collection('donations')
        .doc(donation.id);

    final updateData = {
      'status': newStatus.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
      'decisionByUid': user?.uid,
      'decisionByName': user?.displayName ?? user?.email ?? 'Unknown admin',
      'decisionByEmail': user?.email,
      'verifications': FieldValue.arrayUnion([
        {
          'status': newStatus.toFirestore(),
          'remarks': remarks,
          'verifiedAt': Timestamp.now(),
          'adminUid': user?.uid,
          'adminName': user?.displayName ?? user?.email ?? 'Unknown admin',
        },
      ]),
    };

    if (rejectionReason != null) {
      updateData['rejectionReason'] = rejectionReason;
    }

    await ref.update(updateData);

    // Audit Log
    await AuditService.logDonationAction(
      action: 'Donation marked as ${newStatus.displayName}',
      donationId: donation.id,
      donorName: donation.donorName ?? 'Unknown',
      amount: donation.amount ?? 0,
      details: remarks,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Donation Details',
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('donations')
            .doc(widget.donationId)
            .snapshots(),
        builder: (context, snapshot) {
          // Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error/Empty State
          if (snapshot.hasError ||
              !snapshot.hasData ||
              !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('Donation not found or error loading'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ],
              ),
            );
          }

          // Parse Donation
          final donation = Donation.fromFirestore(snapshot.data!);
          return _buildContent(donation);
        },
      ),
    );
  }

  Widget _buildContent(Donation donation) {
    final theme = Theme.of(context);
    final isPending = donation.status == DonationStatus.pending;
    final isUnderVerification =
        donation.status == DonationStatus.underVerification;
    final showActions = isPending || isUnderVerification;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Profile & Status
                _buildHeader(donation),
                const SizedBox(height: 32),

                // Beneficiary
                _sectionHeader('Beneficiary'),
                const SizedBox(height: 12),
                FrostedPanel(child: _buildBeneficiaryInfo(donation)),
                const SizedBox(height: 32),

                // In-Kind Items (if applicable)
                if (donation.donationType == DonationType.inKind &&
                    donation.items != null) ...[
                  _sectionHeader('Donated Items'),
                  const SizedBox(height: 12),
                  _buildInKindItemsSection(donation.items!),
                  const SizedBox(height: 32),
                ],

                // Timestamps
                _sectionHeader('Timeline'),
                const SizedBox(height: 12),
                FrostedPanel(child: _buildTimeline(donation)),
                const SizedBox(height: 32),

                // Payment Proof
                _sectionHeader('Proof of Donation'),
                const SizedBox(height: 12),
                _buildProofSection(donation),
                const SizedBox(height: 32),

                // Verification History - Always show section
                _sectionHeader('History & Logs'),
                const SizedBox(height: 12),
                FrostedPanel(child: _buildHistoryList(donation)),
                const SizedBox(height: 32),

                // Rejection Reason Display (if rejected)
                if (donation.status == DonationStatus.rejected &&
                    donation.rejectionReason != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rejection Reason',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          donation.rejectionReason!,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),

        // Action Bar (Only visible if action is needed)
        if (showActions)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Reject Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _rejectDonation(donation),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Action Button (Start Verification OR Verify)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () {
                              if (isPending) {
                                _startVerification(donation);
                              } else {
                                _verifyDonation(donation);
                              }
                            },
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(isPending ? Icons.play_arrow : Icons.check),
                      label: Text(
                        _isProcessing
                            ? 'Saving...'
                            : (isPending ? 'Start Verification' : 'Verify'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPending ? Colors.blue : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // --- UI Helper Methods ---

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildHeader(Donation donation) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(donation.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          child: Text(
            (donation.donorName?.isNotEmpty == true)
                ? donation.donorName![0].toUpperCase()
                : '?',
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
                donation.donorName ?? 'Unknown Donor',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                donation.donorEmail ?? 'No Email',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              if (donation.amount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PKR ${donation.amount!.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Status Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: statusColor),
              const SizedBox(width: 6),
              Text(
                donation.status.displayName.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBeneficiaryInfo(Donation donation) {
    if (donation.familyId == 'general_relief_fund') {
      return _infoRow('Donation For', 'General Relief Fund');
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('families')
          .doc(donation.familyId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _infoRow(
            'Donation For',
            'Unknown Family (${donation.familyId})',
          );
        }

        // Use Family model to get consistent data (including fallbacks)
        final family = Family.fromFirestore(snapshot.data!);

        return Column(
          children: [
            _infoRow('Family', 'Family in ${family.area}, ${family.city}'),
            const SizedBox(height: 8),
            _infoRow(
              'Members',
              '${family.numberOfAdults} Adults, ${family.numberOfChildren} Children'
                  '${family.familySize > 0 ? " (Total: ${family.familySize})" : ""}',
            ),
          ],
        );
      },
    );
  }

  Widget _buildInKindItemsSection(Map<String, int> items) {
    final theme = Theme.of(context);
    return FrostedPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: items.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: Colors.purple.shade300),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  'x${entry.value}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeline(Donation donation) {
    return Column(
      children: [
        _infoRow('Created', _formatDate(donation.createdAt)),
        const SizedBox(height: 8),
        _infoRow('Last Update', _formatDate(donation.updatedAt)),
      ],
    );
  }

  Widget _buildProofSection(Donation donation) {
    final theme = Theme.of(context);
    final hasProof = donation.paymentProofUrl?.isNotEmpty == true;

    return InkWell(
      onTap: hasProof ? () => _openProof(donation.paymentProofUrl) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.image,
              color: hasProof ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                hasProof ? 'View Payment Proof' : 'No Proof Uploaded',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: hasProof ? theme.colorScheme.onSurface : Colors.grey,
                ),
              ),
            ),
            if (hasProof) const Icon(Icons.open_in_new, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(Donation donation) {
    // Reverse to show latest first
    final history = donation.statusHistory.reversed.toList();

    if (history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text("No history logs available."),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = history[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.history, size: 16, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.status.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    entry.note,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    _formatDate(entry.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(DonationStatus status) {
    switch (status) {
      case DonationStatus.verified:
        return Colors.green;
      case DonationStatus.rejected:
        return Colors.red;
      case DonationStatus.underVerification:
        return Colors.blue;
      case DonationStatus.pending:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
