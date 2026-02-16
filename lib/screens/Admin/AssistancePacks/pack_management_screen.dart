import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/services/assistance_pack_service.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/screens/Admin/AssistancePacks/pack_form_dialog.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';

/// Screen for managing assistance packs
class PackManagementScreen extends StatefulWidget {
  const PackManagementScreen({super.key});

  @override
  State<PackManagementScreen> createState() => _PackManagementScreenState();
}

class _PackManagementScreenState extends State<PackManagementScreen> {
  String _searchQuery = '';
  String _filterType = 'all';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Assistance Pack Management',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Overview Stats
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedPanel(
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot>(
              stream: AssistancePackService.getPacksStream(),
              builder: (context, snapshot) {
                final packs = snapshot.hasData
                    ? snapshot.data!.docs
                          .map((doc) => AssistancePack.fromFirestore(doc))
                          .toList()
                    : [];

                final totalPacks = packs.length;
                final activePacks = packs.where((p) => p.isActive).length;
                final inactivePacks = totalPacks - activePacks;

                return ExpansionTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(
                    'Overview & Statistics',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  leading: Icon(
                    Icons.analytics_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total Packs',
                          totalPacks.toString(),
                          AdminColors.primaryBlue,
                        ),
                        _statItem(
                          'Active',
                          activePacks.toString(),
                          Colors.green[600]!,
                        ),
                        _statItem(
                          'Inactive',
                          inactivePacks.toString(),
                          Colors.grey[600]!,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Toolbar: Search | Filter | Add
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Search Bar
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search packs...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Filter Menu
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.6),
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Type',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (v) => setState(() => _filterType = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'all', child: Text('All Types')),
                    const PopupMenuItem(value: 'food', child: Text('Food')),
                    const PopupMenuItem(
                      value: 'clothing',
                      child: Text('Clothing'),
                    ),
                    const PopupMenuItem(value: 'mixed', child: Text('Mixed')),
                    const PopupMenuItem(
                      value: 'education',
                      child: Text('Education'),
                    ),
                    const PopupMenuItem(
                      value: 'medical',
                      child: Text('Medical'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Add Button
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _showPackDialog(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Packs List
        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot>(
              stream: AssistancePackService.getPacksStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: theme.disabledColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No assistance packs yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.disabledColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _showPackDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Create First Pack'),
                        ),
                      ],
                    ),
                  );
                }

                // Filter packs
                final packs = snapshot.data!.docs
                    .map((doc) => AssistancePack.fromFirestore(doc))
                    .where((pack) {
                      final matchesSearch = pack.name.toLowerCase().contains(
                        _searchQuery,
                      );
                      final matchesType =
                          _filterType == 'all' || pack.packType == _filterType;
                      return matchesSearch && matchesType;
                    })
                    .toList();

                if (packs.isEmpty) {
                  return Center(
                    child: Text(
                      'No packs match your search',
                      style: TextStyle(color: theme.disabledColor),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: packs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _buildPackCard(context, packs[index], index + 1);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildPackCard(BuildContext context, AssistancePack pack, int index) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatPackType(pack.packType),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Active Status
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: pack.isActive
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pack.isActive ? Icons.check_circle : Icons.cancel,
                        size: 14,
                        color: pack.isActive ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pack.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: pack.isActive ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (pack.description != null && pack.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pack.description!,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Stats Row
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _infoChip(
                  icon: Icons.people_outline,
                  label: '${pack.minMembers}-${pack.maxMembers} members',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.attach_money,
                  label: 'PKR ${pack.budgetAmount.toStringAsFixed(0)}',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.inventory_2_outlined,
                  label: '${pack.items.length} items',
                  theme: theme,
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showPackDialog(context, pack: pack),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.primaryBlue,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _toggleStatus(pack),
                  icon: Icon(
                    pack.isActive ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                  ),
                  label: Text(pack.isActive ? 'Deactivate' : 'Activate'),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                ),
                TextButton.icon(
                  onPressed: () => _deletePack(pack),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPackType(String type) {
    return type[0].toUpperCase() + type.substring(1);
  }

  void _showPackDialog(BuildContext context, {AssistancePack? pack}) {
    showDialog(
      context: context,
      builder: (context) => PackFormDialog(pack: pack),
    );
  }

  Future<void> _toggleStatus(AssistancePack pack) async {
    try {
      await AssistancePackService.toggleActiveStatus(pack.id, !pack.isActive);

      await AuditService.logPackAction(
        action: pack.isActive ? 'Deactivated Pack' : 'Activated Pack',
        packId: pack.id,
        packName: pack.name,
        details: pack.isActive
            ? 'Pack deactivated by admin'
            : 'Pack activated by admin',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pack ${pack.isActive ? "deactivated" : "activated"} successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePack(AssistancePack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pack'),
        content: Text(
          'Are you sure you want to delete "${pack.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AssistancePackService.deletePack(pack.id);

        await AuditService.logPackAction(
          action: 'Deleted Pack',
          packId: pack.id,
          packName: pack.name,
          details: 'Pack permanently deleted by admin',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pack deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
