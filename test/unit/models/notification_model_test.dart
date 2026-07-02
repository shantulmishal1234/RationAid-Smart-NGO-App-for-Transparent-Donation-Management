import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/notification_model.dart';

void main() {
  group('AppNotification', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // ─────────────────────────────────────────────────────────────────
    // fromFirestore
    // ─────────────────────────────────────────────────────────────────
    test('correctly parses a standard notification document', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('notifications').doc('notif_001').set({
        'userId': 'user_abc',
        'role': 'donor',
        'title': 'Donation Verified',
        'message': 'Your donation has been verified by admin.',
        'isRead': false,
        'createdAt': now,
        'actionType': 'donation_status',
        'actionId': 'don_001',
      });

      final doc =
          await fakeFirestore.collection('notifications').doc('notif_001').get();
      final notif = AppNotification.fromFirestore(doc);

      expect(notif.id, 'notif_001');
      expect(notif.userId, 'user_abc');
      expect(notif.role, 'donor');
      expect(notif.title, 'Donation Verified');
      expect(notif.message, 'Your donation has been verified by admin.');
      expect(notif.isRead, false);
      expect(notif.actionType, 'donation_status');
      expect(notif.actionId, 'don_001');
    });

    test('prefers "message" field over "body" field', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('notifications').doc('notif_002').set({
        'userId': 'user_xyz',
        'role': 'admin',
        'title': 'Test',
        'message': 'This is the message',
        'body': 'This is the body',
        'isRead': false,
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('notifications').doc('notif_002').get();
      final notif = AppNotification.fromFirestore(doc);

      expect(notif.message, 'This is the message');
    });

    test('falls back to "body" field when "message" is absent', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('notifications').doc('notif_003').set({
        'userId': 'user_xyz',
        'role': 'admin',
        'title': 'Test',
        'body': 'Body-only message',
        'isRead': false,
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('notifications').doc('notif_003').get();
      final notif = AppNotification.fromFirestore(doc);

      expect(notif.message, 'Body-only message');
    });

    test('uses default role "all" when role field is missing', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('notifications').doc('notif_004').set({
        'userId': 'all',
        'title': 'Broadcast',
        'message': 'System wide announcement',
        'isRead': false,
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('notifications').doc('notif_004').get();
      final notif = AppNotification.fromFirestore(doc);

      expect(notif.role, 'all');
    });

    test('handles missing optional fields gracefully', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('notifications').doc('notif_005').set({
        'userId': 'user_abc',
        'role': 'purchaser',
        'title': 'Simple Notif',
        'message': 'Simple message',
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('notifications').doc('notif_005').get();
      final notif = AppNotification.fromFirestore(doc);

      expect(notif.isRead, false); // default
      expect(notif.actionType, isNull);
      expect(notif.actionId, isNull);
    });

    // ─────────────────────────────────────────────────────────────────
    // toFirestore
    // ─────────────────────────────────────────────────────────────────
    test('toFirestore serializes all fields correctly', () {
      final now = DateTime(2024, 6, 15, 10, 30);
      final notif = AppNotification(
        id: 'notif_001',
        userId: 'user_abc',
        role: 'donor',
        title: 'Test',
        message: 'Test message',
        isRead: true,
        createdAt: now,
        actionType: 'donation_status',
        actionId: 'don_001',
      );

      final map = notif.toFirestore();

      expect(map['userId'], 'user_abc');
      expect(map['role'], 'donor');
      expect(map['title'], 'Test');
      expect(map['message'], 'Test message');
      expect(map['isRead'], true);
      expect(map['actionType'], 'donation_status');
      expect(map['actionId'], 'don_001');
      expect(map['createdAt'], isA<Timestamp>());
    });

    // ─────────────────────────────────────────────────────────────────
    // Computed Properties
    // ─────────────────────────────────────────────────────────────────
    test('isBroadcast is true when userId is "all"', () {
      final notif = AppNotification(
        id: 'n1',
        userId: 'all',
        role: 'donor',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
      );
      expect(notif.isBroadcast, true);
    });

    test('isBroadcast is true when role is "all"', () {
      final notif = AppNotification(
        id: 'n2',
        userId: 'user_abc',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
      );
      expect(notif.isBroadcast, true);
    });

    test('isBroadcast is false for targeted notification', () {
      final notif = AppNotification(
        id: 'n3',
        userId: 'user_specific',
        role: 'donor',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
      );
      expect(notif.isBroadcast, false);
    });

    test('hasAction is true when both actionType and actionId are set', () {
      final notif = AppNotification(
        id: 'n4',
        userId: 'user_abc',
        role: 'donor',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
        actionType: 'delivery_update',
        actionId: 'del_001',
      );
      expect(notif.hasAction, true);
    });

    test('hasAction is false when actionType or actionId is null', () {
      final notif = AppNotification(
        id: 'n5',
        userId: 'user_abc',
        role: 'donor',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
        actionType: 'donation_status',
        // actionId is null
      );
      expect(notif.hasAction, false);
    });

    test('timeAgo returns "Just now" for recent notifications', () {
      final notif = AppNotification(
        id: 'n6',
        userId: 'u',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now(),
      );
      expect(notif.timeAgo, 'Just now');
    });

    test('timeAgo returns correct minutes format', () {
      final notif = AppNotification(
        id: 'n7',
        userId: 'u',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      expect(notif.timeAgo, '30m ago');
    });

    test('timeAgo returns correct hours format', () {
      final notif = AppNotification(
        id: 'n8',
        userId: 'u',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      expect(notif.timeAgo, '3h ago');
    });

    test('timeAgo returns correct days format', () {
      final notif = AppNotification(
        id: 'n9',
        userId: 'u',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(notif.timeAgo, '2d ago');
    });

    test('timeAgo returns correct weeks format', () {
      final notif = AppNotification(
        id: 'n10',
        userId: 'u',
        role: 'all',
        title: 'T',
        message: 'M',
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
      );
      expect(notif.timeAgo, '2w ago');
    });

    // ─────────────────────────────────────────────────────────────────
    // copyWith
    // ─────────────────────────────────────────────────────────────────
    test('copyWith updates only isRead without changing other fields', () {
      final original = AppNotification(
        id: 'notif_001',
        userId: 'user_abc',
        role: 'donor',
        title: 'Original Title',
        message: 'Original Message',
        isRead: false,
        createdAt: DateTime(2024, 1, 1),
        actionType: 'donation_status',
        actionId: 'don_001',
      );

      final updated = original.copyWith(isRead: true);

      expect(updated.isRead, true);
      expect(updated.id, 'notif_001');
      expect(updated.userId, 'user_abc');
      expect(updated.title, 'Original Title');
      expect(updated.message, 'Original Message');
      expect(updated.actionType, 'donation_status');
    });
  });
}
