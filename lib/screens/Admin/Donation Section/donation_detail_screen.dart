import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class DonationDetailScreen extends StatefulWidget {
  final String donationId;
  final Map<String, dynamic> initialData;

  const DonationDetailScreen({
    super.key,
    required this.donationId,
    required this.initialData,
  });

  @override
  State<DonationDetailScreen> createState() => _DonationDetailScreenState();
}

class _DonationDetailScreenState extends State<DonationDetailScreen> {
  final _auth = FirebaseAuth.instance;

  User? get _currentUser => _auth.currentUser;

  late String _status;
  final _remarksController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialData['status'] ?? 'pending';
    _remarksController.text = widget.initialData['remarks'] ?? '';
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _openProof() async {
    final url = widget.initialData['proofUrl'] as String?;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No proof document uploaded'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open proof'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final user = _currentUser;
      final d = widget.initialData;
      final donorName = d['donorName'] ?? 'Unknown donor';
      final amount = (d['amount'] ?? 0).toDouble();

      final ref = FirebaseFirestore.instance
          .collection('donations')
          .doc(widget.donationId);

      await ref.update({
        'status': _status,
        'remarks': _remarksController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'decisionByUid': user?.uid,
        'decisionByName': user?.displayName ?? user?.email ?? 'Unknown admin',
        'decisionByEmail': user?.email,
        'verifications': FieldValue.arrayUnion([
          {
            'status': _status,
            'remarks': _remarksController.text.trim(),
            'verifiedAt': Timestamp.now(),
            'adminUid': user?.uid,
            'adminName': user?.displayName ?? user?.email ?? 'Unknown admin',
            'adminEmail': user?.email,
          },
        ]),
      });

      await AuditService.logDonationAction(
        action: 'Donation status updated to $_status',
        donationId: widget.donationId,
        donorName: donorName,
        amount: amount,
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
          content: Text('Failed to update donation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.initialData;
    final createdAt = d['createdAt'] as Timestamp?;
    final updatedAt = d['updatedAt'] as Timestamp?;
    final decisionByName = d['decisionByName'] as String?;
    final decisionByEmail = d['decisionByEmail'] as String?;
    final verifications = List<Map<String, dynamic>>.from(
      d['verifications'] ?? [],
    );

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Donation details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Donor header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primaryBlue.withOpacity(
                            0.08,
                          ),
                          child: const Icon(
                            Icons.volunteer_activism,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['donorName'] ?? 'Unknown donor',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                d['donorEmail'] ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(d['amount'] ?? 0).toDouble()} ${d['currency'] ?? 'PKR'} • ${d['method'] ?? 'cash'}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(_status).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(_status),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(_status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _sectionHeader('Timestamps'),
                    const SizedBox(height: 6),
                    _infoRow(
                      'Created',
                      createdAt != null
                          ? createdAt.toDate().toString().split('.').first
                          : '-',
                    ),
                    _infoRow(
                      'Last updated',
                      updatedAt != null
                          ? updatedAt.toDate().toString().split('.').first
                          : '-',
                    ),
                    if (decisionByName != null || decisionByEmail != null)
                      _infoRow(
                        'Verified by',
                        decisionByName ?? decisionByEmail ?? '-',
                      ),

                    const SizedBox(height: 18),
                    _sectionHeader('Status'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _statusChip('pending', 'Pending'),
                        _statusChip('under_review', 'Under review'),
                        _statusChip('verified', 'Verified'),
                        _statusChip('rejected', 'Rejected'),
                      ],
                    ),

                    const SizedBox(height: 18),
                    _sectionHeader('Remarks'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarksController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF9FBFF),
                        hintText: 'Notes about this donation...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primaryBlue,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
                    _sectionHeader('Verification history'),
                    const SizedBox(height: 8),
                    verifications.isEmpty
                        ? Text(
                            'No verification actions recorded yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: verifications.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 12),
                            itemBuilder: (context, index) {
                              final v = verifications[index];
                              final status =
                                  (v['status'] ?? 'pending') as String;
                              final remarks = (v['remarks'] ?? '') as String;
                              final adminName =
                                  (v['adminName'] ?? 'Unknown') as String;
                              final ts = v['verifiedAt'] as Timestamp?;
                              final when = ts != null
                                  ? ts.toDate().toString().split('.').first
                                  : '-';

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 26,
                                    alignment: Alignment.topCenter,
                                    child: Icon(
                                      Icons.verified,
                                      size: 16,
                                      color: _statusColor(status),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_statusLabel(status)} • $when',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        if (remarks.isNotEmpty)
                                          Text(
                                            remarks,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        Text(
                                          'By: $adminName',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                    const SizedBox(height: 18),
                    _sectionHeader('Payment proof'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FBFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 20,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (d['proofUrl'] as String?)?.isNotEmpty == true
                                  ? 'Proof document uploaded'
                                  : 'No proof uploaded',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _openProof,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sticky bottom button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
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

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'verified':
        return Colors.green;
      case 'under_review':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'verified':
        return 'Verified';
      case 'under_review':
        return 'Under review';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  Widget _statusChip(String value, String label) {
    final isSelected = _status == value;
    final color = _statusColor(value);

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _status = value),
      selectedColor: color.withOpacity(0.18),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey[700],
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: isSelected ? color : Colors.grey[300]!),
    );
  }
}
