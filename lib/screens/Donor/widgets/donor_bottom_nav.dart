import 'dart:ui';
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

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getSectionIndex(widget.currentSection);
    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = screenWidth - 32;
    final itemWidth = barWidth / 5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Container(
        height: 75,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.donorGreen.withValues(alpha: 0.2),
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  // Animated sliding indicator
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
                            AppColors.donorGreen,
                            AppColors.donorGreen.withValues(alpha: 0.85),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.donorGreen.withValues(alpha: 0.4),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Navigation items
                  Row(
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
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                            ? Colors.white
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
                  fontSize: isActive ? 11 : 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? Colors.white
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
