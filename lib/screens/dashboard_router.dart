import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ration_aid/screens/Admin/admin_dashboard.dart';
import 'package:ration_aid/screens/Startup%20&%20Authentication/auth_screen.dart';
import 'package:ration_aid/screens/donor_dashboard.dart';
import 'package:ration_aid/screens/Donor/profile_setup_screen.dart';
import 'package:ration_aid/screens/purchaser_dashboard.dart';
import 'package:ration_aid/screens/volunteer_dashboard.dart';

class DashboardRouter extends StatefulWidget {
  const DashboardRouter({super.key});

  @override
  State<DashboardRouter> createState() => _DashboardRouterState();
}

class _DashboardRouterState extends State<DashboardRouter> {
  Future<DocumentSnapshot>? _userFuture;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null) {
      _userFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // If no user logged in, go to auth screen
    if (user == null) {
      return const AuthScreen();
    }

    // Refresh future if user changed (unlikely here but safe)
    if (_currentUser?.uid != user.uid) {
      _currentUser = user;
      _userFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    }

    // Fetch user data from Firestore and route based on role
    return FutureBuilder<DocumentSnapshot>(
      future: _userFuture,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        // Error or no data
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const AuthScreen();
        }

        // Get user data
        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final roles = List<String>.from(userData['roles'] ?? []);

        // No role assigned
        if (roles.isEmpty) {
          return const AuthScreen();
        }

        // Route based on first role in array
        switch (roles.first) {
          case 'donor':
            // Check if donor has completed profile setup
            final profileCompleted = userData['profileCompleted'] ?? false;
            if (!profileCompleted) {
              return const ProfileSetupScreen();
            }
            return const DonorDashboard();
          case 'purchaser':
            return const PurchaserDashboard();
          case 'distributor':
            return const VolunteerDashboard();
          case 'volunteer':
            return const VolunteerDashboard();
          case 'admin':
          case 'ngo_admin':
            return const AdminDashboard();
          default:
            return const AuthScreen();
        }
      },
    );
  }
}
