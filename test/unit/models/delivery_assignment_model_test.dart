import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // DeliveryStatus Enum
  // ─────────────────────────────────────────────────────────────────
  group('DeliveryStatus', () {
    test('toFirestore serializes all 7 statuses correctly', () {
      expect(DeliveryStatus.notStarted.toFirestore(), 'not_started');
      expect(DeliveryStatus.pickedUp.toFirestore(), 'picked_up');
      expect(DeliveryStatus.inTransit.toFirestore(), 'in_transit');
      expect(DeliveryStatus.delivered.toFirestore(), 'delivered');
      expect(DeliveryStatus.failed.toFirestore(), 'failed');
      expect(DeliveryStatus.adminVerified.toFirestore(), 'admin_verified');
      expect(DeliveryStatus.reassigned.toFirestore(), 'reassigned');
    });

    test('fromFirestore parses all known Firestore strings', () {
      expect(DeliveryStatus.fromFirestore('not_started'), DeliveryStatus.notStarted);
      expect(DeliveryStatus.fromFirestore('picked_up'), DeliveryStatus.pickedUp);
      expect(DeliveryStatus.fromFirestore('in_transit'), DeliveryStatus.inTransit);
      expect(DeliveryStatus.fromFirestore('delivered'), DeliveryStatus.delivered);
      expect(DeliveryStatus.fromFirestore('failed'), DeliveryStatus.failed);
      expect(DeliveryStatus.fromFirestore('admin_verified'), DeliveryStatus.adminVerified);
      expect(DeliveryStatus.fromFirestore('reassigned'), DeliveryStatus.reassigned);
    });

    test('fromFirestore returns notStarted for unknown string', () {
      expect(DeliveryStatus.fromFirestore('unknown'), DeliveryStatus.notStarted);
      expect(DeliveryStatus.fromFirestore(''), DeliveryStatus.notStarted);
    });

    test('toFirestore and fromFirestore are a perfect round-trip for all statuses', () {
      for (final status in DeliveryStatus.values) {
        expect(
          DeliveryStatus.fromFirestore(status.toFirestore()),
          status,
          reason: 'Round-trip failed for $status',
        );
      }
    });

    test('displayName returns correct human-readable strings', () {
      expect(DeliveryStatus.notStarted.displayName, 'Not Started');
      expect(DeliveryStatus.pickedUp.displayName, 'Picked Up');
      expect(DeliveryStatus.inTransit.displayName, 'In Transit');
      expect(DeliveryStatus.delivered.displayName, 'Delivered');
      expect(DeliveryStatus.failed.displayName, 'Failed');
      expect(DeliveryStatus.adminVerified.displayName, 'Verified');
      expect(DeliveryStatus.reassigned.displayName, 'Reassigned');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DeliveryFailureReason Enum
  // ─────────────────────────────────────────────────────────────────
  group('DeliveryFailureReason', () {
    test('toFirestore serializes all failure reasons correctly', () {
      expect(DeliveryFailureReason.familyUnavailable.toFirestore(), 'family_unavailable');
      expect(DeliveryFailureReason.addressIncorrect.toFirestore(), 'address_incorrect');
      expect(DeliveryFailureReason.safetyConcern.toFirestore(), 'safety_concern');
      expect(DeliveryFailureReason.other.toFirestore(), 'other');
    });

    test('fromFirestore parses all known failure reason strings', () {
      expect(
        DeliveryFailureReason.fromFirestore('family_unavailable'),
        DeliveryFailureReason.familyUnavailable,
      );
      expect(
        DeliveryFailureReason.fromFirestore('address_incorrect'),
        DeliveryFailureReason.addressIncorrect,
      );
      expect(
        DeliveryFailureReason.fromFirestore('safety_concern'),
        DeliveryFailureReason.safetyConcern,
      );
      expect(DeliveryFailureReason.fromFirestore('other'), DeliveryFailureReason.other);
    });

    test('fromFirestore falls back to other for unknown reason', () {
      expect(DeliveryFailureReason.fromFirestore('unknown_reason'), DeliveryFailureReason.other);
    });

    test('round-trip serialization for all failure reasons', () {
      for (final reason in DeliveryFailureReason.values) {
        expect(
          DeliveryFailureReason.fromFirestore(reason.toFirestore()),
          reason,
          reason: 'Round-trip failed for $reason',
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DeliveryAssignment — fromFirestore
  // ─────────────────────────────────────────────────────────────────
  group('DeliveryAssignment.fromFirestore', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('correctly parses a full delivery assignment document', () async {
      final now = Timestamp.now();
      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_001')
          .set({
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
        'items': {'Rice': 10, 'Flour': 5},
        'itemUnits': {'Rice': 'kg', 'Flour': 'kg'},
        'inKindCoveredItems': ['Oil'],
        'assignedDistributorId': 'dist_001',
        'assignedDistributorName': 'Khalid Mehmood',
        'status': 'not_started',
        'scheduledAt': now,
        'adminNote': 'Handle with care',
        'procurementRequestId': 'proc_001',
        'createdAt': now,
        'updatedAt': now,
      });

      final doc =
          await fakeFirestore.collection('delivery_assignments').doc('del_001').get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.id, 'del_001');
      expect(assignment.familyId, 'family_abc');
      expect(assignment.familyArea, 'Gulshan-e-Iqbal');
      expect(assignment.familyCity, 'Karachi');
      expect(assignment.familyAddress, 'Block 7, Gulshan');
      expect(assignment.familyPhone, '03001234567');
      expect(assignment.familySize, 5);
      expect(assignment.familyGeoLat, closeTo(24.9008, 0.0001));
      expect(assignment.familyGeoLng, closeTo(67.0990, 0.0001));
      expect(assignment.familyLocationVerified, true);
      expect(assignment.assignedPackId, 'pack_001');
      expect(assignment.assignedPackName, 'Basic Food Pack');
      expect(assignment.items['Rice'], 10);
      expect(assignment.itemUnits['Rice'], 'kg');
      expect(assignment.inKindCoveredItems, contains('Oil'));
      expect(assignment.assignedDistributorId, 'dist_001');
      expect(assignment.assignedDistributorName, 'Khalid Mehmood');
      expect(assignment.status, DeliveryStatus.notStarted);
      expect(assignment.adminNote, 'Handle with care');
      expect(assignment.procurementRequestId, 'proc_001');
    });

    test('correctly parses a failed delivery with failure details', () async {
      final now = Timestamp.now();
      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_002')
          .set({
        'familyId': 'family_def',
        'familyArea': 'PECHS',
        'familyCity': 'Karachi',
        'familyAddress': 'Block 2, PECHS',
        'familySize': 3,
        'status': 'failed',
        'failureReason': 'family_unavailable',
        'failureNotes': 'No one was home',
        'createdAt': now,
        'updatedAt': now,
      });

      final doc =
          await fakeFirestore.collection('delivery_assignments').doc('del_002').get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.status, DeliveryStatus.failed);
      expect(assignment.failureReason, DeliveryFailureReason.familyUnavailable);
      expect(assignment.failureNotes, 'No one was home');
    });

    test('handles missing optional fields with correct defaults', () async {
      final now = Timestamp.now();
      await fakeFirestore
          .collection('delivery_assignments')
          .doc('del_003')
          .set({
        'familyId': 'family_ghi',
        'familyArea': 'Clifton',
        'familyCity': 'Karachi',
        'familyAddress': 'Block 5',
        'status': 'not_started',
        'createdAt': now,
        'updatedAt': now,
      });

      final doc =
          await fakeFirestore.collection('delivery_assignments').doc('del_003').get();
      final assignment = DeliveryAssignment.fromFirestore(doc);

      expect(assignment.familyPhone, isNull);
      expect(assignment.familySize, 0);
      expect(assignment.familyLocationVerified, false);
      expect(assignment.items, isEmpty);
      expect(assignment.itemUnits, isEmpty);
      expect(assignment.inKindCoveredItems, isEmpty);
      expect(assignment.assignedDistributorId, isNull);
      expect(assignment.assignedDistributorName, isNull);
      expect(assignment.failureReason, isNull);
      expect(assignment.failureNotes, isNull);
      expect(assignment.proofPhotoUrl, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DeliveryAssignment — toFirestore
  // ─────────────────────────────────────────────────────────────────
  group('DeliveryAssignment.toFirestore', () {
    test('serializes status field as Firestore string', () {
      final now = DateTime.now();
      final assignment = DeliveryAssignment(
        id: 'del_001',
        familyId: 'fam_001',
        familyArea: 'Test Area',
        familyCity: 'Test City',
        familyAddress: 'Test Address',
        familySize: 4,
        familyLocationVerified: false,
        items: const {},
        itemUnits: const {},
        inKindCoveredItems: const [],
        status: DeliveryStatus.inTransit,
        createdAt: now,
        updatedAt: now,
      );

      final map = assignment.toFirestore();
      expect(map['status'], 'in_transit');
      expect(map['familyId'], 'fam_001');
      expect(map['familyArea'], 'Test Area');
    });

    test('serializes failure reason when present', () {
      final now = DateTime.now();
      final assignment = DeliveryAssignment(
        id: 'del_002',
        familyId: 'fam_002',
        familyArea: 'Area',
        familyCity: 'City',
        familyAddress: 'Address',
        familySize: 2,
        familyLocationVerified: false,
        items: const {},
        itemUnits: const {},
        inKindCoveredItems: const [],
        status: DeliveryStatus.failed,
        failureReason: DeliveryFailureReason.addressIncorrect,
        failureNotes: 'Address could not be found',
        createdAt: now,
        updatedAt: now,
      );

      final map = assignment.toFirestore();
      expect(map['status'], 'failed');
      expect(map['failureReason'], 'address_incorrect');
      expect(map['failureNotes'], 'Address could not be found');
    });
  });

}
