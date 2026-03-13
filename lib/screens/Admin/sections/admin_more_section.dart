import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

class AdminMoreSection extends StatelessWidget {
  final ValueChanged<AdminSection> onSectionChanged;

  const AdminMoreSection({super.key, required this.onSectionChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final categories = [
      {
        'title': 'Verification & Approvals',
        'items': [
          {
            'icon': Icons.gavel,
            'label': 'Final Approval',
            'section': AdminSection.finalApproval,
            'color': Colors.cyan,
            'desc': 'Approve/Reject Families',
          },
          {
            'icon': Icons.shopping_bag,
            'label': 'Purchase Approval',
            'section': AdminSection.purchaseApproval,
            'color': Colors.deepPurple,
            'desc': 'Review Vendor Bids',
          },
          {
            'icon': Icons.delivery_dining,
            'label': 'Delivery Management',
            'section': AdminSection.deliveryVerification,
            'color': Colors.orangeAccent,
            'desc': 'Verify Distributions',
          },
        ],
      },
      {
        'title': 'Logistics & Inventory',
        'items': [
          {
            'icon': Icons.inventory_2,
            'label': 'Assistance Packs',
            'section': AdminSection.assistancePacks,
            'color': Colors.purple,
            'desc': 'Manage Ration Templates',
          },
          {
            'icon': Icons.warning_amber_rounded,
            'label': 'Inventory Issues',
            'section': AdminSection.inventoryIssues,
            'color': Colors.pink,
            'desc': 'Resolve Discrepancies',
          },
        ],
      },
      {
        'title': 'Analytics & Auditing',
        'items': [
          {
            'icon': Icons.bar_chart_rounded,
            'label': 'Reports',
            'section': AdminSection.reports,
            'color': Colors.orange,
            'desc': 'Generate Metrics',
          },
          {
            'icon': Icons.receipt_long,
            'label': 'Audit Trail',
            'section': AdminSection.audit,
            'color': Colors.deepPurpleAccent,
            'desc': 'System Action Logs',
          },
        ],
      },
      {
        'title': 'System & Personal',
        'items': [
          {
            'icon': Icons.person_outline,
            'label': 'Profile',
            'section': AdminSection.profile,
            'color': Colors.blue,
            'desc': 'Admin Settings',
          },
        ],
      },
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administrative Modules',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Access additional tools and specialized hubs.',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...categories.map((cat) {
            final items = cat['items'] as List<Map<String, dynamic>>;
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 12),
                      child: Text(
                        cat['title'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white70
                              : AppColors.primaryBlue.withValues(alpha: 0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _buildSmartGrid(context, items, isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          }),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }

  Widget _buildSmartGrid(
    BuildContext context,
    List<Map<String, dynamic>> items,
    bool isDark,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 2) {
      if (i + 1 < items.length) {
        // Render 2 items in a row
        rows.add(
          Row(
            children: [
              Expanded(child: _buildModuleCard(context, items[i], isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildModuleCard(context, items[i + 1], isDark)),
            ],
          ),
        );
      } else {
        // Odd item at the end expands full width
        rows.add(
          Row(
            children: [
              Expanded(child: _buildModuleCard(context, items[i], isDark)),
            ],
          ),
        );
      }
      if (i + 2 < items.length) {
        rows.add(const SizedBox(height: 12));
      }
    }

    return Column(children: rows);
  }

  Widget _buildModuleCard(
    BuildContext context,
    Map<String, dynamic> item,
    bool isDark,
  ) {
    final Color color = item['color'];
    final IconData icon = item['icon'];
    final String label = item['label'];
    final String desc = item['desc'];
    final AdminSection section = item['section'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSectionChanged(section),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black26
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
