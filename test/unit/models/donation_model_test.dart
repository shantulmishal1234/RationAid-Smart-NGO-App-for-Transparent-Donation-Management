import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/master_ledger_model.dart';


void main() {
  // ─────────────────────────────────────────────────────────────────
  // DonationStatus Enum
  // ─────────────────────────────────────────────────────────────────
  group('DonationStatus', () {
    test('toFirestore returns correct string for all 11 statuses', () {
      expect(DonationStatus.draft.toFirestore(), 'draft');
      expect(DonationStatus.pending.toFirestore(), 'pending');
      expect(DonationStatus.underVerification.toFirestore(), 'under_verification');
      expect(DonationStatus.verified.toFirestore(), 'verified');
      expect(DonationStatus.pendingAssignment.toFirestore(), 'pending_assignment');
      expect(DonationStatus.stocked.toFirestore(), 'stocked');
      expect(DonationStatus.inProcess.toFirestore(), 'in_process');
      expect(DonationStatus.outForDelivery.toFirestore(), 'out_for_delivery');
      expect(DonationStatus.delivered.toFirestore(), 'delivered');
      expect(DonationStatus.closed.toFirestore(), 'closed');
      expect(DonationStatus.rejected.toFirestore(), 'rejected');
    });

    test('fromFirestore parses all known Firestore status strings', () {
      expect(DonationStatus.fromFirestore('draft'), DonationStatus.draft);
      expect(DonationStatus.fromFirestore('pending'), DonationStatus.pending);
      expect(DonationStatus.fromFirestore('under_verification'), DonationStatus.underVerification);
      expect(DonationStatus.fromFirestore('verified'), DonationStatus.verified);
      expect(DonationStatus.fromFirestore('pending_assignment'), DonationStatus.pendingAssignment);
      expect(DonationStatus.fromFirestore('stocked'), DonationStatus.stocked);
      expect(DonationStatus.fromFirestore('in_process'), DonationStatus.inProcess);
      expect(DonationStatus.fromFirestore('out_for_delivery'), DonationStatus.outForDelivery);
      expect(DonationStatus.fromFirestore('delivered'), DonationStatus.delivered);
      expect(DonationStatus.fromFirestore('closed'), DonationStatus.closed);
      expect(DonationStatus.fromFirestore('rejected'), DonationStatus.rejected);
    });

    test('fromFirestore maps pool_assigned to closed', () {
      expect(DonationStatus.fromFirestore('pool_assigned'), DonationStatus.closed);
    });

    test('fromFirestore returns draft for unknown status string', () {
      expect(DonationStatus.fromFirestore('something_random'), DonationStatus.draft);
      expect(DonationStatus.fromFirestore(''), DonationStatus.draft);
    });

    test('toFirestore and fromFirestore are a perfect round-trip for all statuses', () {
      for (final status in DonationStatus.values) {
        expect(
          DonationStatus.fromFirestore(status.toFirestore()),
          status,
          reason: 'Round-trip failed for $status',
        );
      }
    });

    test('displayName returns human-readable string for all statuses', () {
      expect(DonationStatus.draft.displayName, 'Draft');
      expect(DonationStatus.underVerification.displayName, 'Under Verification');
      expect(DonationStatus.pendingAssignment.displayName, 'Pending Assignment');
      expect(DonationStatus.stocked.displayName, 'In Warehouse');
      expect(DonationStatus.outForDelivery.displayName, 'Out for Delivery');
      expect(DonationStatus.delivered.displayName, 'Delivered');
      expect(DonationStatus.rejected.displayName, 'Rejected');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DonationType Enum
  // ─────────────────────────────────────────────────────────────────
  group('DonationType', () {
    test('toFirestore returns correct string', () {
      expect(DonationType.cash.toFirestore(), 'cash');
      expect(DonationType.inKind.toFirestore(), 'inKind');
    });

    test('fromFirestore parses cash correctly', () {
      expect(DonationType.fromFirestore('cash'), DonationType.cash);
    });

    test('fromFirestore returns inKind for any non-cash value', () {
      expect(DonationType.fromFirestore('inKind'), DonationType.inKind);
      expect(DonationType.fromFirestore('in_kind'), DonationType.inKind);
    });

    test('displayName returns correct human-readable labels', () {
      expect(DonationType.cash.displayName, 'Cash');
      expect(DonationType.inKind.displayName, 'In-Kind');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // StatusHistoryEntry
  // ─────────────────────────────────────────────────────────────────
  group('StatusHistoryEntry', () {
    test('toMap serializes correctly', () {
      final now = DateTime(2024, 1, 15, 10, 30);
      final entry = StatusHistoryEntry(
        status: DonationStatus.verified,
        timestamp: now,
        note: 'Admin verified',
      );

      final map = entry.toMap();

      expect(map['status'], 'verified');
      expect(map['note'], 'Admin verified');
      expect(map['timestamp'], isA<Timestamp>());
    });

    test('fromMap deserializes correctly', () {
      final now = DateTime(2024, 1, 15, 10, 30);
      final map = {
        'status': 'delivered',
        'timestamp': Timestamp.fromDate(now),
        'note': 'Delivered to family',
      };

      final entry = StatusHistoryEntry.fromMap(map);

      expect(entry.status, DonationStatus.delivered);
      expect(entry.note, 'Delivered to family');
      expect(entry.timestamp.year, 2024);
    });

    test('fromMap handles missing timestamp gracefully', () {
      final map = {'status': 'verified', 'note': 'test'};
      final entry = StatusHistoryEntry.fromMap(map);
      expect(entry.timestamp, isNotNull);
    });

    test('fromMap handles missing status with draft fallback', () {
      final map = {'timestamp': Timestamp.now(), 'note': 'fallback test'};
      final entry = StatusHistoryEntry.fromMap(map);
      expect(entry.status, DonationStatus.draft);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // Donation Model — fromFirestore
  // ─────────────────────────────────────────────────────────────────
  group('Donation.fromFirestore', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('correctly parses a cash donation document', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('donations').doc('don_001').set({
        'donorId': 'donor_abc',
        'donorName': 'Ahmed Ali',
        'donorEmail': 'ahmed@test.com',
        'familyId': 'family_xyz',
        'donationType': 'cash',
        'amount': 5000.0,
        'anonymous': false,
        'status': 'verified',
        'createdAt': now,
        'updatedAt': now,
        'allocationMode': 'direct',
        'effectiveAmount': 5000.0,
        'overflowAmount': 0.0,
        'allocatedAmount': 0.0,
        'displacedAmount': 0.0,
        'idempotencyKey': 'key_001',
        'statusHistory': [],
        'deliveryPhotos': [],
      });

      final doc = await fakeFirestore.collection('donations').doc('don_001').get();
      final donation = Donation.fromFirestore(doc);

      expect(donation.id, 'don_001');
      expect(donation.donorId, 'donor_abc');
      expect(donation.donorName, 'Ahmed Ali');
      expect(donation.familyId, 'family_xyz');
      expect(donation.donationType, DonationType.cash);
      expect(donation.amount, 5000.0);
      expect(donation.anonymous, false);
      expect(donation.status, DonationStatus.verified);
      expect(donation.allocationMode, 'direct');
      expect(donation.effectiveAmount, 5000.0);
    });

    test('correctly parses an in-kind donation document', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('donations').doc('don_002').set({
        'donorId': 'donor_def',
        'familyId': 'family_xyz',
        'donationType': 'inKind',
        'items': {'Rice': 10, 'Flour': 5},
        'itemUnits': {'Rice': 'kg', 'Flour': 'kg'},
        'anonymous': true,
        'status': 'under_verification',
        'createdAt': now,
        'updatedAt': now,
        'allocationMode': 'direct',
        'effectiveAmount': 0.0,
        'overflowAmount': 0.0,
        'allocatedAmount': 0.0,
        'displacedAmount': 0.0,
        'idempotencyKey': 'key_002',
        'statusHistory': [],
        'deliveryPhotos': [],
        'pickupAddress': '123 Main St',
        'contactNumber': '03001234567',
      });

      final doc = await fakeFirestore.collection('donations').doc('don_002').get();
      final donation = Donation.fromFirestore(doc);

      expect(donation.donationType, DonationType.inKind);
      expect(donation.items!['Rice'], 10);
      expect(donation.items!['Flour'], 5);
      expect(donation.itemUnits!['Rice'], 'kg');
      expect(donation.anonymous, true);
      expect(donation.status, DonationStatus.underVerification);
      expect(donation.pickupAddress, '123 Main St');
      expect(donation.contactNumber, '03001234567');
    });

    test('handles missing optional fields gracefully with correct defaults', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('donations').doc('don_003').set({
        'donorId': 'donor_ghi',
        'familyId': 'family_abc',
        'donationType': 'cash',
        'amount': 1000.0,
        'status': 'draft',
        'createdAt': now,
        'updatedAt': now,
        'idempotencyKey': 'key_003',
      });

      final doc = await fakeFirestore.collection('donations').doc('don_003').get();
      final donation = Donation.fromFirestore(doc);

      expect(donation.anonymous, false); // default
      expect(donation.statusHistory, isEmpty); // default
      expect(donation.deliveryPhotos, isEmpty); // default
      expect(donation.allocationMode, 'direct'); // default
      expect(donation.effectiveAmount, 1000.0); // falls back to amount field
      expect(donation.overflowAmount, 0.0); // default
      expect(donation.displacedAmount, 0.0); // default
      expect(donation.rejectionReason, isNull);
      expect(donation.driverName, isNull);
    });

    test('parses statusHistory list correctly', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('donations').doc('don_004').set({
        'donorId': 'donor_jkl',
        'familyId': 'family_def',
        'donationType': 'cash',
        'amount': 2000.0,
        'status': 'delivered',
        'createdAt': now,
        'updatedAt': now,
        'idempotencyKey': 'key_004',
        'statusHistory': [
          {'status': 'draft', 'timestamp': now, 'note': 'Created'},
          {'status': 'verified', 'timestamp': now, 'note': 'Admin verified'},
          {'status': 'delivered', 'timestamp': now, 'note': 'Delivered'},
        ],
        'deliveryPhotos': ['url1.jpg', 'url2.jpg'],
      });

      final doc = await fakeFirestore.collection('donations').doc('don_004').get();
      final donation = Donation.fromFirestore(doc);

      expect(donation.statusHistory.length, 3);
      expect(donation.statusHistory[0].status, DonationStatus.draft);
      expect(donation.statusHistory[1].status, DonationStatus.verified);
      expect(donation.statusHistory[2].status, DonationStatus.delivered);
      expect(donation.deliveryPhotos.length, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DonationSubmitResult
  // ─────────────────────────────────────────────────────────────────
  group('DonationSubmitResult', () {
    test('hadOverflow is true when overflowAmount > 0', () {
      final result = DonationSubmitResult(
        donationId: 'don_001',
        effectiveAmount: 4000,
        overflowAmount: 1000,
        targetFamilyId: 'fam_001',
      );
      expect(result.hadOverflow, true);
    });

    test('hadOverflow is false when overflowAmount is 0', () {
      final result = DonationSubmitResult(
        donationId: 'don_002',
        effectiveAmount: 5000,
        overflowAmount: 0,
        targetFamilyId: 'fam_001',
      );
      expect(result.hadOverflow, false);
    });
  });
}
