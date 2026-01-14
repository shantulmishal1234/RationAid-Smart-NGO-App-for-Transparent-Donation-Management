import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuditService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Log any action to the audit trail
  static Future<void> logAction({
    required String action,
    required String entityType, // 'family', 'donation', 'user', 'system'
    String? entityId,
    String? details,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('audit_logs').add({
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'details': details,
        'metadata': metadata,
        'performedByUid': user.uid,
        'performedByEmail': user.email,
        'performedByName': user.displayName ?? user.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silent fail - don't block operations if logging fails
      print('Audit log failed: $e');
    }
  }

  /// Convenience methods for common actions
  static Future<void> logFamilyAction({
    required String action,
    required String familyId,
    String? familyName,
    String? details,
  }) async {
    await logAction(
      action: action,
      entityType: 'family',
      entityId: familyId,
      details: details,
      metadata: {'familyName': familyName},
    );
  }

  static Future<void> logDonationAction({
    required String action,
    required String donationId,
    String? donorName,
    double? amount,
    String? details,
  }) async {
    await logAction(
      action: action,
      entityType: 'donation',
      entityId: donationId,
      details: details,
      metadata: {'donorName': donorName, 'amount': amount},
    );
  }

  static Future<void> logUserAction({
    required String action,
    required String userId,
    String? userName,
    String? details,
  }) async {
    await logAction(
      action: action,
      entityType: 'user',
      entityId: userId,
      details: details,
      metadata: {'userName': userName},
    );
  }

  static Future<void> logSystemAction({
    required String action,
    String? details,
  }) async {
    await logAction(action: action, entityType: 'system', details: details);
  }
}
