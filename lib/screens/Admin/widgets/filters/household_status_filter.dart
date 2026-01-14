import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Filter widget for household status selection
class HouseholdStatusFilter extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onChanged;

  const HouseholdStatusFilter({
    super.key,
    required this.selectedStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const statuses = {
      'all': 'All',
      'pending': 'Pending',
      'accepted': 'Accepted',
      'rejected': 'Rejected',
      'discarded': 'Discarded',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: statuses.entries.map((entry) {
          final isSelected = selectedStatus == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (_) => onChanged(entry.key),
              selectedColor: AdminColors.primaryBlue.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: isSelected ? AdminColors.primaryBlue : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: isSelected ? AdminColors.primaryBlue : Colors.grey[300]!,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
