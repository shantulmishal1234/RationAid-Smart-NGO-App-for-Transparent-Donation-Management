import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize the notification service
  static Future<void> initialize() async {
    // Placeholder for future initialization (e.g. FCM)
    print('NotificationService initialized');
  }

  /// Send notification to a specific role (Legacy compatibility)
  static Future<void> sendToRole({
    required String role,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // Map 'admin' role to broadcast admin notification
    if (role == 'admin') {
      await sendAdminNotification(
        title: title,
        message: body,
        type: data?['type'] ?? 'general',
        relatedId: data?['donationId'] ?? data?['familyId'],
      );
    }
  }

  /// Send notification to a specific user (Direct)
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': title,
        'message': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'direct_message',
      });
    } catch (e) {
      print('Error sending direct notification: $e');
    }
  }

  /// Send a notification to all admins
  static Future<void> sendAdminNotification({
    required String title,
    required String message,
    required String
    type, // 'family_review', 'quorum_reached', 'fully_funded', 'delivery_pending'
    String? relatedId, // familyId or donationId
  }) async {
    try {
      await _firestore.collection('admin_notifications').add({
        'title': title,
        'message': message,
        'type': type,
        'relatedId': relatedId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'readBy': [], // List of admin UIDs who have read this
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  /// Send notification specifically for a new family needing review
  static Future<void> notifyNewFamily(String familyId, String location) async {
    await sendAdminNotification(
      title: 'New Family Submitted',
      message: 'A new family in $location is waiting for review.',
      type: 'family_review',
      relatedId: familyId,
    );
  }

  /// Send notification for Quorum Reached
  static Future<void> notifyQuorumReached(String familyId, int votes) async {
    await sendAdminNotification(
      title: 'Quorum Reached',
      message: 'Family has received $votes votes. Ready for Final Approval.',
      type: 'quorum_reached',
      relatedId: familyId,
    );
  }

  /// Send notification for Fully Funded
  static Future<void> notifyFullyFunded(String familyId) async {
    await sendAdminNotification(
      title: 'Funding Target Met',
      message: 'A family is now fully funded! Verify purchase now.',
      type: 'fully_funded',
      relatedId: familyId,
    );
  }

  /// Send notification when Purchaser submits a purchase
  static Future<void> notifyPurchaseSubmitted({
    required String requestId,
    required String purchaserName,
    required String packName,
  }) async {
    await sendAdminNotification(
      title: 'Purchase Submitted',
      message:
          '$purchaserName submitted a purchase for "$packName". Verify now.',
      type: 'purchase_verification',
      relatedId: requestId,
    );
  }

  /// Send notification when GRF Pool sweeps variance (Surplus/Deficit)
  static Future<void> notifyAdminGRFSweep({
    required double amount,
    required bool isSurplus,
    required String packName,
  }) async {
    final title =
        isSurplus ? 'GRF Surplus Recovered 💰' : 'GRF Inflation Subsidy 📉';
    final message = isSurplus
        ? 'Successfully swept PKR ${amount.toStringAsFixed(0)} back to GRF Pool from $packName budget.'
        : 'Deducted PKR ${amount.toStringAsFixed(0)} from GRF Pool to cover inflation deficit for $packName.';

    await sendAdminNotification(
      title: title,
      message: message,
      type: 'grf_audit',
      relatedId: 'general_relief_fund',
    );
  }

  /// Mark notification as read for current user
  static Future<void> markAsRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore
        .collection('admin_notifications')
        .doc(notificationId)
        .update({
          'readBy': FieldValue.arrayUnion([user.uid]),
        });
  }

  /// Mark all as read
  static Future<void> markAllAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final batch = _firestore.batch();
    final snapshot = await _firestore.collection('admin_notifications').get();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([user.uid]),
      });
    }
    await batch.commit();
  }

  /// Stream of unread notifications for the current user
  /// Since 'isRead' is shared, we check if 'readBy' contains current uid
  static Stream<int> getUnreadCountStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);

    return _firestore.collection('admin_notifications').snapshots().map((
      snapshot,
    ) {
      int count = 0;
      for (var doc in snapshot.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? []);
        if (!readBy.contains(user.uid)) {
          count++;
        }
      }
      return count;
    });
  }

  /// Stream notifications for a specific user (e.g. Donor)
  static Stream<QuerySnapshot> streamUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Mark all notifications as read for a specific user
  static Future<void> markAllUserNotificationsAsRead(String userId) async {
    final unread = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Stream notifications for Purchaser role (Specific + Broadcasts)
  static Stream<QuerySnapshot> streamPurchaserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', whereIn: [userId, 'all'])
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Send notification to a specific Purchaser
  static Future<void> sendPurchaserNotification({
    required String userId,
    required String title,
    required String message,
    String? actionType,
    String? actionId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'role': 'purchaser',
        'title': title,
        'message': message,
        'actionType': actionType,
        'actionId': actionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error sending purchaser notification: $e');
    }
  }

  /// Send broadcast notification to ALL Purchasers
  static Future<void> notifyAllPurchasers({
    required String title,
    required String message,
    String? actionType,
    String? actionId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': 'all',
        'role': 'purchaser',
        'title': title,
        'message': message,
        'actionType': actionType,
        'actionId': actionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error sending broadcast purchaser notification: $e');
    }
  }

  /// Mark Purchaser notification as read
  static Future<void> markPurchaserNotificationAsRead(
    String notificationId,
  ) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DONOR NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a direct notification to a Donor
  static Future<void> sendDonorNotification({
    required String userId,
    required String title,
    required String message,
    String? actionType,
    String? actionId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'role': 'donor',
        'title': title,
        'message': message,
        'actionType': actionType,
        'actionId': actionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error sending donor notification: $e');
    }
  }

  /// Get unread notification count for a specific Donor
  static Stream<int> getDonorUnreadCountStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DISTRIBUTOR NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Send a direct notification to a specific Distributor
  static Future<void> sendDistributorNotification({
    required String userId,
    required String title,
    required String message,
    String? actionType,
    String? actionId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'role': 'distributor',
        'title': title,
        'message': message,
        'actionType': actionType,
        'actionId': actionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error sending distributor notification: $e');
    }
  }

  /// Broadcast a notification to ALL Distributors (e.g. new pool delivery)
  static Future<void> notifyAllDistributors({
    required String title,
    required String message,
    String? actionType,
    String? actionId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': 'all_distributors',
        'role': 'distributor',
        'title': title,
        'message': message,
        'actionType': actionType,
        'actionId': actionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error sending distributor broadcast: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PURCHASER NOTIFICATIONS (Issue)
  // ─────────────────────────────────────────────────────────────────────────

  /// Send notification when Purchaser reports an issue
  static Future<void> notifyIssueReported({
    required String requestId,
    required String packName,
    required String issueType,
    required String reportedBy,
  }) async {
    await sendAdminNotification(
      title: 'Inventory Issue Reported ⚠️',
      message:
          '$reportedBy reported "$issueType" issue for $packName. Review required.',
      type: 'inventory_issue',
      relatedId: requestId,
    );
  }

  /// Get unread count for Purchaser
  static Stream<int> getPurchaserUnreadCountStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', whereIn: [userId, 'all'])
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Stream notifications for Distributor role (direct + pool broadcasts)
  static Stream<QuerySnapshot> streamDistributorNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', whereIn: [userId, 'all_distributors'])
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get unread count for Distributor (direct + pool broadcasts)
  static Stream<int> getDistributorUnreadCountStream(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', whereIn: [userId, 'all_distributors'])
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark notification as read (general utility)
  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }
}
