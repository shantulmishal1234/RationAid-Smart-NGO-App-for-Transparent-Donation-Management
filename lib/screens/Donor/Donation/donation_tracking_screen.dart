import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';

/// Donation Tracking Screen - Track donation from submission to delivery
/// Donation Tracking Screen - Track donation from submission to delivery
class DonationTrackingScreen extends StatefulWidget {
  final Donation donation;

  const DonationTrackingScreen({super.key, required this.donation});

  @override
  State<DonationTrackingScreen> createState() => _DonationTrackingScreenState();
}

class _DonationTrackingScreenState extends State<DonationTrackingScreen> {
  final DonationService _donationService = DonationService();
  late Stream<Donation?> _donationStream;

  @override
  void initState() {
    super.initState();
    _donationStream = _donationService.streamDonation(widget.donation.id);
  }

  String _getDynamicTitle(DonationStatus status) {
    switch (status) {
      case DonationStatus.draft:
        return 'Complete Your Donation';
      case DonationStatus.pending:
        return 'Action Required';
      case DonationStatus.underVerification:
        return 'Verification in Progress';
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
      case DonationStatus.inProcess:
      case DonationStatus.outForDelivery:
        return 'Track Your Donation';
      case DonationStatus.stocked:
        return 'Items In Warehouse';
      case DonationStatus.delivered:
      case DonationStatus.closed:
        return 'Donation Receipt';
      case DonationStatus.rejected:
        return 'Donation Required Action';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Donation?>(
      stream: _donationStream,
      initialData: widget.donation,
      builder: (context, snapshot) {
        // If data is null (document deleted?), fallback to initial or show error
        final donation = snapshot.data ?? widget.donation;

        return DonorScaffold(
          title: _getDynamicTitle(donation.status),
          showBackButton: true,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Current Status Header
                _CurrentStatusHeader(donation: donation),
                const SizedBox(height: 20),

                // Status Timeline vs Micro-Ledger Tracker
                if (donation.familyId == 'general_relief_fund' &&
                    donation.status == DonationStatus.verified)
                  _MicroLedgerTracker(donation: donation)
                else
                  _StatusTimeline(donation: donation),
                const SizedBox(height: 20),

                // Live Status Card (dynamic based on current status)
                _LiveStatusCard(donation: donation),
                const SizedBox(height: 20),

                // Donation Details
                _DonationDetailsCard(donation: donation),
                const SizedBox(height: 20),

                // Update History removed and merged into StatusTimeline

                // Action Buttons for drafts
                if (donation.isEditable || donation.isDeletable) ...[
                  const SizedBox(height: 20),
                  _ActionButtons(donation: donation),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Current Status Header Widget
class _CurrentStatusHeader extends StatelessWidget {
  final Donation donation;

  const _CurrentStatusHeader({required this.donation});

  Color _getStatusColor() {
    switch (donation.status) {
      case DonationStatus.draft:
        return Colors.grey;
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        return const Color(0xFFFF9800); // Orange
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
      case DonationStatus.inProcess:
        return const Color(0xFF2196F3); // Blue
      case DonationStatus.stocked:
        return const Color(0xFF009688); // Teal – In Warehouse
      case DonationStatus.outForDelivery:
        return const Color(0xFF00BCD4); // Teal
      case DonationStatus.delivered:
      case DonationStatus.closed:
        return const Color(0xFF4CAF50); // Green
      case DonationStatus.rejected:
        return const Color(0xFFE53935); // Red
    }
  }

  IconData _getStatusIcon() {
    switch (donation.status) {
      case DonationStatus.draft:
        return Icons.edit_note;
      case DonationStatus.pending:
        return Icons.hourglass_top;
      case DonationStatus.underVerification:
        return Icons.search;
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
        return Icons.check_circle_outline;
      case DonationStatus.stocked:
        return Icons.warehouse_outlined;
      case DonationStatus.inProcess:
        return Icons.inventory_2_outlined;
      case DonationStatus.outForDelivery:
        return Icons.local_shipping_outlined;
      case DonationStatus.delivered:
      case DonationStatus.closed:
        return Icons.mark_email_read_outlined;
      case DonationStatus.rejected:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.1)
            : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_getStatusIcon(), size: 48, color: color),
          ),
          const SizedBox(height: 20),
          Text(
            donation.status.displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          if (donation.estimatedDelivery != null &&
              donation.status != DonationStatus.delivered &&
              donation.status != DonationStatus.closed &&
              donation.status != DonationStatus.rejected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'Est. Delivery: ${_formatDate(donation.estimatedDelivery!)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Status Timeline Widget
class _StatusTimeline extends StatelessWidget {
  final Donation donation;

  const _StatusTimeline({required this.donation});

  List<DonationStatus> get _getTimelineSteps {
    if (donation.status == DonationStatus.rejected) {
      return [
        DonationStatus.draft,
        DonationStatus.underVerification,
        DonationStatus.rejected,
      ];
    }

    // For GRF/Pool donations, timeline is adapted for virtual assignment.
    if (donation.familyId == 'general_relief_fund' ||
        donation.allocationMode == 'general' ||
        donation.allocationMode == 'pool' ||
        donation.allocationMode == 'pool_assigned') {
      return [
        DonationStatus.draft,
        DonationStatus.underVerification,
        DonationStatus.pendingAssignment,
        DonationStatus.verified,
        DonationStatus.closed,
      ];
    }

    return [
      DonationStatus.draft,
      DonationStatus.underVerification,
      DonationStatus.verified,
      DonationStatus.outForDelivery,
      DonationStatus.delivered,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _getTimelineSteps;

    // Determine current index
    int currentIndex = 0;
    if (donation.status == DonationStatus.closed) {
      currentIndex = steps.length - 1;
    } else {
      currentIndex = steps.indexOf(donation.status);
      if (currentIndex == -1) {
        // Handle intermediate states mapping
        if (donation.status == DonationStatus.pending) currentIndex = 0;
        if (donation.status == DonationStatus.inProcess) {
          currentIndex = 2; // Map to Verified
        }
      }
    }

    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tracking History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: steps.length,
            itemBuilder: (context, index) {
              final status = steps[index];
              final isCompleted = index < currentIndex;
              final isCurrent = index == currentIndex;
              final isLast = index == steps.length - 1;

              final relevantEntry = _getEntryForStatus(status);

              return _TimelineStep(
                status: status,
                isCompleted: isCompleted,
                isCurrent: isCurrent,
                isLast: isLast,
                isRejected: status == DonationStatus.rejected,
                isGrf:
                    donation.familyId == 'general_relief_fund' ||
                    donation.allocationMode == 'general',
                timestamp: relevantEntry?.timestamp != DateTime(0)
                    ? relevantEntry?.timestamp
                    : null,
                note: relevantEntry?.note.isNotEmpty == true
                    ? relevantEntry!.note
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  StatusHistoryEntry? _getEntryForStatus(DonationStatus status) {
    try {
      return donation.statusHistory.lastWhere(
        (entry) {
          // Map intermediate history statuses to simplified timeline steps
          if (status == DonationStatus.verified) {
            return entry.status == DonationStatus.verified ||
                entry.status == DonationStatus.inProcess;
          }
          if (status == DonationStatus.draft) {
            return entry.status == DonationStatus.draft ||
                entry.status == DonationStatus.pending;
          }
          return entry.status == status;
        },
        orElse: () => StatusHistoryEntry(
          status: status,
          timestamp: DateTime(0),
          note: '',
        ),
      );
    } catch (e) {
      return null;
    }
  }
}

class _TimelineStep extends StatelessWidget {
  final DonationStatus status;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;
  final bool isRejected;
  final bool isGrf;
  final DateTime? timestamp;
  final String? note;

  const _TimelineStep({
    required this.status,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLast,
    this.isRejected = false,
    this.isGrf = false,
    this.timestamp,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color stepColor;
    if (isRejected && (isCurrent || isCompleted)) {
      stepColor = Colors.red;
    } else if (isCompleted) {
      stepColor = AppColors.donorGreen;
    } else if (isCurrent) {
      stepColor = AppColors.donorGreen;
    } else {
      stepColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Line & Dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Top Line (connects to previous)
                // The Dot
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isCurrent ? Colors.white : stepColor,
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: stepColor, width: 4)
                        : null,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: stepColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: isCompleted && !isRejected
                      ? const Icon(Icons.check, size: 10, color: Colors.white)
                      : isRejected
                      ? const Icon(Icons.close, size: 10, color: Colors.white)
                      : null,
                ),
                // Bottom Line (connects to next)
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isCompleted
                          ? stepColor
                          : (isDark ? Colors.grey[800] : Colors.grey[200]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getDisplayName(status),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isCurrent || isCompleted
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isCurrent || isCompleted
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _formatTime(timestamp!),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(timestamp!),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ] else if (isCurrent) ...[
                    const SizedBox(height: 4),
                    Text(
                      'In Progress...',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: stepColor,
                      ),
                    ),
                  ],
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: stepColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.format_quote,
                            size: 14,
                            color: stepColor.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              note!,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                ),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayName(DonationStatus status) {
    if (status == DonationStatus.outForDelivery) return 'Out for Delivery';
    if (isGrf && status == DonationStatus.verified) {
      return 'Awaiting Allocation';
    }
    if (isGrf && status == DonationStatus.closed) return 'Fund Deployed';
    return status.displayName;
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Live Status Card - Changes based on donation status
class _LiveStatusCard extends StatelessWidget {
  final Donation donation;

  const _LiveStatusCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    switch (donation.status) {
      case DonationStatus.pending:
        return _buildPendingCard(context);
      case DonationStatus.underVerification:
        return _buildUnderVerificationCard(context);
      case DonationStatus.verified:
      case DonationStatus.pendingAssignment:
        return _buildVerifiedCard(context);
      case DonationStatus.inProcess:
        return _buildInProcessCard(context);
      case DonationStatus.outForDelivery:
        return _buildOutForDeliveryCard(context);
      case DonationStatus.delivered:
        return _buildDeliveredCard(context);
      case DonationStatus.rejected:
        return _buildRejectedCard(context);
      default:
        return const SizedBox();
    }
  }

  Widget _buildPendingCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.upload_file,
      iconColor: const Color(0xFFFF9800),
      title: 'Action Required',
      message: 'Please upload your payment proof to proceed with verification.',
      isAction: true,
      donation: donation,
      actionButtonText: 'Upload Proof Now',
    );
  }

  Widget _buildUnderVerificationCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.search,
      iconColor: const Color(0xFF2196F3),
      title: 'Under Review',
      message:
          'Our team is verifying your donation. This usually takes 1-2 hours.',
    );
  }

  Widget _buildVerifiedCard(BuildContext context) {
    final isGrf =
        donation.familyId == 'general_relief_fund' ||
        donation.allocationMode == 'general';
    return _StatusCard(
      icon: isGrf
          ? Icons.account_balance_wallet_outlined
          : Icons.verified_user_outlined,
      iconColor: const Color(0xFF4CAF50),
      title: isGrf ? 'Awaiting Allocation' : 'Verified & Approved',
      message: isGrf
          ? 'Your contribution is secured in the General Relief Fund vault. It will be dispatched dynamically to close emergency gaps.'
          : 'Your donation has been approved and is ready for processing.',
    );
  }

  Widget _buildInProcessCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.inventory_2_outlined,
      iconColor: const Color(0xFF9C27B0), // Purple
      title: 'Being Prepared',
      message: 'Your donation is being packed and prepared for delivery.',
      extraInfo: donation.driverName != null
          ? 'Driver Assigned: ${donation.driverName}'
          : null,
    );
  }

  Widget _buildOutForDeliveryCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00BCD4).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF00BCD4),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'On the Way!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF00BCD4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your donation is fast approaching.',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (donation.driverName != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Divider(
                color: theme.dividerColor.withValues(alpha: 0.2),
                height: 1,
              ),
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Driver Name',
              value: donation.driverName!,
              iconColor: const Color(0xFF00BCD4),
            ),
            if (donation.driverPhone != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Contact',
                value: donation.driverPhone!,
                iconColor: const Color(0xFF00BCD4),
                isPhone: true,
              ),
            ],
            if (donation.vehicleNumber != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.directions_car_outlined,
                label: 'Vehicle',
                value: donation.vehicleNumber!,
                iconColor: const Color(0xFF00BCD4),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveredCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF4CAF50),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Mission Complete!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (donation.deliveredAt != null) ...[
            Text(
              'Delivered on ${_formatDate(donation.deliveredAt!)}',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (donation.receivedBy != null) ...[
            Text(
              'Received by: ${donation.receivedBy}',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (donation.deliveryPhotos.isNotEmpty) ...[
            Text(
              'Proof of Delivery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: donation.deliveryPhotos.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        donation.deliveryPhotos[index],
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 100,
                            height: 100,
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: theme.colorScheme.onSurface,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '❤️ Thank you for your generosity!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFB71C1C).withValues(alpha: 0.2)
            : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEF5350), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFFD32F2F),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Donation Rejected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ],
          ),
          if (donation.rejectionReason != null) ...[
            const SizedBox(height: 16),
            Text(
              'REASON FOR REJECTION',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD32F2F).withValues(alpha: 0.8),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              donation.rejectionReason!,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.red[100] : Colors.black87,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? extraInfo;
  final bool isAction;
  final Donation? donation;
  final String? actionButtonText;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.extraInfo,
    this.isAction = false,
    this.donation,
    this.actionButtonText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isAction
              ? iconColor
              : theme.dividerColor.withValues(alpha: 0.2),
          width: isAction ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (extraInfo != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                extraInfo!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: iconColor,
                ),
              ),
            ),
          ],
          if (isAction && actionButtonText != null && donation != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/create-donation',
                    arguments: donation,
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: Text(actionButtonText!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.donorGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Info Row for delivery details
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final bool isPhone;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = Colors.grey,
    this.isPhone = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        if (isPhone)
          IconButton(
            onPressed: () async {
              final Uri phoneUri = Uri(scheme: 'tel', path: value);
              if (await canLaunchUrl(phoneUri)) {
                await launchUrl(phoneUri);
              }
            },
            icon: Icon(Icons.phone, color: iconColor),
          ),
      ],
    );
  }
}

/// Donation Details Card
class _DonationDetailsCard extends StatelessWidget {
  final Donation donation;

  const _DonationDetailsCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, color: AppColors.donorGreen),
              const SizedBox(width: 8),
              Text(
                'Donation Details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.people, size: 20, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Beneficiary: ${donation.familyId == 'general_relief_fund'
                      ? 'General Relief Fund'
                      : donation.allocationMode == 'smart'
                      ? 'Smart Give (Auto-Allocated)'
                      : 'Family Support'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (donation.items != null && donation.items!.isNotEmpty) ...[
            Text(
              'Items:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...donation.items!.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.donorGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.key} (${entry.value} kg)',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (donation.amount != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  'Amount: PKR ${donation.amount!.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
          if (donation.donationNote != null) ...[
            const SizedBox(height: 16),
            Text(
              'Note:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              donation.donationNote!,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (donation.smartSplits != null &&
              donation.smartSplits!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  color: AppColors.donorGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Impact Breakdown',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...donation.smartSplits!.map((split) {
              final String familyId = split['familyId'] as String? ?? '';
              final bool isPool =
                  familyId.isEmpty || familyId == 'general_relief_fund';

              Widget familyLabelWidget;
              if (isPool) {
                familyLabelWidget = const Text(
                  'NGO General Pool',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                );
              } else {
                final familyData = split['family'] as Map<String, dynamic>?;
                final String area = familyData?['area'] as String? ?? '';
                final String shortId = familyId.length > 5 ? familyId.substring(0, 5) : familyId;
                
                if (area.isNotEmpty) {
                  familyLabelWidget = Text(
                    '$area Family',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  );
                } else {
                  // Fallback: Fetch from database dynamically
                  familyLabelWidget = FutureBuilder<Family?>(
                    future: FamilyService().getFamilyById(familyId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text(
                          'Loading family...',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        );
                      }
                      if (snapshot.hasData && snapshot.data != null) {
                        return Text(
                          '${snapshot.data!.area} Family',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        );
                      }
                      return Text(
                        'Family $shortId...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      );
                    },
                  );
                }
              }

              String displayValue;
              if (donation.donationType == DonationType.cash) {
                final double amt = (split['amount'] as num?)?.toDouble() ?? 0.0;
                displayValue = 'PKR ${amt.toStringAsFixed(0)}';
              } else {
                final Map<String, dynamic> splitItems =
                    split['items'] as Map<String, dynamic>? ?? {};
                final String itemsSummary = splitItems.entries
                    .map((e) => '${e.value}kg ${e.key}')
                    .join(', ');
                displayValue = itemsSummary.isEmpty ? 'Reserved' : itemsSummary;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isPool ? Colors.teal : AppColors.donorGreen)
                      .withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isPool ? Colors.teal : AppColors.donorGreen)
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    familyLabelWidget,
                    const SizedBox(height: 4),
                    Text(
                      displayValue,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    if (split['reason'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${split['reason']}',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// Update History Card intentionally removed.
// Admin notes and status changes have been strictly integrated directly into
// the `_StatusTimeline` vertical tracking tree to vastly improve UX efficiency and reduce height.

/// Action Buttons Widget - Edit and Delete for drafts
class _ActionButtons extends StatefulWidget {
  final Donation donation;

  const _ActionButtons({required this.donation});

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _isDeleting = false;

  Future<void> _editDonation() async {
    final result = await Navigator.pushNamed(
      context,
      '/create-donation',
      arguments: widget.donation,
    );

    // If edit was successful, go back to refresh
    if (result != null && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _deleteDonation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Donation?'),
        content: const Text(
          'This action cannot be undone. Are you sure you want to delete this draft donation?',
        ),
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

    if (confirm == true && mounted) {
      setState(() => _isDeleting = true);

      try {
        final donationService = DonationService();
        await donationService.deleteDonation(widget.donation.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Donation deleted successfully')),
          );
          Navigator.pop(context); // Go back after deletion
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isDeleting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting donation: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // Edit Button
          if (widget.donation.isEditable)
            ElevatedButton.icon(
              onPressed: _editDonation,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Donation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.donorGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

          // Delete Button
          if (widget.donation.isDeletable) ...[
            if (widget.donation.isEditable) const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isDeleting ? null : _deleteDonation,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Icon(Icons.delete),
              label: Text(_isDeleting ? 'Deleting...' : 'Delete Draft'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MicroLedgerTracker extends StatelessWidget {
  final Donation donation;

  const _MicroLedgerTracker({required this.donation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final double effective = donation.effectiveAmount > 0
        ? donation.effectiveAmount
        : (donation.amount ?? 0);
    final double allocated = donation.allocatedAmount;
    final double percentage = effective > 0
        ? (allocated / effective).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  isDark
                      ? Colors.indigo.shade900.withValues(alpha: 0.3)
                      : Colors.indigo.shade50,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.account_balance_wallet,
                        color: isDark
                            ? Colors.blueAccent
                            : Colors.blue.shade700,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your Impact Ledger',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.blueAccent
                              : Colors.blue.shade900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Progress Bar
                LinearProgressIndicator(
                  value: percentage,
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  color: Colors.blue,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'PKR ${allocated.toStringAsFixed(0)} Deployed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      'PKR ${(effective - allocated).toStringAsFixed(0)} Remaining',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Allocations List
          Padding(
            padding: const EdgeInsets.all(20),
            child:
                (donation.grfAllocations == null ||
                    donation.grfAllocations!.isEmpty)
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Awaiting first family allocation gap...',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Deployments',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...donation.grfAllocations!.reversed.map((alloc) {
                        final fId = alloc['familyId'].toString();
                        final shortId = fId.length > 6
                            ? fId.substring(0, 6)
                            : fId;
                        final amt = (alloc['amount'] as num).toDouble();
                        final ts = alloc['date'] as Timestamp;
                        final dt = ts.toDate();
                        final dateStr =
                            '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Family Need Fulfilled',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      'ID: $shortId... • $dateStr',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'PKR ${amt.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
