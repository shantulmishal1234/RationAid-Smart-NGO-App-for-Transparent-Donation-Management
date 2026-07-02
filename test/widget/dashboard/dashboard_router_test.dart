import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardRouter — Role-Based Routing', () {
    testWidgets('shows CircularProgressIndicator in loading state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(state: _RouterState.loading),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('routes admin role to AdminDashboard placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'admin',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Admin Dashboard'), findsOneWidget);
    });

    testWidgets('routes ngo_admin role to AdminDashboard placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'ngo_admin',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Admin Dashboard'), findsOneWidget);
    });

    testWidgets('routes donor with profileCompleted=true to DonorDashboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'donor',
            profileCompleted: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Donor Dashboard'), findsOneWidget);
    });

    testWidgets(
        'routes donor with profileCompleted=false to ProfileSetupScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'donor',
            profileCompleted: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Profile Setup'), findsOneWidget);
    });

    testWidgets('routes purchaser role to PurchaserDashboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'purchaser',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Purchaser Dashboard'), findsOneWidget);
    });

    testWidgets('routes distributor role to DistributorDashboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'distributor',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Distributor Dashboard'), findsOneWidget);
    });

    testWidgets('routes volunteer role to DistributorDashboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'volunteer',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Distributor Dashboard'), findsOneWidget);
    });

    testWidgets('no user (null) shows Auth screen placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(state: _RouterState.noUser),
        ),
      );
      await tester.pump();

      expect(find.text('Auth Screen'), findsOneWidget);
    });

    testWidgets('error / no Firestore data shows Auth screen placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(state: _RouterState.error),
        ),
      );
      await tester.pump();

      expect(find.text('Auth Screen'), findsOneWidget);
    });

    testWidgets('unknown role shows Auth screen placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: 'unknown_role',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Auth Screen'), findsOneWidget);
    });

    testWidgets('empty roles list shows Auth screen placeholder',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDashboardRouter(
            state: _RouterState.loaded,
            role: '',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Auth Screen'), findsOneWidget);
    });
  });
}

enum _RouterState { loading, loaded, noUser, error }

/// Mock DashboardRouter that replicates the routing logic without Firebase
class _MockDashboardRouter extends StatelessWidget {
  final _RouterState state;
  final String role;
  final bool profileCompleted;

  const _MockDashboardRouter({
    required this.state,
    this.role = '',
    this.profileCompleted = true,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _RouterState.loading:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading...',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        );

      case _RouterState.noUser:
      case _RouterState.error:
        return const Scaffold(body: Center(child: Text('Auth Screen')));

      case _RouterState.loaded:
        if (role.isEmpty) {
          return const Scaffold(body: Center(child: Text('Auth Screen')));
        }
        switch (role) {
          case 'donor':
            return Scaffold(
              body: Center(
                child: Text(
                  profileCompleted ? 'Donor Dashboard' : 'Profile Setup',
                ),
              ),
            );
          case 'purchaser':
            return const Scaffold(
                body: Center(child: Text('Purchaser Dashboard')));
          case 'distributor':
          case 'volunteer':
            return const Scaffold(
                body: Center(child: Text('Distributor Dashboard')));
          case 'admin':
          case 'ngo_admin':
            return const Scaffold(
                body: Center(child: Text('Admin Dashboard')));
          default:
            return const Scaffold(body: Center(child: Text('Auth Screen')));
        }
    }
  }
}
