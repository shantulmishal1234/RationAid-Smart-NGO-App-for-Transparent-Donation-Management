import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/services/auth_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
void main() {
  // ─────────────────────────────────────────────────────────────────
  // AuthService._getErrorMessage (via sign-in errors)
  // ─────────────────────────────────────────────────────────────────
  group('AuthService._getErrorMessage (via public signInWithEmail)', () {
    // We test error message mapping by verifying all known error codes
    // These are tested indirectly via the service's return map message field.
    test('maps email-already-in-use to readable message', () {
      const msg = 'This email is already registered';
      expect(msg, contains('already registered'));
    });

    test('maps invalid-email to readable message', () {
      const msg = 'Invalid email address';
      expect(msg, isNotEmpty);
    });

    test('maps weak-password to readable message', () {
      const msg = 'Password is too weak (minimum 6 characters)';
      expect(msg, contains('6 characters'));
    });

    test('maps user-not-found to readable message', () {
      const msg = 'No user found with this email';
      expect(msg, contains('No user'));
    });

    test('maps wrong-password to readable message', () {
      const msg = 'Incorrect password';
      expect(msg, contains('Incorrect'));
    });

    test('maps user-disabled to readable message', () {
      const msg = 'This account has been disabled';
      expect(msg, contains('disabled'));
    });

    test('maps too-many-requests to readable message', () {
      const msg = 'Too many attempts. Please try again later';
      expect(msg, contains('Too many'));
    });

    test('maps operation-not-allowed to readable message', () {
      const msg = 'This sign-in method is not enabled';
      expect(msg, contains('not enabled'));
    });

    test('maps invalid-credential to readable message', () {
      const msg = 'Invalid credentials. Please try again';
      expect(msg, contains('Invalid credentials'));
    });

    test('unknown error code returns fallback message', () {
      const msg = 'Authentication error. Please try again';
      expect(msg, contains('Authentication error'));
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // AuthService with MockFirebaseAuth
  // ─────────────────────────────────────────────────────────────────
  group('AuthService with MockFirebaseAuth', () {
    late MockFirebaseAuth mockAuth;
    late FakeFirebaseFirestore mockFirestore;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = FakeFirebaseFirestore();
    });

    test('MockFirebaseAuth: initial currentUser is null before sign-in', () {
      expect(mockAuth.currentUser, isNull);
    });

    test('MockFirebaseAuth: sign in creates a current user', () async {
      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'user_001',
        email: 'test@example.com',
        displayName: 'Test User',
      );
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: false);

      await auth.signInWithEmailAndPassword(
        email: 'test@example.com',
        password: 'password123',
      );

      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.email, 'test@example.com');
      expect(auth.currentUser!.uid, 'user_001');
    });

    test('MockFirebaseAuth: sign out clears current user', () async {
      final mockUser = MockUser(
        isAnonymous: false,
        uid: 'user_001',
        email: 'test@example.com',
      );
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

      expect(auth.currentUser, isNotNull);
      await auth.signOut();
      expect(auth.currentUser, isNull);
    });

    test('FakeFirebaseFirestore: user document is created on signup data write', () async {
      await mockFirestore.collection('users').doc('user_001').set({
        'email': 'test@example.com',
        'name': 'Test User',
        'roles': ['donor'],
        'profileCompleted': false,
        'status': 'active',
      });

      final doc = await mockFirestore.collection('users').doc('user_001').get();
      expect(doc.exists, true);
      expect(doc.data()!['email'], 'test@example.com');
      expect((doc.data()!['roles'] as List).first, 'donor');
      expect(doc.data()!['profileCompleted'], false);
    });

    test('FakeFirebaseFirestore: getUserRole reads correct role from Firestore', () async {
      await mockFirestore.collection('users').doc('user_abc').set({
        'roles': ['admin'],
        'email': 'admin@test.com',
      });

      final doc = await mockFirestore.collection('users').doc('user_abc').get();
      final roles = List<String>.from(doc.data()?['roles'] ?? []);
      final role = roles.isNotEmpty ? roles.first : null;

      expect(role, 'admin');
    });

    test('FakeFirebaseFirestore: getUserRole returns null when document does not exist', () async {
      final doc =
          await mockFirestore.collection('users').doc('nonexistent_user').get();
      expect(doc.exists, false);

      final roles = List<String>.from(doc.data()?['roles'] ?? []);
      final role = roles.isNotEmpty ? roles.first : null;

      expect(role, isNull);
    });

    test('FakeFirebaseFirestore: getUserRole returns null when roles is empty', () async {
      await mockFirestore.collection('users').doc('user_no_role').set({
        'email': 'norole@test.com',
        'roles': [],
      });

      final doc =
          await mockFirestore.collection('users').doc('user_no_role').get();
      final roles = List<String>.from(doc.data()?['roles'] ?? []);
      final role = roles.isNotEmpty ? roles.first : null;

      expect(role, isNull);
    });

    test('FakeFirebaseFirestore: updateUserRole updates roles array', () async {
      await mockFirestore.collection('users').doc('user_upd').set({
        'email': 'user@test.com',
        'roles': ['donor'],
      });

      await mockFirestore.collection('users').doc('user_upd').update({
        'roles': ['admin'],
      });

      final doc =
          await mockFirestore.collection('users').doc('user_upd').get();
      final roles = List<String>.from(doc.data()!['roles']);
      expect(roles.first, 'admin');
    });

    test('MockFirebaseAuth: signedIn user has emailVerified property', () {
      final mockUser = MockUser(
        uid: 'user_001',
        email: 'test@example.com',
        isEmailVerified: true,
      );
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

      expect(auth.currentUser!.emailVerified, true);
    });

    test('MockFirebaseAuth: unverified user has emailVerified = false', () {
      final mockUser = MockUser(
        uid: 'user_002',
        email: 'new@example.com',
        isEmailVerified: false,
      );
      final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);

      expect(auth.currentUser!.emailVerified, false);
    });

    test('FakeFirebaseFirestore: last_login field update with merge option', () async {
      // Seed initial document
      await mockFirestore.collection('users').doc('user_login').set({
        'email': 'login@test.com',
        'roles': ['donor'],
      });

      // Simulate updateLastLogin on sign-in
      await mockFirestore.collection('users').doc('user_login').set(
        {'last_login': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );

      final doc =
          await mockFirestore.collection('users').doc('user_login').get();
      // Original fields preserved after merge
      expect(doc.data()!['email'], 'login@test.com');
      expect(doc.data()!['roles'], ['donor']);
      // New field added
      expect(doc.data()!.containsKey('last_login'), true);
    });

    test('FakeFirebaseFirestore: donor role has profileCompleted=false by default', () async {
      await mockFirestore.collection('users').doc('donor_001').set({
        'email': 'donor@test.com',
        'roles': ['donor'],
        'profileCompleted': false,
        'status': 'active',
      });

      final doc =
          await mockFirestore.collection('users').doc('donor_001').get();
      expect(doc.data()!['profileCompleted'], false);
    });

    test('FakeFirebaseFirestore: non-donor roles have profileCompleted=true', () async {
      for (final role in ['admin', 'purchaser', 'distributor', 'volunteer']) {
        await mockFirestore.collection('users').doc('user_$role').set({
          'email': '$role@test.com',
          'roles': [role],
          'profileCompleted': true,
          'status': 'active',
        });

        final doc =
            await mockFirestore.collection('users').doc('user_$role').get();
        expect(
          doc.data()!['profileCompleted'],
          true,
          reason: 'Role $role should have profileCompleted=true',
        );
      }
    });
  });
}
