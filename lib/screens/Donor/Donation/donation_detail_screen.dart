import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/services/receipt_service.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';

/// Donation Detail Screen - View donation with status timeline
/// Supports edit (for drafts), re-upload (for rejected), and delete (for drafts)
class DonationDetailScreen extends StatefulWidget {
  final String donationId;

  const DonationDetailScreen({super.key, required this.donationId});

  @override
  State<DonationDetailScreen> createState() => _DonationDetailScreenState();
}

class _DonationDetailScreenState extends State<DonationDetailScreen> {
  final DonationService _donationService = DonationService();
  bool _isReuploading = false;
  bool _isGeneratingReceipt = false;

  Future<void> _downloadReceipt(Donation donation) async {
    setState(() => _isGeneratingReceipt = true);
    try {
      await ReceiptService.generateReceipt(donation);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate receipt: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingReceipt = false);
      }
    }
  }

  Future<void> _deleteDonation(Donation donation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Donation?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _donationService.deleteDonation(widget.donationId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Donation deleted')));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _reuploadPaymentProof() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image == null) return;

      setState(() => _isReuploading = true);

      final imageFile = File(image.path);
      final imageUrl = await CloudinaryService.uploadImage(imageFile);
      if (imageUrl == null) throw Exception('Upload failed');
      await _donationService.reuploadPaymentProof(widget.donationId, imageUrl);

      setState(() => _isReuploading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment proof re-uploaded successfully!'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isReuploading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DonorScaffold(
      title: 'Donation Details',
      showBackButton: true,
      body: FutureBuilder<Donation?>(
        future: _donationService.getDonationById(widget.donationId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final donation = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Timeline
                _StatusTimelineCard(donation: donation),
                const SizedBox(height: 16),

                // Donation Information
                _DonationInfoCard(donation: donation),
                const SizedBox(height: 16),

                // Family Information
                _FamilyInfoCard(familyId: donation.familyId),
                const SizedBox(height: 16),

                // Payment Proof (if cash)
                if (donation.donationType == DonationType.cash &&
                    donation.paymentProofUrl != null)
                  _PaymentProofCard(imageUrl: donation.paymentProofUrl!),

                // Rejection Reason
                if (donation.status == DonationStatus.rejected &&
                    donation.rejectionReason != null) ...[
                  const SizedBox(height: 16),
                  _RejectionReasonCard(reason: donation.rejectionReason!),
                ],

                // Action Buttons
                const SizedBox(height: 24),
                _buildActionButtons(donation),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(Donation donation) {
    return Column(
      children: [
        // Download Receipt (for verified/completed donations)
        if (donation.status.index >= DonationStatus.verified.index)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGeneratingReceipt
                  ? null
                  : () => _downloadReceipt(donation),
              icon: _isGeneratingReceipt
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.receipt_long),
              label: Text(
                _isGeneratingReceipt ? 'Generating...' : 'Download Receipt',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        // Re-upload button (for rejected)
        if (donation.canReupload)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isReuploading ? null : _reuploadPaymentProof,
              icon: _isReuploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: _isReuploading
                  ? const Text('Uploading...')
                  : const Text('Re-upload Payment Proof'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.donorGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        // Edit button (for drafts/pending)
        if (donation.isEditable) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // Navigate to create donation screen with existing donation
                Navigator.pushNamed(
                  context,
                  '/create-donation',
                  arguments: donation, // Pass donation for editing
                ).then((_) {
                  // Refresh the screen after edit
                  setState(() {});
                });
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Donation'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.donorGreen,
                side: const BorderSide(color: AppColors.donorGreen),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],

        // Delete button (for drafts only)
        if (donation.isDeletable) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteDonation(donation),
              icon: const Icon(Icons.delete),
              label: const Text('Delete Draft'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Status Timeline Card Widget
class _StatusTimelineCard extends StatelessWidget {
  final Donation donation;

  const _StatusTimelineCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Donation Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            _buildTimelineItem(
              context,
              'Draft',
              donation.status.index >= DonationStatus.draft.index,
              isActive: donation.status == DonationStatus.draft,
            ),
            _buildTimelineItem(
              context,
              'Under Verification',
              donation.status.index >= DonationStatus.underVerification.index,
              isActive: donation.status == DonationStatus.underVerification,
            ),
            _buildTimelineItem(
              context,
              'Verified',
              donation.status.index >= DonationStatus.verified.index,
              isActive: donation.status == DonationStatus.verified,
            ),
            _buildTimelineItem(
              context,
              'In Process',
              donation.status.index >= DonationStatus.inProcess.index,
              isActive: donation.status == DonationStatus.inProcess,
            ),
            _buildTimelineItem(
              context,
              'Out for Delivery',
              donation.status.index >= DonationStatus.outForDelivery.index,
              isActive: donation.status == DonationStatus.outForDelivery,
            ),
            _buildTimelineItem(
              context,
              'Delivered',
              donation.status.index >= DonationStatus.delivered.index,
              isActive: donation.status == DonationStatus.delivered,
              isLast: true,
            ),
            // Show rejection branch if rejected
            if (donation.status == DonationStatus.rejected)
              _buildTimelineItem(
                context,
                'Rejected',
                true,
                isActive: true,
                isLast: true,
                color: DonorColors.statusRejected,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    String label,
    bool isCompleted, {
    bool isActive = false,
    bool isLast = false,
    Color? color,
  }) {
    final itemColor =
        color ??
        (isActive
            ? AppColors.donorGreen
            : (isCompleted
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[600]!
                        : Colors.grey[600]!)
                  : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]!
                        : Colors.grey[300]!)));

    final textColor = isActive
        ? itemColor
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted ? itemColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: itemColor, width: 2),
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted
                        ? itemColor
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[300]),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Donation Information Card
class _DonationInfoCard extends StatelessWidget {
  final Donation donation;

  const _DonationInfoCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Donation Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow('Type', donation.donationType.displayName),
            if (donation.amount != null)
              _InfoRow('Amount', 'Rs. ${donation.amount!.toStringAsFixed(0)}'),
            if (donation.items != null && donation.items!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Items:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              ...donation.items!.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '• ${entry.key}: ${entry.value}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                );
              }),
            ],
            _InfoRow('Anonymous', donation.anonymous ? 'Yes' : 'No'),
            if (donation.donationNote != null)
              _InfoRow('Note', donation.donationNote!),
            _InfoRow('Created', _formatDate(donation.createdAt)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Family Information Card
class _FamilyInfoCard extends StatelessWidget {
  final String familyId;

  const _FamilyInfoCard({required this.familyId});

  @override
  Widget build(BuildContext context) {
    final familyService = FamilyService();

    return FutureBuilder<Family?>(
      future: familyService.getFamilyById(familyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final family = snapshot.data!;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Family Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow('Area', family.area),
                _InfoRow('Family Size', family.familySize.toString()),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Payment Proof Card
class _PaymentProofCard extends StatelessWidget {
  final String imageUrl;

  const _PaymentProofCard({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Payment Proof',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Failed to load image')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Rejection Reason Card
class _RejectionReasonCard extends StatelessWidget {
  final String reason;

  const _RejectionReasonCard({required this.reason});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? Colors.red[900]!.withValues(alpha: 0.3) : Colors.red[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: isDark ? Colors.red[200] : Colors.red[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'Rejection Reason',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.red[200] : Colors.red[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(
                color: isDark ? Colors.red[100] : Colors.red[900],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Info Row Widget
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
