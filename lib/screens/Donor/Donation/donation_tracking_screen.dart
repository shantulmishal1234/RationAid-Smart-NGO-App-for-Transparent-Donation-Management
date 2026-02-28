import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/donation_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Donation?>(
      stream: _donationStream,
      initialData: widget.donation,
      builder: (context, snapshot) {
        // If data is null (document deleted?), fallback to initial or show error
        final donation = snapshot.data ?? widget.donation;

        return DonorScaffold(
          title: 'Donation #${donation.id.substring(0, 8)}',
          showBackButton: true,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Current Status Header
                _CurrentStatusHeader(donation: donation),
                const SizedBox(height: 20),

                // Status Timeline
                _StatusTimeline(donation: donation),
                const SizedBox(height: 20),

                // Live Status Card (dynamic based on current status)
                _LiveStatusCard(donation: donation),
                const SizedBox(height: 20),

                // Donation Details
                _DonationDetailsCard(donation: donation),
                const SizedBox(height: 20),

                // Update History
                if (donation.statusHistory.isNotEmpty)
                  _UpdateHistoryCard(donation: donation),

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
      case DonationStatus.inProcess:
        return const Color(0xFF2196F3); // Blue
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
        return Icons.check_circle_outline;
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(_getStatusIcon(), size: 48, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            donation.status.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
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
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Est. Delivery: ${_formatDate(donation.estimatedDelivery!)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
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
        if (donation.status == DonationStatus.inProcess)
          currentIndex = 2; // Map to Verified
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
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

              return _TimelineStep(
                status: status,
                isCompleted: isCompleted,
                isCurrent: isCurrent,
                isLast: isLast,
                isRejected: status == DonationStatus.rejected,
                timestamp: _getTimestampForStatus(status),
              );
            },
          ),
        ],
      ),
    );
  }

  DateTime? _getTimestampForStatus(DonationStatus status) {
    try {
      final relevantEntry = donation.statusHistory.lastWhere(
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

      if (relevantEntry.timestamp.year == 0) return null;
      return relevantEntry.timestamp;
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
  final DateTime? timestamp;

  const _TimelineStep({
    required this.status,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLast,
    this.isRejected = false,
    this.timestamp,
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
                              : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _formatTime(timestamp!),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
    return _StatusCard(
      icon: Icons.verified_user_outlined,
      iconColor: const Color(0xFF4CAF50),
      title: 'Verified & Approved',
      message: 'Your donation has been approved and is ready for processing.',
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.4),
            blurRadius: 16,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On the Way!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Your donation is fast approaching.',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (donation.driverName != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(color: Colors.white24, height: 1),
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Driver Name',
              value: donation.driverName!,
            ),
            if (donation.driverPhone != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Contact',
                value: donation.driverPhone!,
                isPhone: true,
              ),
            ],
            if (donation.vehicleNumber != null) ...[
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.directions_car_outlined,
                label: 'Vehicle',
                value: donation.vehicleNumber!,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveredCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
            blurRadius: 16,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Mission Complete!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (donation.deliveredAt != null) ...[
            Text(
              'Delivered on ${_formatDate(donation.deliveredAt!)}',
              style: const TextStyle(
                fontSize: 15,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (donation.receivedBy != null) ...[
            Text(
              'Received by: ${donation.receivedBy}',
              style: const TextStyle(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (donation.deliveryPhotos.isNotEmpty) ...[
            const Text(
              'Proof of Delivery',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
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
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                            color: Colors.white24,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white,
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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '❤️ Thank you for your generosity!',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.extraInfo,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: isAction
            ? Border.all(color: iconColor, width: 2)
            : Border.all(color: iconColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.08),
            blurRadius: 20,
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
  final bool isPhone;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isPhone = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
            icon: const Icon(Icons.phone, color: Colors.white),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              Text(
                'Beneficiary: ${donation.familyId == 'general_relief_fund' ? 'General Relief Fund' : 'Family Support'}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
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
                  Icons.attach_money,
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
        ],
      ),
    );
  }
}

/// Update History Card
class _UpdateHistoryCard extends StatelessWidget {
  final Donation donation;

  const _UpdateHistoryCard({required this.donation});

  @override
  Widget build(BuildContext context) {
    final reversedHistory = donation.statusHistory.reversed.toList();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              const Icon(Icons.history, color: AppColors.donorGreen),
              const SizedBox(width: 8),
              Text(
                'Updates & Activity',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...reversedHistory.map((entry) {
            return _UpdateItem(entry: entry);
          }),
        ],
      ),
    );
  }
}

/// Individual Update Item
class _UpdateItem extends StatelessWidget {
  final StatusHistoryEntry entry;

  const _UpdateItem({required this.entry});

  IconData _getIcon() {
    switch (entry.status) {
      case DonationStatus.pending:
        return Icons.upload_file;
      case DonationStatus.underVerification:
        return Icons.search;
      case DonationStatus.verified:
        return Icons.verified;
      case DonationStatus.inProcess:
        return Icons.inventory;
      case DonationStatus.outForDelivery:
        return Icons.local_shipping;
      case DonationStatus.delivered:
        return Icons.check_circle;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.donorGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIcon(), size: 16, color: AppColors.donorGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.status.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.note,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
