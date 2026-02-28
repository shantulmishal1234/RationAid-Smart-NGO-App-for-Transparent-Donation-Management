import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/screens/dashboard_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ration_aid/screens/Startup & Authentication/Onboarding_Screen.dart';
import 'package:ration_aid/screens/Startup%20&%20Authentication/auth_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeLogo;
  late Animation<double> _fadeText;
  late Animation<Offset> _slideText;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeLogo = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    );

    _fadeText = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1.0, curve: Curves.easeInOut),
    );

    _slideText = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
          ),
        );

    _controller.forward();

    // Check authentication and navigate
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Step 1: Check if user has seen onboarding
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    // Step 2: Check if user is logged in
    final user = FirebaseAuth.instance.currentUser;

    Widget nextScreen;

    if (!hasSeenOnboarding) {
      // ✅ First time user → Show onboarding
      nextScreen = const OnboardingScreen();
    } else if (user != null) {
      // ✅ Returning user who is logged in → Go to dashboard
      nextScreen = const DashboardRouter();
    } else {
      // ✅ Returning user but not logged in → Go to auth screen
      nextScreen = const AuthScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                : [const Color(0xFF1E88E5), const Color(0xFF26A69A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _fadeLogo,
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    width: 200,
                    height: 200,
                  ),
                ),
                const SizedBox(height: 20),
                SlideTransition(
                  position: _slideText,
                  child: FadeTransition(
                    opacity: _fadeText,
                    child: Text(
                      'Connecting Help with Need',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Optional: Loading indicator
                FadeTransition(
                  opacity: _fadeText,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
