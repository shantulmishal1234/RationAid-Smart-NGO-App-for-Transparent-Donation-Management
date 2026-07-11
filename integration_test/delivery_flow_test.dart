import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:ration_aid/models/delivery_assignment_model.dart';

/// Delivery Flow Integration Test
///
/// Tests the complete delivery lifecycle:
///   Admin creates assignment → Distributor sees it → Picks up →
///   In Transit → Submits Proof → Admin Verifies
///
/// Uses FakeFirebaseFirestore — NO real Firebase calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore mockFirestore;

  setUp(() {
    mockFirestore = FakeFirebaseFirestore();
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 1: Admin Creates Delivery Assignment
  // ─────────────────────────────────────────────────────────────────
  testWidgets(
    'delivery_flow_001: Admin creates delivery assignment for a family',
    (WidgetTester tester) async {
      final now = Timestamp.now();
      final scheduled = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 1)),
      );

      // Act: create delivery assignment (mirrors DeliveryService.createAssignment)
      await mockFirestore.collection('delivery_assignments').doc('del_001').set(
        {
          'familyId': 'family_abc',
          'familyArea': 'Gulshan-e-Iqbal',
          'familyCity': 'Karachi',
          'familyAddress': 'Block 7, Gulshan',
          'familyPhone': '03001234567',
          'familySize': 5,
          'familyGeoLat': 24.9008,
          'familyGeoLng': 67.0990,
          'familyLocationVerified': true,
          'assignedPackId': 'pack_001',
          'assignedPackName': 'Basic Food Pack',
          'items': {'Rice': 10, 'Flour': 5, 'Oil': 3},
          'itemUnits': {'Rice': 'kg', 'Flour': 'kg', 'Oil': 'L'},
          'inKindCoveredItems': [],
          'assignedDistributorId': 'dist_001',
          'assignedDistributorName': 'Khalid Mehmood',
          'status': DeliveryStatus.notStarted.toFirestore(),
          'scheduledAt': scheduled,
          'adminNote': 'Handle with care — elderly family',
          'procurementRequestId': 'proc_001',
          'createdAt': now,
          'updatedAt': now,
        },
      );

      // Assert: document created correctly
      final doc = await mockFirestore
          .collection('delivery_assignments')
          .doc('del_001')
          .get();
      expect(doc.exists, true);

      final assignment = DeliveryAssignment.fromFirestore(doc);
      expect(assignment.status, DeliveryStatus.notStarted);
      expect(assignment.familyId, 'family_abc');
      expect(assignment.familyCity, 'Karachi');
      expect(assignment.assignedDistributorName, 'Khalid Mehmood');
      expect(assignment.items['Rice'], 10);
      expect(assignment.itemUnits['Rice'], 'kg');
      expect(assignment.adminNote, 'Handle with care — elderly family');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.local_shipping,
                    size: 48,
                    color: Colors.blue,
                  ),
                  const Text('Delivery Assignment Created'),
                  Text(
                    'Family: ${assignment.familyArea}, ${assignment.familyCity}',
                  ),
                  Text('Distributor: ${assignment.assignedDistributorName}'),
                  Text('Status: ${assignment.status.displayName}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Delivery Assignment Created'), findsOneWidget);
      expect(find.text('Family: Gulshan-e-Iqbal, Karachi'), findsOneWidget);
      expect(find.text('Distributor: Khalid Mehmood'), findsOneWidget);
      expect(find.text('Status: Not Started'), findsOneWidget);
    },
  );

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 2: Distributor Picks Up (notStarted → pickedUp)
  // ─────────────────────────────────────────────────────────────────
  testWidgets(
    'delivery_flow_002: Distributor marks pickup — status becomes picked_up',
    (WidgetTester tester) async {
      final now = Timestamp.now();

      // Seed a not_started assignment
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_pickup')
          .set({
            'familyId': 'family_pickup',
            'familyArea': 'DHA',
            'familyCity': 'Karachi',
            'familyAddress': 'Phase 5',
            'familySize': 4,
            'familyLocationVerified': true,
            'items': {'Rice': 10},
            'itemUnits': {'Rice': 'kg'},
            'inKindCoveredItems': [],
            'assignedDistributorId': 'dist_001',
            'assignedDistributorName': 'Khalid',
            'status': DeliveryStatus.notStarted.toFirestore(),
            'createdAt': now,
            'updatedAt': now,
          });

      // Distributor marks pickup
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_pickup')
          .update({
            'status': DeliveryStatus.pickedUp.toFirestore(),
            'pickedUpAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

      final doc = await mockFirestore
          .collection('delivery_assignments')
          .doc('del_pickup')
          .get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.status, DeliveryStatus.pickedUp);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2, size: 48, color: Colors.orange),
                  Text('Status: ${assignment.status.displayName}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Status: Picked Up'), findsOneWidget);
    },
  );

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 3: Full Delivery Lifecycle
  //   notStarted → pickedUp → inTransit → delivered
  // ─────────────────────────────────────────────────────────────────
  testWidgets(
    'delivery_flow_003: Full delivery lifecycle from assignment to delivered',
    (WidgetTester tester) async {
      final now = Timestamp.now();

      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_full')
          .set({
            'familyId': 'family_full',
            'familyArea': 'Clifton',
            'familyCity': 'Karachi',
            'familyAddress': 'Block 9, Clifton',
            'familySize': 6,
            'familyLocationVerified': true,
            'items': {'Rice': 10, 'Flour': 5},
            'itemUnits': {'Rice': 'kg', 'Flour': 'kg'},
            'inKindCoveredItems': [],
            'assignedDistributorId': 'dist_002',
            'assignedDistributorName': 'Ali Hassan',
            'status': DeliveryStatus.notStarted.toFirestore(),
            'createdAt': now,
            'updatedAt': now,
          });

      // Step 1: Pickup
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_full')
          .update({
            'status': DeliveryStatus.pickedUp.toFirestore(),
            'updatedAt': Timestamp.now(),
          });

      // Step 2: In Transit
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_full')
          .update({
            'status': DeliveryStatus.inTransit.toFirestore(),
            'updatedAt': Timestamp.now(),
          });

      // Step 3: Delivered with proof
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_full')
          .update({
            'status': DeliveryStatus.delivered.toFirestore(),
            'proofPhotoUrl': 'https://cloudinary.com/proof_full.jpg',
            'proofRecipientName': 'Family Representative',
            'proofTimestamp': Timestamp.now(),
            'deliveredAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

      final doc = await mockFirestore
          .collection('delivery_assignments')
          .doc('del_full')
          .get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.status, DeliveryStatus.delivered);
      expect(assignment.proofPhotoUrl, 'https://cloudinary.com/proof_full.jpg');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const Text('Delivery Complete!'),
                  Text('Status: ${assignment.status.displayName}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Delivery Complete!'), findsOneWidget);
      expect(find.text('Status: Delivered'), findsOneWidget);
    },
  );

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 4: Failed Delivery → Reassigned
  // ─────────────────────────────────────────────────────────────────
  testWidgets(
    'delivery_flow_004: Failed delivery is reassigned to new distributor',
    (WidgetTester tester) async {
      final now = Timestamp.now();

      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .set({
            'familyId': 'family_fail',
            'familyArea': 'North Nazimabad',
            'familyCity': 'Karachi',
            'familyAddress': 'Block K',
            'familySize': 3,
            'familyLocationVerified': false,
            'items': {},
            'itemUnits': {},
            'inKindCoveredItems': [],
            'assignedDistributorId': 'dist_001',
            'assignedDistributorName': 'Old Driver',
            'status': DeliveryStatus.inTransit.toFirestore(),
            'createdAt': now,
            'updatedAt': now,
          });

      // Mark as failed
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .update({
            'status': DeliveryStatus.failed.toFirestore(),
            'failureReason': DeliveryFailureReason.familyUnavailable
                .toFirestore(),
            'failureNotes': 'No one home, tried 3 times',
            'updatedAt': Timestamp.now(),
          });

      // Admin reassigns to different distributor
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .update({
            'status': DeliveryStatus.reassigned.toFirestore(),
            'assignedDistributorId': 'dist_002',
            'assignedDistributorName': 'New Driver',
            'updatedAt': Timestamp.now(),
          });

      final doc = await mockFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.status, DeliveryStatus.reassigned);
      expect(assignment.assignedDistributorId, 'dist_002');
      expect(assignment.assignedDistributorName, 'New Driver');
      expect(assignment.failureReason, DeliveryFailureReason.familyUnavailable);
      expect(assignment.failureNotes, 'No one home, tried 3 times');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swap_horiz, size: 48, color: Colors.orange),
                  Text('Status: ${assignment.status.displayName}'),
                  Text('New Driver: ${assignment.assignedDistributorName}'),
                  Text(
                    'Failure Reason: ${assignment.failureReason!.toFirestore()}',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Status: Reassigned'), findsOneWidget);
      expect(find.text('New Driver: New Driver'), findsOneWidget);
      expect(find.text('Failure Reason: family_unavailable'), findsOneWidget);
    },
  );

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 5: Admin Verifies Delivered Proof
  // ─────────────────────────────────────────────────────────────────
  testWidgets(
    'delivery_flow_005: Admin verifies delivered proof — status becomes admin_verified',
    (WidgetTester tester) async {
      final now = Timestamp.now();

      // Seed a delivered assignment
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_verify')
          .set({
            'familyId': 'family_verify',
            'familyArea': 'PECHS',
            'familyCity': 'Karachi',
            'familyAddress': 'Block 2',
            'familySize': 4,
            'familyLocationVerified': true,
            'items': {'Rice': 10},
            'itemUnits': {'Rice': 'kg'},
            'inKindCoveredItems': [],
            'assignedDistributorId': 'dist_001',
            'status': DeliveryStatus.delivered.toFirestore(),
            'proofPhotoUrl': 'https://cloudinary.com/proof.jpg',
            'proofRecipientName': 'Mr. Ahmed',
            'deliveredAt': now,
            'createdAt': now,
            'updatedAt': now,
          });

      // Admin verifies proof
      await mockFirestore
          .collection('delivery_assignments')
          .doc('del_verify')
          .update({
            'status': DeliveryStatus.adminVerified.toFirestore(),
            'adminVerifiedAt': Timestamp.now(),
            'adminVerifiedBy': 'admin_uid_001',
            'adminVerifierName': 'Admin User',
            'updatedAt': Timestamp.now(),
          });

      final doc = await mockFirestore
          .collection('delivery_assignments')
          .doc('del_verify')
          .get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.status, DeliveryStatus.adminVerified);
      expect(doc.data()!['adminVerifiedBy'], 'admin_uid_001');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_user,
                    size: 64,
                    color: Colors.green,
                  ),
                  const Text('Admin Verification Complete'),
                  Text('Status: ${assignment.status.displayName}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Admin Verification Complete'), findsOneWidget);
      expect(find.text('Status: Verified'), findsOneWidget);
    },
  );
}
