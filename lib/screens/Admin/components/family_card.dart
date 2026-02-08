import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart'; // Relative import to avoid package resolution issues

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
  final int? serialNumber;
  final double? targetAmount;
  final double? raisedAmount;

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
    this.serialNumber,
    this.targetAmount,
    this.raisedAmount,
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

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isDark
                    ? Colors.blueGrey[800]
                    : Colors.blueGrey[50],
                child: Text(
                  serialNumber != null
                      ? serialNumber.toString()
                      : familySize.toString(),
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
                      area,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 10,
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
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: assignedVolunteerName == null
                            ? theme.colorScheme.onSurface.withOpacity(0.5)
                            : (isDark ? Colors.greenAccent : Colors.green[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _statusColor().withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(),
                      ),
                    ),
                  ),
                  if (status == 'accepted' &&
                      targetAmount != null &&
                      targetAmount! > 0) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: ((raisedAmount ?? 0) / targetAmount!)
                                  .clamp(0.0, 1.0),
                              backgroundColor:
                                  theme.brightness == Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                              // Show orange if pending included (we can't know for sure here without extra prop,
                              // but we'll assume green for "raised" concept)
                              color: ((raisedAmount ?? 0) >= targetAmount!)
                                  ? Colors.green
                                  : AppColors.donorGreen,
                              minHeight: 3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(((raisedAmount ?? 0) / targetAmount!) * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 8,
                              color: ((raisedAmount ?? 0) >= targetAmount!)
                                  ? Colors.green
                                  : AppColors.donorGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (onEdit != null) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
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
