import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Member tile widget for displaying HRM member information
class MemberTile extends StatelessWidget {
  final String uid;
  final String name;
  final String email;
  final List<String> roles;
  final String department;
  final String assignedArea;
  final Timestamp? lastLoginAt;
  final int deliveryCount;
  final int procurementCount;
  final bool isSupervisor;
  final bool isFinalApprover;
  final VoidCallback onTap;
  final int? serialNumber;

  const MemberTile({
    super.key,
    required this.uid,
    required this.name,
    required this.email,
    required this.roles,
    required this.department,
    required this.assignedArea,
    required this.lastLoginAt,
    required this.deliveryCount,
    this.procurementCount = 0,
    this.isSupervisor = false,
    this.isFinalApprover = false,
    required this.onTap,
    this.serialNumber,
  });

  String _mainRoleLabel() {
    if (roles.contains('admin')) return 'Admin';
    if (roles.contains('purchaser')) return 'Purchaser';
    if (roles.contains('distributor')) return 'Distributor';
    if (roles.contains('donor')) return 'Donor';
    return 'Member';
  }

  /// Derive 1–2 character initials from the name
  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Activity status based on last login — returns (label, color, icon)
  (String, Color, IconData) _activityStatus() {
    if (lastLoginAt == null) return ('Never', Colors.grey, Icons.block);
    final daysSince = DateTime.now().difference(lastLoginAt!.toDate()).inDays;
    if (daysSince <= 7) return ('Active', Colors.green, Icons.circle);
    if (daysSince <= 30) return ('Stale', Colors.orange, Icons.circle);
    return ('Inactive', Colors.red, Icons.circle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if this is a donor account
    final isDonor = roles.contains('donor');
    final isPurchaser = roles.contains('purchaser');

    final roleText = _mainRoleLabel();
    final (statusLabel, statusColor, statusIcon) = _activityStatus();

    final lastLoginText = lastLoginAt != null
        ? lastLoginAt!.toDate().toString().split('.').first
        : 'Never';

    // Role-appropriate activity count
    final activityCount = isPurchaser ? procurementCount : deliveryCount;
    final activityLabel = isPurchaser ? 'Procurements' : 'Deliveries';

    // Base color for the avatar based on role
    Color avatarColor = isDark ? Colors.blueGrey[800]! : Colors.blueGrey[50]!;
    Color avatarTextColor = isDark ? Colors.white : Colors.black87;
    if (roles.contains('purchaser')) {
      avatarColor = Colors.purple.withValues(alpha: isDark ? 0.3 : 0.12);
      avatarTextColor = Colors.purple[700]!;
    } else if (roles.contains('distributor')) {
      avatarColor = Colors.teal.withValues(alpha: isDark ? 0.3 : 0.12);
      avatarTextColor = Colors.teal[700]!;
    } else if (roles.contains('admin')) {
      avatarColor = Colors.red.withValues(alpha: isDark ? 0.3 : 0.12);
      avatarTextColor = Colors.red[700]!;
    } else if (isDonor) {
      avatarColor = Colors.orange.withValues(alpha: isDark ? 0.3 : 0.12);
      avatarTextColor = Colors.orange[700]!;
    }

    // RepaintBoundary isolates repaints to this tile, improving scroll performance
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              // Initials Avatar with serial number badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarColor,
                    child: Text(
                      _initials(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: avatarTextColor,
                      ),
                    ),
                  ),
                  if (serialNumber != null)
                    Positioned(
                      bottom: -2,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.dividerColor,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '$serialNumber',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row with optional badges
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Supervisor badge
                        if (isSupervisor) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 10,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Supervisor',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Final Approver badge
                        if (isFinalApprover) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.gavel_rounded,
                                  size: 10,
                                  color: Colors.deepOrange,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Final Approver',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.deepOrange[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Email
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                        fontSize: 11,
                      ),
                    ),
                    // Donor: show only last login
                    if (isDonor) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Last login: $lastLoginText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                          fontSize: 10,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 3),
                      // Role + department + assigned area
                      Text(
                        assignedArea.isNotEmpty
                            ? '$roleText • $department • $assignedArea'
                            : '$roleText • $department',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Activity row: status dot + login + count
                      Row(
                        children: [
                          Icon(statusIcon, size: 8, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                          Text(
                            '  •  $activityLabel: $activityCount',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Chevron
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
