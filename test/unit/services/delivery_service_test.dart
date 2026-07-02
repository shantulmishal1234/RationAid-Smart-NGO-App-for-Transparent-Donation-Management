import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  // ─────────────────────────────────────────────────────────────────
  // Delivery Assignment CRUD via FakeFirestore
  // (Tests the Firestore data structures DeliveryService operates on)
  // ─────────────────────────────────────────────────────────────────
  group('DeliveryService — Firestore data operations', () {
    test('createAssignment: writes correct document structure to Firestore', () async {
      final now = DateTime.now();
      final docRef = fakeFirestore.collection('delivery_assignments').doc('del_001');

      await docRef.set({
        'familyId': 'family_abc',
        'familyArea': 'Gulshan-e-Iqbal',
        'familyCity': 'Karachi',
        'familyAddress': 'Block 7',
        'familyPhone': '03001234567',
        'familySize': 5,
        'familyGeoLat': 24.9008,
        'familyGeoLng': 67.0990,
        'familyLocationVerified': true,
        'assignedPackId': 'pack_001',
        'assignedPackName': 'Basic Food Pack',
        'items': {'Rice': 10, 'Flour': 5},
        'itemUnits': {'Rice': 'kg', 'Flour': 'kg'},
        'inKindCoveredItems': [],
        'assignedDistributorId': 'dist_001',
        'assignedDistributorName': 'Khalid Mehmood',
        'status': DeliveryStatus.notStarted.toFirestore(),
        'scheduledAt': Timestamp.fromDate(now.add(const Duration(days: 1))),
        'adminNote': 'Priority delivery',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      final doc =
          await fakeFirestore.collection('delivery_assignments').doc('del_001').get();

      expect(doc.exists, true);
      expect(doc.data()!['familyId'], 'family_abc');
      expect(doc.data()!['familyCity'], 'Karachi');
      expect(doc.data()!['status'], 'not_started');
      expect(doc.data()!['assignedDistributorId'], 'dist_001');
      expect(doc.data()!['items']['Rice'], 10);
    });

    test('updateStatus: updates status field and updatedAt timestamp', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('delivery_assignments').doc('del_002').set({
        'familyId': 'family_xyz',
        'familyArea': 'DHA',
        'status': 'not_started',
        'createdAt': now,
        'updatedAt': now,
      });

      // Simulate status update (what DeliveryService.updateStatus does)
      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_002')
          .update({
        'status': DeliveryStatus.pickedUp.toFirestore(),
        'updatedAt': Timestamp.now(),
      });

      final doc =
          await fakeFirestore.collection('delivery_assignments').doc('del_002').get();
      expect(doc.data()!['status'], 'picked_up');
    });

    test('getAssignmentsForDistributor: filters by assignedDistributorId', () async {
      final now = Timestamp.now();

      // Dist A assignments
      await fakeFirestore.collection('delivery_assignments').doc('del_001').set({
        'assignedDistributorId': 'dist_A',
        'status': 'not_started',
        'familyId': 'fam_1',
        'createdAt': now,
      });
      await fakeFirestore.collection('delivery_assignments').doc('del_002').set({
        'assignedDistributorId': 'dist_A',
        'status': 'in_transit',
        'familyId': 'fam_2',
        'createdAt': now,
      });

      // Dist B assignment
      await fakeFirestore.collection('delivery_assignments').doc('del_003').set({
        'assignedDistributorId': 'dist_B',
        'status': 'not_started',
        'familyId': 'fam_3',
        'createdAt': now,
      });

      final snapshot = await fakeFirestore
          .collection('delivery_assignments')
          .where('assignedDistributorId', isEqualTo: 'dist_A')
          .get();

      expect(snapshot.docs.length, 2);
      for (final doc in snapshot.docs) {
        expect(doc.data()['assignedDistributorId'], 'dist_A');
      }
    });

    test('getAssignmentsForAdmin: reads all assignments from collection', () async {
      final now = Timestamp.now();

      for (int i = 1; i <= 5; i++) {
        await fakeFirestore.collection('delivery_assignments').doc('del_$i').set({
          'familyId': 'fam_$i',
          'status': 'not_started',
          'assignedDistributorId': 'dist_$i',
          'createdAt': now,
        });
      }

      final snapshot =
          await fakeFirestore.collection('delivery_assignments').get();
      expect(snapshot.docs.length, 5);
    });

    test('updateToDelivered: sets status to delivered and records proof URL', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('delivery_assignments').doc('del_proof').set({
        'familyId': 'family_abc',
        'status': 'in_transit',
        'createdAt': now,
        'updatedAt': now,
      });

      // Simulate proof submission
      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_proof')
          .update({
        'status': DeliveryStatus.delivered.toFirestore(),
        'proofPhotoUrl': 'https://cloudinary.com/proof.jpg',
        'proofRecipientName': 'Family Head',
        'proofTimestamp': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      final doc = await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_proof')
          .get();
      expect(doc.data()!['status'], 'delivered');
      expect(doc.data()!['proofPhotoUrl'], 'https://cloudinary.com/proof.jpg');
      expect(doc.data()!['proofRecipientName'], 'Family Head');
    });

    test('markFailed: sets status to failed and records failure reason', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('delivery_assignments').doc('del_fail').set({
        'familyId': 'family_abc',
        'status': 'in_transit',
        'createdAt': now,
        'updatedAt': now,
      });

      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .update({
        'status': DeliveryStatus.failed.toFirestore(),
        'failureReason': DeliveryFailureReason.familyUnavailable.toFirestore(),
        'failureNote': 'Nobody was home',
        'updatedAt': Timestamp.now(),
      });

      final doc = await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_fail')
          .get();
      expect(doc.data()!['status'], 'failed');
      expect(doc.data()!['failureReason'], 'family_unavailable');
      expect(doc.data()!['failureNote'], 'Nobody was home');
    });

    test('adminVerify: sets status to admin_verified', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('delivery_assignments').doc('del_verify').set({
        'familyId': 'family_abc',
        'status': 'delivered',
        'createdAt': now,
        'updatedAt': now,
      });

      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_verify')
          .update({
        'status': DeliveryStatus.adminVerified.toFirestore(),
        'adminVerifiedAt': Timestamp.now(),
        'adminVerifiedBy': 'admin_uid',
        'updatedAt': Timestamp.now(),
      });

      final doc = await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_verify')
          .get();
      expect(doc.data()!['status'], 'admin_verified');
      expect(doc.data()!['adminVerifiedBy'], 'admin_uid');
    });

    test('reassign: updates distributor fields and status', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('delivery_assignments').doc('del_reassign').set({
        'familyId': 'family_abc',
        'status': 'failed',
        'assignedDistributorId': 'dist_old',
        'assignedDistributorName': 'Old Driver',
        'createdAt': now,
        'updatedAt': now,
      });

      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_reassign')
          .update({
        'status': DeliveryStatus.reassigned.toFirestore(),
        'assignedDistributorId': 'dist_new',
        'assignedDistributorName': 'New Driver',
        'updatedAt': Timestamp.now(),
      });

      final doc = await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_reassign')
          .get();
      expect(doc.data()!['status'], 'reassigned');
      expect(doc.data()!['assignedDistributorId'], 'dist_new');
      expect(doc.data()!['assignedDistributorName'], 'New Driver');
    });

    test('filter by status: returns only not_started assignments', () async {
      final now = Timestamp.now();

      final statuses = ['not_started', 'in_transit', 'delivered', 'not_started', 'failed'];
      for (int i = 0; i < statuses.length; i++) {
        await fakeFirestore.collection('delivery_assignments').doc('del_$i').set({
          'familyId': 'fam_$i',
          'status': statuses[i],
          'createdAt': now,
        });
      }

      final snapshot = await fakeFirestore
          .collection('delivery_assignments')
          .where('status', isEqualTo: 'not_started')
          .get();

      expect(snapshot.docs.length, 2);
    });

    test('offline proof queue: JSON serializes and restores correctly', () {
      // Test the data structure of offline proofs stored in SharedPreferences
      final proofData = {
        'assignmentId': 'del_offline',
        'photoUrl': 'https://cloudinary.com/offline_proof.jpg',
        'recipientName': 'Offline Recipient',
        'timestamp': DateTime.now().toIso8601String(),
        'latitude': 24.9008,
        'longitude': 67.0990,
      };

      final jsonString = jsonEncode(proofData);
      final restored = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(restored['assignmentId'], 'del_offline');
      expect(restored['recipientName'], 'Offline Recipient');
      expect(restored['latitude'], 24.9008);
    });
  });
}
