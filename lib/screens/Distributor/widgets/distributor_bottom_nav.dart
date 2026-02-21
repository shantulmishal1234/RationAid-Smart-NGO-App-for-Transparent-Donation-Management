import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';

enum DistributorSection { deliveries, performance, profile }

/// Premium animated bottom navigation bar for Distributor
class DistributorBottomNav extends StatefulWidget {
  final DistributorSection currentSection;
  final ValueChanged<DistributorSection> onSectionChanged;

  const DistributorBottomNav({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
  });

  @override
  State<DistributorBottomNav> createState() => _DistributorBottomNavState();
}

class _DistributorBottomNavState extends State<DistributorBottomNav>
    with TickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
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
  void didUpdateWidget(DistributorBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSection != widget.currentSection) {
      _bounceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  int get _currentIndex {
    switch (widget.currentSection) {
      case DistributorSection.deliveries:
        return 0;
      case DistributorSection.performance:
        return 1;
      case DistributorSection.profile:
        return 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex;
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 32;
    final itemWidth = barWidth / 3;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final notchX = currentIndex * itemWidth + itemWidth / 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: SizedBox(
        height: 85,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Floating Indicator Dot
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              tween: Tween<double>(begin: 0, end: notchX),
              builder: (context, x, _) {
                return Positioned(
                  top: 0,
                  left: x - 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.volunteerBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.volunteerBlue,
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
                tween: Tween<double>(begin: 0, end: notchX),
                builder: (context, nx, child) {
                  return CustomPaint(
                    size: Size(barWidth, 75),
                    painter: _NotchedBarPainter(
                      notchX: nx,
                      color: isDark
                          ? const Color(0xFF1E1E1E).withOpacity(0.95)
                          : Colors.white.withOpacity(0.95),
                      isDark: isDark,
                      accentColor: AppColors.volunteerBlue,
                    ),
                    child: child,
                  );
                },
                child: SizedBox(
                  height: 75,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _navItem(
                        icon: Icons.local_shipping_outlined,
                        label: 'Deliveries',
                        section: DistributorSection.deliveries,
                        index: 0,
                      ),
                      _navItem(
                        icon: Icons.bar_chart_outlined,
                        label: 'Performance',
                        section: DistributorSection.performance,
                        index: 1,
                      ),
                      _navItem(
                        icon: Icons.person_outline,
                        label: 'Profile',
                        section: DistributorSection.profile,
                        index: 2,
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

  Widget _navItem({
    required IconData icon,
    required String label,
    required DistributorSection section,
    required int index,
  }) {
    final isActive = widget.currentSection == section;

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
                  final scale = (isActive && index == _currentIndex)
                      ? _bounceAnimation.value
                      : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Icon(
                      icon,
                      color: isActive
                          ? AppColors.volunteerBlue
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[400]
                                : Colors.grey[600]),
                      size: isActive ? 26 : 24,
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
                      ? AppColors.volunteerBlue
                      : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600]),
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

class _NotchedBarPainter extends CustomPainter {
  final double notchX;
  final Color color;
  final bool isDark;
  final Color accentColor;

  _NotchedBarPainter({
    required this.notchX,
    required this.color,
    required this.isDark,
    required this.accentColor,
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

    final basePath = Path()
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
      basePath,
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
  bool shouldRepaint(covariant _NotchedBarPainter old) =>
      old.notchX != notchX || old.color != color;
}
