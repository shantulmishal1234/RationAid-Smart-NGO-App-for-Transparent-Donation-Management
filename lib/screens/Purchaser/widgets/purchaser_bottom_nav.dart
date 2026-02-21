import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Premium animated navigation bar for Purchaser
class PurchaserBottomNav extends StatefulWidget {
  final PurchaserSection currentSection;
  final ValueChanged<PurchaserSection> onSectionChanged;

  /// If > 0, a red badge is shown over the Notifications tab.
  final int unreadNotificationCount;

  const PurchaserBottomNav({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
    this.unreadNotificationCount = 0,
  });

  @override
  State<PurchaserBottomNav> createState() => _PurchaserBottomNavState();
}

class _PurchaserBottomNavState extends State<PurchaserBottomNav>
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
  void didUpdateWidget(PurchaserBottomNav oldWidget) {
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

  int _getSectionIndex(PurchaserSection section) {
    switch (section) {
      case PurchaserSection.dashboard:
        return 0;
      case PurchaserSection.procurement:
        return 1;
      case PurchaserSection.inventory:
        return 2;
      case PurchaserSection.history:
        return 3;
      case PurchaserSection.reports:
        return 4;
      case PurchaserSection.notifications:
        return 5;
      case PurchaserSection.profile:
        return 6;
    }
  }

  double _getAdjustedNotchX(int index, double itemWidth, double barWidth) {
    if (index < 0) return -100;
    double x = index * itemWidth + (itemWidth / 2);
    const notchW = 35.0;
    const buffer = 10.0;
    const minX = notchW + buffer;
    final maxX = barWidth - minX;
    return x.clamp(minX, maxX);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getSectionIndex(widget.currentSection);
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 32;
    final itemWidth = barWidth / 7; // divided by 7 items
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final adjustedNotchX = _getAdjustedNotchX(
      currentIndex,
      itemWidth,
      barWidth,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        height: 85,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Floating Indicator Dot
            if (currentIndex >= 0)
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                tween: Tween<double>(begin: 0, end: adjustedNotchX),
                builder: (context, x, child) {
                  return Positioned(
                    top: 0,
                    left: x - 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.purchaserOrange,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.purchaserOrange,
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            // Notched Background
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutCubic,
                tween: Tween<double>(begin: 0, end: adjustedNotchX),
                builder: (context, notchX, child) {
                  return CustomPaint(
                    size: Size(barWidth, 75),
                    painter: NotchedBarPainter(
                      notchX: notchX,
                      color: isDark
                          ? const Color(0xFF1E1E1E).withOpacity(0.95)
                          : Colors.white.withOpacity(0.95),
                      isDark: isDark,
                    ),
                    child: child,
                  );
                },
                child: Container(
                  height: 75,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem(
                        icon: Icons.dashboard_outlined,
                        label: 'Home',
                        section: PurchaserSection.dashboard,
                        index: 0,
                      ),
                      _buildNavItem(
                        icon: Icons.shopping_cart_outlined,
                        label: 'Buy',
                        section: PurchaserSection.procurement,
                        index: 1,
                      ),
                      _buildNavItem(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stock',
                        section: PurchaserSection.inventory,
                        index: 2,
                      ),
                      _buildNavItem(
                        icon: Icons.history_edu_outlined, // History icon
                        label: 'History',
                        section: PurchaserSection.history,
                        index: 3,
                      ),
                      _buildNavItem(
                        icon: Icons.analytics_outlined,
                        label: 'Reports',
                        section: PurchaserSection.reports,
                        index: 4,
                      ),
                      _buildNavItem(
                        icon: Icons.notifications_outlined,
                        label: 'Alerts',
                        section: PurchaserSection.notifications,
                        index: 5,
                        badgeCount: widget.unreadNotificationCount,
                      ),
                      _buildNavItem(
                        icon: Icons.person_outline,
                        label: 'Profile',
                        section: PurchaserSection.profile,
                        index: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required PurchaserSection section,
    required int index,
    int badgeCount = 0,
  }) {
    final isActive = widget.currentSection == section;
    final currentIndex = _getSectionIndex(widget.currentSection);

    return Expanded(
      child: GestureDetector(
        onTap: () => widget.onSectionChanged(section),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 75,
          padding: const EdgeInsets.only(top: 15, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _bounceAnimation,
                builder: (context, child) {
                  final scale = (isActive && index == currentIndex)
                      ? _bounceAnimation.value
                      : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            icon,
                            color: isActive
                                ? AppColors.purchaserOrange
                                : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey[400]
                                      : Colors.grey[600]),
                            size: isActive ? 26 : 24,
                          ),
                        ),
                        // Unread badge
                        if (badgeCount > 0)
                          Positioned(
                            top: -4,
                            right: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                badgeCount > 99 ? '99+' : '$badgeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: isActive ? 10.5 : 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.purchaserOrange
                      : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600]),
                  letterSpacing: isActive ? 0.3 : 0,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotchedBarPainter extends CustomPainter {
  final double notchX;
  final Color color;
  final bool isDark;

  NotchedBarPainter({
    required this.notchX,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    const r = 20.0;
    const notchW = 35.0;
    const notchH = 18.0;

    final baseBarPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          const Radius.circular(r),
        ),
      );

    final notchPath = Path();
    if (notchX > 0) {
      notchPath.moveTo(notchX - notchW, 0);
      notchPath.cubicTo(
        notchX - notchW * 0.4,
        0,
        notchX - notchW * 0.5,
        notchH,
        notchX,
        notchH,
      );
      notchPath.cubicTo(
        notchX + notchW * 0.5,
        notchH,
        notchX + notchW * 0.4,
        0,
        notchX + notchW,
        0,
      );
      notchPath.lineTo(notchX + notchW, -10);
      notchPath.lineTo(notchX - notchW, -10);
      notchPath.close();
    }

    final finalPath = Path.combine(
      PathOperation.difference,
      baseBarPath,
      notchPath,
    );

    canvas.drawShadow(
      finalPath,
      Colors.black.withOpacity(isDark ? 0.5 : 0.1),
      15,
      false,
    );
    canvas.drawPath(finalPath, paint);

    final borderPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.1)
          : Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(finalPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant NotchedBarPainter oldDelegate) {
    return oldDelegate.notchX != notchX ||
        oldDelegate.color != color ||
        oldDelegate.isDark != isDark;
  }
}
