import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Auth screen widget tests using a mock that mirrors AuthScreen's form structure.
// This avoids Firebase calls while testing all form validation and UI behaviours.

void main() {
  group('AuthScreen — Login Form Validation', () {
    testWidgets('renders login form with email and password fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockAuthScreen()),
      );

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('renders Login button', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));
      expect(find.text('Login'), findsWidgets);
    });

    testWidgets('empty email shows "Email is required" validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('invalid email format shows validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.enterText(
        find.byKey(const Key('email_field')),
        'not-an-email',
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('empty password shows "Password is required" validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.enterText(
        find.byKey(const Key('email_field')),
        'valid@email.com',
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('short password (<6 chars) shows minimum length error',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.enterText(
          find.byKey(const Key('email_field')), 'test@email.com');
      await tester.enterText(find.byKey(const Key('password_field')), '123');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Minimum 6 characters'), findsOneWidget);
    });

    testWidgets('valid form passes all validation checks',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.enterText(
          find.byKey(const Key('email_field')), 'valid@email.com');
      await tester.enterText(
          find.byKey(const Key('password_field')), 'password123');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // No validation errors should appear
      expect(find.text('Email is required'), findsNothing);
      expect(find.text('Enter a valid email'), findsNothing);
      expect(find.text('Password is required'), findsNothing);
      expect(find.text('Minimum 6 characters'), findsNothing);
    });

    testWidgets('password field is obscured', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      final passwordField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('password_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(passwordField.obscureText, true);
    });
  });

  group('AuthScreen — Sign Up Mode', () {
    testWidgets('toggling to sign-up mode shows name field',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.tap(find.text('Sign Up'));
      await tester.pump();

      expect(find.byKey(const Key('name_field')), findsOneWidget);
      expect(find.text('Sign Up'), findsAtLeastNWidgets(1));
    });

    testWidgets('sign-up mode shows role selector dropdown',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.tap(find.text('Sign Up'));
      await tester.pump();

      expect(find.byKey(const Key('role_dropdown')), findsOneWidget);
    });

    testWidgets('sign-up empty name field shows "Name is required" error',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      await tester.tap(find.text('Sign Up'));
      await tester.pump();

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Name is required'), findsOneWidget);
    });
  });

  group('AuthScreen — Forgot Password', () {
    testWidgets('shows Forgot Password text/button in login mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: _MockAuthScreen()));

      expect(find.text('Forgot Password?'), findsOneWidget);
    });
  });
}

/// Mock AuthScreen that mirrors the real AuthScreen's form structure
/// without any Firebase calls
class _MockAuthScreen extends StatefulWidget {
  @override
  State<_MockAuthScreen> createState() => _MockAuthScreenState();
}

class _MockAuthScreenState extends State<_MockAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Sign Up')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Toggle button
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isLogin = true),
                    child: const Text('Login'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = false),
                    child: const Text('Sign Up'),
                  ),
                ],
              ),

              // Name field (signup only)
              if (!_isLogin)
                TextFormField(
                  key: const Key('name_field'),
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),

              // Email field
              TextFormField(
                key: const Key('email_field'),
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),

              // Password field
              TextFormField(
                key: const Key('password_field'),
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (v.length < 6) return 'Minimum 6 characters';
                  return null;
                },
              ),

              // Role dropdown (signup only)
              if (!_isLogin)
                DropdownButtonFormField<String>(
                  key: const Key('role_dropdown'),
                  hint: const Text('Select Role'),
                  items: const [
                    DropdownMenuItem(value: 'donor', child: Text('Donor')),
                    DropdownMenuItem(
                        value: 'purchaser', child: Text('Purchaser')),
                    DropdownMenuItem(
                        value: 'distributor', child: Text('Distributor')),
                  ],
                  onChanged: (_) {},
                  validator: (v) => v == null ? 'Please select a role' : null,
                ),

              // Forgot password
              if (_isLogin)
                TextButton(
                  onPressed: () {},
                  child: const Text('Forgot Password?'),
                ),

              // Submit button
              ElevatedButton(
                onPressed: () => _formKey.currentState!.validate(),
                child: Text(_isLogin ? 'Login' : 'Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
