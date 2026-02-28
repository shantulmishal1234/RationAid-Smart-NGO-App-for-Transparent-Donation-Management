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

  String _levelLabel() {
    if (roles.contains('head')) return 'Head';
    if (roles.contains('sub_head')) return 'Sub-head';
    if (roles.contains('member')) return 'Member';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if this is a donor account
    final isDonor = roles.contains('donor');

    final level = _levelLabel();
    final roleText = level.isEmpty
        ? _mainRoleLabel()
        : '${_mainRoleLabel()} • $level';

    final lastLoginText = lastLoginAt != null
        ? lastLoginAt!.toDate().toString().split('.').first
        : 'Never';

    // RepaintBoundary isolates repaints to this tile, improving scroll performance
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isDark
                    ? Colors.blueGrey[800]
                    : Colors.blueGrey[50],
                child: Text(
                  serialNumber != null
                      ? serialNumber.toString()
                      : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                    // For donors: show last login only
                    // For others: show role, department, last login, and deliveries
                    if (isDonor) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Last login: $lastLoginText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 1),
                      Text(
                        '$roleText • $department',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Last login: $lastLoginText • Deliveries: $deliveryCount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
