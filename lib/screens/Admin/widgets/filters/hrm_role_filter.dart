import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Filter widget for HRM role selection
class HrmRoleFilter extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onChanged;

  const HrmRoleFilter({
    super.key,
    required this.selectedRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const roles = {
      'all': 'All',
      'purchasers': 'Purchasers',
      'distributors': 'Distributors',
      'donors': 'Donors',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: roles.entries.map((entry) {
          final isSelected = selectedRole == entry.key;
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
