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
    final theme = Theme.of(context);
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
              backgroundColor: theme.cardColor,
              labelStyle: TextStyle(
                color: isSelected
                    ? AdminColors.primaryBlue
                    : theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: isSelected
                    ? AdminColors.primaryBlue
                    : theme.dividerColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
