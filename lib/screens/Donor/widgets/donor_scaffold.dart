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
                      AppColors.donorGreen.withOpacity(0.1),
                      AppColors.donorGreen.withOpacity(0.05),
                    ]
                  : [AppColors.donorGreen, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: isDark
                ? Border(
                    bottom: BorderSide(
                      color: AppColors.donorGreen.withOpacity(0.3),
                      width: 1.5,
                    ),
                  )
                : null,
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: useSafeArea ? SafeArea(child: body) : body,
    );
  }
}
