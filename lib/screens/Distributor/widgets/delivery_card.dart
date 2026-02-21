import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/theme/app_colors.dart';

class DeliveryCard extends StatelessWidget {
  final DeliveryAssignment assignment;
  final VoidCallback onTap;

  /// Optional widget injected into the card's top-right area (e.g. release button).
  final Widget? trailing;

  const DeliveryCard({
    super.key,
    required this.assignment,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = assignment.status;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _statusColor(status).withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Status bar at top
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: _statusColor(status),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _statusIcon(status),
                          color: _statusColor(status),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${assignment.familyArea}, ${assignment.familyCity}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${assignment.items.length} item type(s) · Family of ${assignment.familySize}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Optional trailing action widget (e.g. release button)
                      if (trailing != null) trailing!,
                      _StatusChip(status: status),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Info row
                  Row(
                    children: [
                      _infoItem(
                        context,
                        Icons.inventory_2_outlined,
                        assignment.assignedPackName ?? 'Standard Pack',
                      ),
                      const SizedBox(width: 16),
                      _infoItem(
                        context,
                        Icons.schedule,
                        assignment.scheduledAt != null
                            ? DateFormat(
                                'MMM dd, hh:mm a',
                              ).format(assignment.scheduledAt!)
                            : 'ASAP',
                      ),
                    ],
                  ),

                  // GPS + admin-verified badges row
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // GPS availability badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: assignment.familyGeoLat != null
                              ? Colors.green.withOpacity(0.10)
                              : Colors.grey.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: assignment.familyGeoLat != null
                                ? Colors.green.withOpacity(0.4)
                                : Colors.grey.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              assignment.familyGeoLat != null
                                  ? Icons.location_on
                                  : Icons.location_off,
                              size: 11,
                              color: assignment.familyGeoLat != null
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              assignment.familyGeoLat != null
                                  ? (assignment.familyLocationVerified
                                        ? 'GPS Verified'
                                        : 'GPS Available')
                                  : 'No GPS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: assignment.familyGeoLat != null
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Failure badge
                  if (assignment.isFailed &&
                      assignment.failureReason != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            assignment.failureReason!.displayName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Verified badge
                  if (assignment.status == DeliveryStatus.adminVerified) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Admin Verified',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Tap indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.volunteerBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: AppColors.volunteerBlue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
          ),
        ),
      ],
    );
  }

  Color _statusColor(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Colors.grey;
      case DeliveryStatus.pickedUp:
        return Colors.orange;
      case DeliveryStatus.inTransit:
        return AppColors.volunteerBlue;
      case DeliveryStatus.delivered:
        return Colors.purple;
      case DeliveryStatus.adminVerified:
        return Colors.green;
      case DeliveryStatus.failed:
        return Colors.red;
      case DeliveryStatus.reassigned:
        return Colors.deepOrange;
    }
  }

  IconData _statusIcon(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Icons.hourglass_empty;
      case DeliveryStatus.pickedUp:
        return Icons.shopping_bag_outlined;
      case DeliveryStatus.inTransit:
        return Icons.local_shipping;
      case DeliveryStatus.delivered:
        return Icons.check_circle_outline;
      case DeliveryStatus.adminVerified:
        return Icons.verified;
      case DeliveryStatus.failed:
        return Icons.cancel_outlined;
      case DeliveryStatus.reassigned:
        return Icons.swap_horiz;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final DeliveryStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _color(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Colors.grey;
      case DeliveryStatus.pickedUp:
        return Colors.orange;
      case DeliveryStatus.inTransit:
        return AppColors.volunteerBlue;
      case DeliveryStatus.delivered:
        return Colors.purple;
      case DeliveryStatus.adminVerified:
        return Colors.green;
      case DeliveryStatus.failed:
        return Colors.red;
      case DeliveryStatus.reassigned:
        return Colors.deepOrange;
    }
  }
}
