import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // ============================================
  // SIGN UP WITH EMAIL
  // ============================================
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String role,
  }) async {
    try {
      UserCredential userCred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCred.user!.updateDisplayName(name);

      await _firestore.collection('users').doc(userCred.user!.uid).set({
        'email': email,
        'phone': phone,
        'name': name,
        'display_name': name,
        'photo_url': null,
        'roles': [role],
        'workspace_id': null,
        'created_at': FieldValue.serverTimestamp(),
        'last_login': FieldValue.serverTimestamp(),
        'profile': {},
        'status': 'active',
        // Profile setup fields for donor onboarding
        'profileCompleted': role != 'donor', // Donors need to complete profile
        'profilePhotoUrl': null,
      });

      await userCred.user!.sendEmailVerification();

      return {
        'success': true,
        'message': 'Signup successful! Please verify your email.',
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {'success': false, 'message': 'Signup failed: ${e.toString()}'};
    }
  }

  // ============================================
  // SIGN IN WITH EMAIL
  // ============================================
  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Use set with merge to create document if it doesn't exist
      await _firestore.collection('users').doc(userCred.user!.uid).set({
        'last_login': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return {
        'success': true,
        'message': 'Login successful',
        'isVerified': userCred.user!.emailVerified,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  // ============================================
  // UPDATE USER ROLE
  // ============================================
  Future<Map<String, dynamic>> updateUserRole({
    required String userId,
    required String role,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'roles': [role],
      });

      return {'success': true, 'message': 'Role updated successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update role: ${e.toString()}',
      };
    }
  }

  // ============================================
  // RESEND VERIFICATION EMAIL
  // ============================================
  Future<Map<String, dynamic>> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        return {'success': false, 'message': 'No user logged in'};
      }

      if (user.emailVerified) {
        return {'success': false, 'message': 'Email already verified'};
      }

      await user.sendEmailVerification();

      return {
        'success': true,
        'message': 'Verification email sent! Check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send email: ${e.toString()}',
      };
    }
  }

  // ============================================
  // RESET PASSWORD
  // ============================================
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'message': 'Password reset email sent! Check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': _getErrorMessage(e.code)};
    } catch (e) {
      return {
        'success': false,
        'message': 'Password reset failed: ${e.toString()}',
      };
    }
  }

  // ============================================
  // SIGN OUT
  // ============================================
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ============================================
  // GET USER ROLE
  // ============================================
  Future<String?> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;

      final roles = List<String>.from(doc.data()?['roles'] ?? []);
      return roles.isNotEmpty ? roles.first : null;
    } catch (e) {
      return null;
    }
  }

  // ============================================
  // GET CURRENT USER
  // ============================================
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // ============================================
  // CHECK IF EMAIL IS VERIFIED
  // ============================================
  Future<bool> isEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ============================================
  // ERROR MESSAGE HELPER
  // ============================================
  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak (minimum 6 characters)';
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again';
      default:
        return 'Authentication error. Please try again';
    }
  }
}
