import 'package:flutter/material.dart';

/// Family card widget for displaying family information
class FamilyCard extends StatelessWidget {
  final String id;
  final String name;
  final String area;
  final String address;
  final int familySize;
  final String status;
  final VoidCallback onTap;
  final String? assignedVolunteerName;
  final VoidCallback? onEdit;
  final int? serialNumber; // NEW

  const FamilyCard({
    super.key,
    required this.id,
    required this.name,
    required this.area,
    required this.address,
    required this.familySize,
    required this.status,
    required this.assignedVolunteerName,
    required this.onTap,
    this.onEdit,
    this.serialNumber, // NEW
  });

  Color _statusColor() {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'discarded':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel() {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'discarded':
        return 'Discarded';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // RepaintBoundary isolates repaints to this card, improving scroll performance
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isDark
                    ? Colors.blueGrey[800]
                    : Colors.blueGrey[50],
                child: Text(
                  serialNumber != null
                      ? serialNumber.toString()
                      : familySize.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      assignedVolunteerName != null
                          ? 'Assigned: $assignedVolunteerName'
                          : 'Assigned: None',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: assignedVolunteerName == null
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : (isDark ? Colors.greenAccent : Colors.green[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status pill + optional edit icon in a column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(),
                      ),
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(height: 4),
                    IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Edit family',
                      onPressed: onEdit,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
