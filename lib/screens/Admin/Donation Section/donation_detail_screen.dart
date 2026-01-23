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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Donation Details',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.dividerColor.withOpacity(0.2),
            height: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Identity Header
                  _buildHeader(d),
                  const SizedBox(height: 32),

                  // Timestamps
                  _buildSectionHeader('Timestamps'),
                  const SizedBox(height: 12),
                  _buildTimestamps(
                    createdAt,
                    updatedAt,
                    decisionByName,
                    decisionByEmail,
                  ),
                  const SizedBox(height: 32),

                  // Payment Proof
                  _buildSectionHeader('Payment Proof'),
                  const SizedBox(height: 12),
                  _buildProofSection(d),
                  const SizedBox(height: 32),

                  // Verification Decision
                  _buildSectionHeader('Verification Decision'),
                  const SizedBox(height: 12),
                  _buildDecisionSection(isDark),
                  const SizedBox(height: 32),

                  // History
                  if (verifications.isNotEmpty) ...[
                    _buildSectionHeader('Verification History'),
                    const SizedBox(height: 12),
                    _buildHistoryList(verifications),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> d) {
    final theme = Theme.of(context);
    final donorName = d['donorName'] ?? 'Unknown donor';
    final amount = (d['amount'] ?? 0).toDouble();
    final currency = d['currency'] ?? 'PKR';
    final method = d['method'] ?? 'cash';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          child: Text(
            donorName.isNotEmpty ? donorName[0].toUpperCase() : '?',
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
                donorName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                d['donorEmail'] ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
                      '$amount $currency',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'via $method',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
            _statusLabel(_status).toUpperCase(),
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

  Widget _buildTimestamps(
    Timestamp? createdAt,
    Timestamp? updatedAt,
    String? decisionByName,
    String? decisionByEmail,
  ) {
    return Column(
      children: [
        _infoRow(
          'Created',
          createdAt != null
              ? createdAt.toDate().toString().split('.').first
              : '-',
        ),
        const SizedBox(height: 8),
        _infoRow(
          'Last updated',
          updatedAt != null
              ? updatedAt.toDate().toString().split('.').first
              : '-',
        ),
        if (decisionByName != null || decisionByEmail != null) ...[
          const SizedBox(height: 8),
          _infoRow('Verified by', decisionByName ?? decisionByEmail ?? '-'),
        ],
      ],
    );
  }

  Widget _buildProofSection(Map<String, dynamic> d) {
    final theme = Theme.of(context);
    final hasProof = (d['proofUrl'] as String?)?.isNotEmpty == true;

    return InkWell(
      onTap: hasProof ? _openProof : null,
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasProof
                    ? theme.colorScheme.primary.withOpacity(0.1)
                    : theme.dividerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.receipt_long,
                size: 20,
                color: hasProof
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasProof ? 'Proof Document' : 'No Proof Uploaded',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (hasProof)
                    Text(
                      'Tap to view attachment',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            if (hasProof)
              Icon(
                Icons.open_in_new,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecisionSection(bool isDark) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusChip('pending', 'Pending'),
            _statusChip('under_review', 'Under Review'),
            _statusChip('verified', 'Verified'),
            _statusChip('rejected', 'Rejected'),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _remarksController,
          maxLines: 3,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Add remarks or notes...',
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
              fontSize: 14,
            ),
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surface
                : theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor.withOpacity(0.8),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.dividerColor.withOpacity(0.8),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> verifications) {
    final theme = Theme.of(context);
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: verifications.length,
      itemBuilder: (context, index) {
        final v = verifications[index];
        final status = (v['status'] ?? 'pending') as String;
        final remarks = (v['remarks'] ?? '') as String;
        final adminName = (v['adminName'] ?? 'Unknown') as String;
        final ts = v['verifiedAt'] as Timestamp?;
        final when = ts != null ? ts.toDate().toString().split('.').first : '-';
        final isLast = index == verifications.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _statusColor(status),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _statusColor(status),
                          width: 2,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: theme.dividerColor.withOpacity(0.5),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.4,
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
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
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
      },
    );
  }

  Widget _sectionHeader(String title) {
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

  Widget _buildSectionHeader(String title) {
    return _sectionHeader(title);
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
        return 'Under Review';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  Widget _statusChip(String value, String label) {
    final theme = Theme.of(context);
    final isSelected = _status == value;
    final color = _statusColor(value);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _status = value),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected
            ? color
            : theme.colorScheme.onSurface.withOpacity(0.7),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? color : theme.dividerColor.withOpacity(0.8),
        ),
      ),
      backgroundColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }
}
