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
  final VoidCallback? onEdit; // NEW

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
    this.onEdit, // NEW
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
    // RepaintBoundary isolates repaints to this card, improving scroll performance
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.blueGrey[50],
                child: Text(
                  familySize.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                            ? Colors.grey[500]
                            : Colors.green[700],
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
                      icon: const Icon(Icons.edit_outlined, size: 18),
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
