import 'package:cloud_firestore/cloud_firestore.dart';

/// Notification model for app notifications
class AppNotification {
  final String id;
  final String userId; // specific user, or 'all' for broadcasts
  final String role; // donor, purchaser, volunteer, admin, or 'all'
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final String? actionType; // optional: 'donation_status', 'broadcast', etc.
  final String? actionId; // optional: related donation/delivery ID

  AppNotification({
    required this.id,
    required this.userId,
    required this.role,
    required this.title,
    required this.message,
    this.isRead = false,
    required this.createdAt,
    this.actionType,
    this.actionId,
  });

  /// Factory constructor from Firestore document
  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Check both 'message' and 'body' fields (admin might use 'body')
    final notificationMessage = data['message'] ?? data['body'] ?? '';

    return AppNotification(
      id: doc.id,
      userId: data['userId'] ?? '',
      role: data['role'] ?? 'all',
      title: data['title'] ?? '',
      message: notificationMessage,
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      actionType: data['actionType'],
      actionId: data['actionId'],
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'role': role,
      'title': title,
      'message': message,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'actionType': actionType,
      'actionId': actionId,
    };
  }

  /// Helper: Check if notification is a broadcast
  bool get isBroadcast {
    return userId == 'all' || role == 'all';
  }

  /// Helper: Check if notification has an action
  bool get hasAction {
    return actionType != null && actionId != null;
  }

  /// Helper: Get time ago string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Copy with method for updates (mainly for marking as read)
  AppNotification copyWith({
    String? id,
    String? userId,
    String? role,
    String? title,
    String? message,
    bool? isRead,
    DateTime? createdAt,
    String? actionType,
    String? actionId,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      title: title ?? this.title,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      actionType: actionType ?? this.actionType,
      actionId: actionId ?? this.actionId,
    );
  }
}
