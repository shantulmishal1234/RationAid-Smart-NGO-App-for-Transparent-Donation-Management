import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/services/donation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_scaffold.dart';

/// Donation Tracking Screen - Track donation from submission to delivery
class DonationTrackingScreen extends StatelessWidget {
  final Donation donation;

  const DonationTrackingScreen({super.key, required this.donation});

  @override
  Widget build(BuildContext context) {
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
        return Colors.orange;
      case DonationStatus.verified:
      case DonationStatus.inProcess:
        return Colors.blue;
      case DonationStatus.outForDelivery:
        return const Color(0xFF00BCD4); // Teal
      case DonationStatus.delivered:
      case DonationStatus.closed:
        return Colors.green;
      case DonationStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (donation.status) {
      case DonationStatus.draft:
        return Icons.edit_note;
      case DonationStatus.pending:
        return Icons.hourglass_empty;
      case DonationStatus.underVerification:
        return Icons.fact_check;
      case DonationStatus.verified:
        return Icons.verified;
      case DonationStatus.inProcess:
        return Icons.inventory_2;
      case DonationStatus.outForDelivery:
        return Icons.local_shipping;
      case DonationStatus.delivered:
        return Icons.check_circle;
      case DonationStatus.closed:
        return Icons.done_all;
      case DonationStatus.rejected:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_getStatusColor(), _getStatusColor().withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _getStatusColor().withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(_getStatusIcon(), size: 50, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            donation.status.displayName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (donation.estimatedDelivery != null) ...[
            const SizedBox(height: 8),
            Text(
              'Estimated: ${_formatDateTime(donation.estimatedDelivery!)}',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Status Timeline Widget
class _StatusTimeline extends StatelessWidget {
  final Donation donation;

  const _StatusTimeline({required this.donation});

  List<DonationStatus> get _allStatuses => [
    DonationStatus.underVerification,
    DonationStatus.verified,
    DonationStatus.inProcess,
    DonationStatus.outForDelivery,
    DonationStatus.delivered,
  ];

  int get _currentIndex => _allStatuses.indexOf(donation.status);

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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Journey Timeline',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(_allStatuses.length, (index) {
            final status = _allStatuses[index];
            final isCompleted = index < _currentIndex;
            final isCurrent = index == _currentIndex;

            return _TimelineStep(
              status: status,
              isCompleted: isCompleted,
              isCurrent: isCurrent,
              isLast: index == _allStatuses.length - 1,
              timestamp: _getTimestampForStatus(status),
            );
          }),
        ],
      ),
    );
  }

  DateTime? _getTimestampForStatus(DonationStatus status) {
    try {
      return donation.statusHistory
          .firstWhere((entry) => entry.status == status)
          .timestamp;
    } catch (e) {
      return null;
    }
  }
}

/// Individual Timeline Step
class _TimelineStep extends StatelessWidget {
  final DonationStatus status;
  final bool isCompleted;
  final bool isCurrent;
  final bool isLast;
  final DateTime? timestamp;

  const _TimelineStep({
    required this.status,
    required this.isCompleted,
    required this.isCurrent,
    required this.isLast,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Circle and line
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted
                    ? Colors.green
                    : isCurrent
                    ? AppColors.donorGreen
                    : (isDark ? Colors.grey[700] : Colors.grey[300]),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppColors.donorGreen.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isCompleted
                    ? Icons.check
                    : isCurrent
                    ? Icons.circle
                    : Icons.circle_outlined,
                color: Colors.white,
                size: isCurrent ? 12 : 16,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted
                    ? Colors.green
                    : (isDark ? Colors.grey[700] : Colors.grey[300]),
              ),
          ],
        ),
        const SizedBox(width: 16),
        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isCurrent || isCompleted
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: isCurrent || isCompleted
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                if (timestamp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(timestamp!),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ] else if (!isCompleted && !isCurrent) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
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
      iconColor: Colors.orange,
      title: 'Awaiting Payment Proof',
      message: 'Please upload your payment proof to proceed with verification.',
    );
  }

  Widget _buildUnderVerificationCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.search,
      iconColor: Colors.blue,
      title: 'Under Review',
      message:
          'Our team is verifying your donation. This usually takes 1-2 hours.',
    );
  }

  Widget _buildVerifiedCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.verified_outlined,
      iconColor: Colors.green,
      title: 'Verified!',
      message: 'Your donation has been approved and will be processed soon.',
    );
  }

  Widget _buildInProcessCard(BuildContext context) {
    return _StatusCard(
      icon: Icons.inventory,
      iconColor: Colors.purple,
      title: 'Being Prepared',
      message: 'Your donation is being packed and prepared for delivery.',
      extraInfo: donation.driverName != null
          ? 'Assigned to: ${donation.driverName}'
          : null,
    );
  }

  Widget _buildOutForDeliveryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_shipping, color: Colors.white, size: 32),
              SizedBox(width: 12),
              Text(
                'On the Way!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Your donation is being delivered',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          if (donation.driverName != null) ...[
            const Divider(color: Colors.white30, height: 32),
            _InfoRow(
              icon: Icons.person,
              label: 'Driver',
              value: donation.driverName!,
            ),
            if (donation.driverPhone != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.phone,
                label: 'Phone',
                value: donation.driverPhone!,
                isPhone: true,
              ),
            ],
            if (donation.vehicleNumber != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.directions_car,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.green, Color(0xFF388E3C)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 40),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delivered Successfully!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
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
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 8),
          ],
          if (donation.receivedBy != null) ...[
            Text(
              'Received by: ${donation.receivedBy}',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            '❤️ Thank you for your generosity!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (donation.deliveryPhotos.isNotEmpty) ...[
            const Divider(color: Colors.white30, height: 32),
            const Text(
              'Delivery Photos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: donation.deliveryPhotos.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        donation.deliveryPhotos[index],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 80,
                            height: 80,
                            color: Colors.white24,
                            child: const Icon(Icons.image, color: Colors.white),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRejectedCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.red[900]!.withOpacity(0.3) : Colors.red[50],
        border: Border.all(color: Colors.red, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cancel, color: Colors.red, size: 32),
              SizedBox(width: 12),
              Text(
                'Donation Rejected',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          if (donation.rejectionReason != null) ...[
            const SizedBox(height: 16),
            Text(
              'Reason:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.red[100] : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              donation.rejectionReason!,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.red[100] : Colors.black87,
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

/// Generic Status Card
class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? extraInfo;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          if (extraInfo != null) ...[
            const SizedBox(height: 12),
            Text(
              extraInfo!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
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
            color: Colors.black.withOpacity(0.05),
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
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
            color: Colors.black.withOpacity(0.05),
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
              color: AppColors.donorGreen.withOpacity(0.1),
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
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.note,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
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
            color: Colors.black.withOpacity(0.05),
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
