import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Floating action menu with Samsung S Pen style animation
class FloatingActionMenu extends StatefulWidget {
  final VoidCallback onDismiss;
  final ValueChanged<AdminSection> onSectionChanged;

  const FloatingActionMenu({
    super.key,
    required this.onDismiss,
    required this.onSectionChanged,
  });

  @override
  State<FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _backdropAnimation;
  late List<Animation<double>> _itemAnimations;

  final List<Map<String, dynamic>> _menuItems = [
    {
      'icon': Icons.gavel,
      'label': 'Final Approval',
      'section': AdminSection.finalApproval,
      'color': const Color(0xFF00BCD4),
    },
    {
      'icon': Icons.inventory_2,
      'label': 'Assistance Packs',
      'section': AdminSection.assistancePacks,
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.bar_chart_rounded,
      'label': 'Reports',
      'section': AdminSection.reports,
      'color': const Color(0xFFFF9800),
    },
    {
      'icon': Icons.notifications,
      'label': 'Notifications',
      'section': AdminSection.notifications,
      'color': const Color(0xFFF44336),
    },
    {
      'icon': Icons.receipt_long,
      'label': 'Audit Trail',
      'section': AdminSection.audit,
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.person_outline,
      'label': 'Profile',
      'section': AdminSection.profile,
      'color': const Color(0xFF2196F3),
    },
    {
      'icon': Icons.shopping_bag,
      'label': 'Purchase Approval',
      'section': AdminSection.purchaseApproval,
      'color': const Color(0xFF673AB7),
    },
    {
      'icon': Icons.delivery_dining,
      'label': 'Delivery Management',
      'section': AdminSection.deliveryVerification,
      'color': const Color(0xFFFF5722),
    },
    {
      'icon': Icons.warning_amber_rounded,
      'label': 'Inventory Issues',
      'section': AdminSection.inventoryIssues,
      'color': const Color(0xFFE91E63),
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _backdropAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _itemAnimations = List.generate(
      _menuItems.length,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.05,
            0.5 + (index * 0.05),
            curve: Curves.elasticOut,
          ),
        ),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() async {
    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  void _handleItemTap(AdminSection section) async {
    await _controller.reverse();
    if (mounted) {
      widget.onSectionChanged(section);
      // widget.onDismiss(); // Redundant as onSectionChanged closes the menu
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: _handleDismiss,
      child: AnimatedBuilder(
        animation: _backdropAnimation,
        builder: (context, child) {
          return Container(
            color: Colors.black.withValues(alpha: _backdropAnimation.value * 0.5),
            child: Stack(
              children: [
                // Menu items floating from bottom-right
                Positioned(
                  bottom: 100,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(_menuItems.length, (index) {
                      final reversedIndex = _menuItems.length - 1 - index;
                      final item = _menuItems[reversedIndex];
                      return AnimatedBuilder(
                        animation: _itemAnimations[reversedIndex],
                        builder: (context, child) {
                          final animation = _itemAnimations[reversedIndex];
                          return Transform.translate(
                            offset: Offset(
                              (1 - animation.value) * 100,
                              (1 - animation.value) * 50,
                            ),
                            child: Opacity(
                              opacity: animation.value.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: animation.value,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _buildMenuItem(
                                    icon: item['icon'],
                                    label: item['label'],
                                    color: item['color'],
                                    section: item['section'],
                                    isDark: isDark,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required AdminSection section,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => _handleItemTap(section),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Icon bubble
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handleItemTap(section),
                borderRadius: BorderRadius.circular(28),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
