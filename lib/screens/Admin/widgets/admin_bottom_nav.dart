import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Premium animated navigation bar for Admin with glassmorphism and sliding indicator
class AdminBottomNav extends StatefulWidget {
  final AdminSection currentSection;
  final ValueChanged<AdminSection> onSectionChanged;
  final VoidCallback onMoreTapped;

  const AdminBottomNav({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
    required this.onMoreTapped,
  });

  @override
  State<AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends State<AdminBottomNav>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bounceAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 20),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.1), weight: 20),
          TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 30),
        ]).animate(
          CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
        );
  }

  @override
  void didUpdateWidget(AdminBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSection != widget.currentSection) {
      _slideController.forward(from: 0);
      _bounceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  int _getSectionIndex(AdminSection section) {
    switch (section) {
      case AdminSection.dashboard:
        return 0;
      case AdminSection.households:
        return 1;
      case AdminSection.donations:
        return 2;
      case AdminSection.hrm:
        return 3;
      default:
        return -1; // For sections in floating menu
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getSectionIndex(widget.currentSection);
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 32;
    final itemWidth = barWidth / 5;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Container(
        height: 75,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AdminColors.primaryBlue.withValues(alpha: 0.2),
              blurRadius: 25,
              offset: const Offset(0, 10),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  // Animated sliding indicator (only for nav items, not More)
                  if (currentIndex >= 0)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      left: currentIndex * itemWidth + itemWidth * 0.15,
                      top: 10,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: itemWidth * 0.7,
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AdminColors.primaryBlue,
                              AdminColors.primaryBlue.withValues(alpha: 0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AdminColors.primaryBlue.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Navigation items
                  Row(
                    children: [
                      _buildNavItem(
                        icon: Icons.dashboard_rounded,
                        label: 'Dashboard',
                        index: 0,
                        section: AdminSection.dashboard,
                        itemWidth: itemWidth,
                      ),
                      _buildNavItem(
                        icon: Icons.family_restroom,
                        label: 'Households',
                        index: 1,
                        section: AdminSection.households,
                        itemWidth: itemWidth,
                      ),
                      _buildNavItem(
                        icon: Icons.volunteer_activism,
                        label: 'Donations',
                        index: 2,
                        section: AdminSection.donations,
                        itemWidth: itemWidth,
                      ),
                      _buildNavItem(
                        icon: Icons.group,
                        label: 'HRM',
                        index: 3,
                        section: AdminSection.hrm,
                        itemWidth: itemWidth,
                      ),
                      _buildMoreButton(itemWidth),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required AdminSection section,
    required double itemWidth,
  }) {
    final isActive = widget.currentSection == section;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onSectionChanged(section),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: itemWidth,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: isActive ? _bounceAnimation.value : 1.0,
                    child: Icon(
                      icon,
                      color: isActive
                          ? Colors.white
                          : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      size: 24,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreButton(double itemWidth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: widget.onMoreTapped,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: itemWidth,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                'More',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
