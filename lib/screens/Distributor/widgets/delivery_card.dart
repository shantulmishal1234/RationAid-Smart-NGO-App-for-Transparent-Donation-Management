import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared status color mapping for all delivery UI
Color deliveryStatusColor(DeliveryStatus s) {
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

class DeliveryCard extends StatelessWidget {
  final DeliveryAssignment assignment;
  final VoidCallback onTap;

  /// Optional widget injected into the card's top-right area (e.g. release button).
  final Widget? trailing;

  /// Callback for mapping navigation. If null, map logic isn't wired.
  final VoidCallback? onNavigate;

  const DeliveryCard({
    super.key,
    required this.assignment,
    required this.onTap,
    this.trailing,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = assignment.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), // 4% shadow
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 6px left colored track (iOS style)
                Container(width: 6, color: _statusColor(status)),
                Expanded(
                  child: Padding(
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
                                color: _statusColor(
                                  status,
                                ).withValues(alpha: 0.12),
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
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55),
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
                                    ? Colors.green.withValues(alpha: 0.10)
                                    : Colors.grey.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: assignment.familyGeoLat != null
                                      ? Colors.green.withValues(alpha: 0.4)
                                      : Colors.grey.withValues(alpha: 0.3),
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
                              color: Colors.red.withValues(alpha: 0.08),
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

                        // Admin Note
                        if (assignment.adminNote != null &&
                            assignment.adminNote!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    assignment.adminNote!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.orange[300]
                                          : Colors.orange[800],
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Verified badge
                        if (assignment.status ==
                            DeliveryStatus.adminVerified) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: Colors.green,
                                ),
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

                        // Quick actions row
                        if (assignment.status == DeliveryStatus.pickedUp ||
                            assignment.status == DeliveryStatus.inTransit) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (assignment.familyPhone != null &&
                                  assignment.familyPhone!.isNotEmpty) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _launchURL(
                                      'tel:${assignment.familyPhone}',
                                    ),
                                    icon: const Icon(Icons.phone, size: 16),
                                    label: const Text('Call'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green,
                                      side: BorderSide(
                                        color: Colors.green.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (onNavigate != null &&
                                  assignment.familyGeoLat != null &&
                                  assignment.familyGeoLng != null) ...[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: onNavigate,
                                    icon: const Icon(
                                      Icons.navigation,
                                      size: 16,
                                    ),
                                    label: const Text('Navigate'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.volunteerBlue,
                                      side: const BorderSide(
                                        color: AppColors.volunteerBlue,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _infoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  Color _statusColor(DeliveryStatus s) => deliveryStatusColor(s);

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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

  Color _color(DeliveryStatus s) => deliveryStatusColor(s);
}
