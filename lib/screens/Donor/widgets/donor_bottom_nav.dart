import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Donor/models/donor_enums.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Premium animated navigation bar with glassmorphism and sliding indicator
class DonorBottomNav extends StatefulWidget {
  final DonorSection currentSection;
  final ValueChanged<DonorSection> onSectionChanged;

  const DonorBottomNav({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
  });

  @override
  State<DonorBottomNav> createState() => _DonorBottomNavState();
}

class _DonorBottomNavState extends State<DonorBottomNav>
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
  void didUpdateWidget(DonorBottomNav oldWidget) {
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

  int _getSectionIndex(DonorSection section) {
    switch (section) {
      case DonorSection.dashboard:
        return 0;
      case DonorSection.exploreFamilies:
        return 1;
      case DonorSection.myDonations:
        return 2;
      case DonorSection.notifications:
        return 3;
      case DonorSection.profile:
        return 4;
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
    final itemWidth = barWidth / 5;
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
                        color: AppColors.donorGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.donorGreen,
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
                          ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.95),
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
                        icon: Icons.dashboard_rounded,
                        label: 'Home',
                        section: DonorSection.dashboard,
                        index: 0,
                      ),
                      _buildNavItem(
                        icon: Icons.explore_rounded,
                        label: 'Explore',
                        section: DonorSection.exploreFamilies,
                        index: 1,
                      ),
                      _buildNavItem(
                        icon: Icons.volunteer_activism_rounded,
                        label: 'Donations',
                        section: DonorSection.myDonations,
                        index: 2,
                      ),
                      _buildNavItem(
                        icon: Icons.notifications_rounded,
                        label: 'Activity',
                        section: DonorSection.notifications,
                        index: 3,
                      ),
                      _buildNavItem(
                        icon: Icons.person_rounded,
                        label: 'Profile',
                        section: DonorSection.profile,
                        index: 4,
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
    required DonorSection section,
    required int index,
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        icon,
                        color: isActive
                            ? AppColors.donorGreen
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[400]
                                  : Colors.grey[600]),
                        size: isActive ? 26 : 24,
                      ),
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
                      ? AppColors.donorGreen
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

/// Custom painter for the notched navigation bar background
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
    const r = 20.0; // Reduced corner radius for symmetry
    const notchW = 35.0; // Reduced notch width for symmetry
    const notchH = 18.0; // Notch depth

    // 1. Create the base bar path (rounded rectangle)
    final baseBarPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          const Radius.circular(r),
        ),
      );

    // 2. Create the notch "cutter" path
    final notchPath = Path();
    if (notchX > 0) {
      notchPath.moveTo(notchX - notchW, 0);
      // Refined fluid notch using improved cubic bezier control points
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
      notchPath.lineTo(notchX + notchW, -10); // Ensure it cuts the top edge
      notchPath.lineTo(notchX - notchW, -10);
      notchPath.close();
    }

    // 3. Combine paths: Base Bar - Notch
    final finalPath = Path.combine(
      PathOperation.difference,
      baseBarPath,
      notchPath,
    );

    // Draw shadow
    canvas.drawShadow(
      finalPath,
      Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
      15,
      false,
    );

    // Draw background
    canvas.drawPath(finalPath, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.5)
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
