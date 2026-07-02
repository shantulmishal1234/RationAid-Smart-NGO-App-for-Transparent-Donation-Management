import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/procurement_model.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // ProcurementStatus Enum
  // ─────────────────────────────────────────────────────────────────
  group('ProcurementStatus', () {
    test('enum contains all 9 defined statuses', () {
      expect(ProcurementStatus.values.length, 9);
      expect(ProcurementStatus.values, contains(ProcurementStatus.pending));
      expect(ProcurementStatus.values, contains(ProcurementStatus.purchased));
      expect(ProcurementStatus.values, contains(ProcurementStatus.verified));
      expect(ProcurementStatus.values, contains(ProcurementStatus.rejected));
      expect(ProcurementStatus.values, contains(ProcurementStatus.stocked));
      expect(ProcurementStatus.values, contains(ProcurementStatus.in_transit));
      expect(ProcurementStatus.values, contains(ProcurementStatus.delivered));
      expect(ProcurementStatus.values, contains(ProcurementStatus.issue_reported));
      expect(ProcurementStatus.values, contains(ProcurementStatus.written_off));
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ProcurementItem
  // ─────────────────────────────────────────────────────────────────
  group('ProcurementItem', () {
    test('creates with all required fields and defaults', () {
      final item = ProcurementItem(
        name: 'Rice',
        quantity: '10',
        unit: 'kg',
        estimatedCost: 800.0,
      );
      expect(item.name, 'Rice');
      expect(item.quantity, '10');
      expect(item.unit, 'kg');
      expect(item.estimatedCost, 800.0);
      expect(item.actualCost, 0.0); // default
      expect(item.isPurchased, false); // default
      expect(item.isInKindCovered, false); // default
    });

    test('quantityWithUnit returns "10 kg" when unit is non-empty', () {
      final item = ProcurementItem(name: 'Rice', quantity: '10', unit: 'kg', estimatedCost: 800.0);
      expect(item.quantityWithUnit, '10 kg');
    });

    test('quantityWithUnit returns quantity only when unit is empty', () {
      final item = ProcurementItem(name: 'Packets', quantity: '5', unit: '', estimatedCost: 200.0);
      expect(item.quantityWithUnit, '5');
    });

    test('toMap serializes all fields correctly', () {
      final item = ProcurementItem(
        name: 'Flour',
        quantity: '5',
        unit: 'kg',
        estimatedCost: 600.0,
        actualCost: 580.0,
        isPurchased: true,
        isInKindCovered: false,
      );

      final map = item.toMap();
      expect(map['name'], 'Flour');
      expect(map['quantity'], '5');
      expect(map['unit'], 'kg');
      expect(map['estimatedCost'], 600.0);
      expect(map['actualCost'], 580.0);
      expect(map['isPurchased'], true);
      expect(map['isInKindCovered'], false);
    });

    test('fromMap parses all fields correctly', () {
      final map = {
        'name': 'Sugar',
        'quantity': '2',
        'unit': 'kg',
        'estimatedCost': 300.0,
        'actualCost': 290.0,
        'isPurchased': true,
        'isInKindCovered': true,
      };
      final item = ProcurementItem.fromMap(map);

      expect(item.name, 'Sugar');
      expect(item.quantity, '2');
      expect(item.unit, 'kg');
      expect(item.estimatedCost, 300.0);
      expect(item.actualCost, 290.0);
      expect(item.isPurchased, true);
      expect(item.isInKindCovered, true);
    });

    test('fromMap handles missing optional fields with defaults', () {
      final map = {'name': 'Salt', 'quantity': '1', 'estimatedCost': 50.0};
      final item = ProcurementItem.fromMap(map);

      expect(item.unit, '');
      expect(item.actualCost, 0.0);
      expect(item.isPurchased, false);
      expect(item.isInKindCovered, false);
    });

    test('toMap and fromMap round-trip preserves values', () {
      final original = ProcurementItem(
        name: 'Cooking Oil',
        quantity: '3',
        unit: 'L',
        estimatedCost: 1200.0,
        actualCost: 1180.0,
        isPurchased: true,
        isInKindCovered: false,
      );

      final restored = ProcurementItem.fromMap(original.toMap());

      expect(restored.name, original.name);
      expect(restored.quantity, original.quantity);
      expect(restored.unit, original.unit);
      expect(restored.estimatedCost, original.estimatedCost);
      expect(restored.actualCost, original.actualCost);
      expect(restored.isPurchased, original.isPurchased);
    });

    test('copyWith updates only specified fields', () {
      final original = ProcurementItem(
        name: 'Rice',
        quantity: '10',
        unit: 'kg',
        estimatedCost: 800.0,
        actualCost: 0.0,
        isPurchased: false,
      );

      final updated = original.copyWith(
        actualCost: 790.0,
        isPurchased: true,
      );

      expect(updated.actualCost, 790.0);
      expect(updated.isPurchased, true);
      // Preserved fields
      expect(updated.name, 'Rice');
      expect(updated.quantity, '10');
      expect(updated.estimatedCost, 800.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // ProcurementRequest — fromFirestore
  // ─────────────────────────────────────────────────────────────────
  group('ProcurementRequest.fromFirestore', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('correctly parses a full procurement request document', () async {
      final now = Timestamp.now();

      await fakeFirestore
          .collection('procurement_requests')
          .doc('proc_001')
          .set({
        'familyId': 'family_abc',
        'familyAddress': 'Gulshan Block 7',
        'packId': 'pack_001',
        'packName': 'Basic Food Pack',
        'category': 'Food',
        'items': [
          {'name': 'Rice', 'quantity': '10', 'unit': 'kg', 'estimatedCost': 800.0, 'actualCost': 0.0, 'isPurchased': false, 'isInKindCovered': false},
          {'name': 'Flour', 'quantity': '5', 'unit': 'kg', 'estimatedCost': 600.0, 'actualCost': 0.0, 'isPurchased': false, 'isInKindCovered': false},
        ],
        'budgetLimit': 15000.0,
        'totalSpent': 0.0,
        'status': 'pending',
        'purchaserId': 'purch_001',
        'purchaserName': 'Bilal Ahmed',
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('procurement_requests').doc('proc_001').get();
      final request = ProcurementRequest.fromFirestore(doc);

      expect(request.id, 'proc_001');
      expect(request.familyId, 'family_abc');
      expect(request.familyAddress, 'Gulshan Block 7');
      expect(request.packId, 'pack_001');
      expect(request.packName, 'Basic Food Pack');
      expect(request.category, 'Food');
      expect(request.items.length, 2);
      expect(request.items[0].name, 'Rice');
      expect(request.budgetLimit, 15000.0);
      expect(request.totalSpent, 0.0);
      expect(request.status, ProcurementStatus.pending);
      expect(request.purchaserId, 'purch_001');
      expect(request.purchaserName, 'Bilal Ahmed');
    });

    test('parses all procurement status values from Firestore', () async {
      final statusMap = {
        'pending': ProcurementStatus.pending,
        'purchased': ProcurementStatus.purchased,
        'verified': ProcurementStatus.verified,
        'rejected': ProcurementStatus.rejected,
        'stocked': ProcurementStatus.stocked,
        'in_transit': ProcurementStatus.in_transit,
        'delivered': ProcurementStatus.delivered,
        'issue_reported': ProcurementStatus.issue_reported,
        'written_off': ProcurementStatus.written_off,
      };

      for (final entry in statusMap.entries) {
        final now = Timestamp.now();
        await fakeFirestore
            .collection('procurement_requests')
            .doc('proc_status_${entry.key}')
            .set({
          'familyId': 'fam',
          'familyAddress': 'Addr',
          'packId': 'pack',
          'packName': 'Pack',
          'category': 'Food',
          'items': [],
          'budgetLimit': 0.0,
          'totalSpent': 0.0,
          'status': entry.key,
          'createdAt': now,
        });

        final doc = await fakeFirestore
            .collection('procurement_requests')
            .doc('proc_status_${entry.key}')
            .get();
        final request = ProcurementRequest.fromFirestore(doc);
        expect(
          request.status,
          entry.value,
          reason: 'Status parsing failed for: ${entry.key}',
        );
      }
    });

    test('handles missing optional fields with correct defaults', () async {
      final now = Timestamp.now();
      await fakeFirestore
          .collection('procurement_requests')
          .doc('proc_002')
          .set({
        'familyId': 'fam_002',
        'familyAddress': 'Area',
        'packId': 'pack_002',
        'packName': 'Pack',
        'category': 'Food',
        'items': [],
        'budgetLimit': 5000.0,
        'totalSpent': 0.0,
        'status': 'pending',
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('procurement_requests').doc('proc_002').get();
      final request = ProcurementRequest.fromFirestore(doc);

      expect(request.purchaserId, isNull);
      expect(request.purchaserName, isNull);
      expect(request.receiptUrl, isNull);
      expect(request.adminRemarks, isNull);
      expect(request.issueType, isNull);
      expect(request.claimedById, isNull);
      expect(request.claimedByName, isNull);
      expect(request.purchasedAt, isNull);
      expect(request.verifiedAt, isNull);
    });
  });
}
