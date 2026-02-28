import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// A reusable Scaffold wrapper for Donor screens that handles:
/// - Automatic Dark Mode background gradients
/// - Consistent AppBar styling
/// - Safe Area handling
class DonorScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? bottomNavigationBar;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showBackButton;
  final bool useSafeArea;
  final PreferredSizeWidget? appBarBottom;

  const DonorScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomNavigationBar,
    this.actions,
    this.floatingActionButton,
    this.showBackButton = true,
    this.useSafeArea = true,
    this.appBarBottom,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: showBackButton,
        titleSpacing: showBackButton ? 0 : 20,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.donorGreen : Colors.white,
          ),
        ),
        actions: actions,
        bottom: appBarBottom,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      AppColors.donorGreen.withValues(alpha: 0.1),
                      AppColors.donorGreen.withValues(alpha: 0.05),
                    ]
                  : [AppColors.donorGreen, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: isDark
                ? Border(
                    bottom: BorderSide(
                      color: AppColors.donorGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  )
                : null,
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)],
          ),
        ),
        child: useSafeArea ? SafeArea(bottom: false, child: body) : body,
      ),
    );
  }
}
