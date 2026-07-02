import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/warehouse_stock_model.dart';

void main() {
  group('WarehouseStock', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // ─────────────────────────────────────────────────────────────────
    // fromFirestore
    // ─────────────────────────────────────────────────────────────────
    test('correctly parses a full warehouse stock document', () async {
      final now = Timestamp.now();
      final receivedAt = Timestamp.fromDate(DateTime(2024, 6, 1));

      await fakeFirestore.collection('warehouse_stock').doc('stock_001').set({
        'familyId': 'family_abc',
        'donationId': 'don_001',
        'donorId': 'donor_xyz',
        'donorName': 'Ahmed Ali',
        'items': {'Rice': 10, 'Flour': 5, 'Oil': 3},
        'itemValueSnapshot': {'Rice': 800.0, 'Flour': 600.0, 'Oil': 1200.0},
        'totalLockedValue': 2600.0,
        'status': 'received',
        'pickupAddress': '123 Main St, Karachi',
        'contactNumber': '03001234567',
        'inboundPickupId': 'pickup_001',
        'pickupProofUrl': 'https://cloudinary.com/proof.jpg',
        'receivedAt': receivedAt,
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('warehouse_stock').doc('stock_001').get();
      final stock = WarehouseStock.fromFirestore(doc);

      expect(stock.id, 'stock_001');
      expect(stock.familyId, 'family_abc');
      expect(stock.donationId, 'don_001');
      expect(stock.donorId, 'donor_xyz');
      expect(stock.donorName, 'Ahmed Ali');
      expect(stock.items['Rice'], 10);
      expect(stock.items['Flour'], 5);
      expect(stock.items['Oil'], 3);
      expect(stock.itemValueSnapshot['Rice'], 800.0);
      expect(stock.itemValueSnapshot['Oil'], 1200.0);
      expect(stock.totalLockedValue, 2600.0);
      expect(stock.status, 'received');
      expect(stock.pickupAddress, '123 Main St, Karachi');
      expect(stock.contactNumber, '03001234567');
      expect(stock.inboundPickupId, 'pickup_001');
      expect(stock.pickupProofUrl, 'https://cloudinary.com/proof.jpg');
      expect(stock.receivedAt, isNotNull);
    });

    test('handles missing optional fields with correct defaults', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('warehouse_stock').doc('stock_002').set({
        'familyId': 'family_def',
        'donationId': 'don_002',
        'donorId': 'donor_abc',
        'donorName': 'Fatima Khan',
        'items': {'Milk': 6},
        'itemValueSnapshot': {'Milk': 300.0},
        'totalLockedValue': 1800.0,
        'status': 'pending_pickup',
        'pickupAddress': 'Block 4, Clifton',
        'contactNumber': '03111234567',
        'createdAt': now,
      });

      final doc =
          await fakeFirestore.collection('warehouse_stock').doc('stock_002').get();
      final stock = WarehouseStock.fromFirestore(doc);

      expect(stock.inboundPickupId, isNull);
      expect(stock.pickupProofUrl, isNull);
      expect(stock.receivedAt, isNull);
      expect(stock.dispatchedAt, isNull);
    });


    // ─────────────────────────────────────────────────────────────────
    // toFirestore
    // ─────────────────────────────────────────────────────────────────
    test('toFirestore serializes all non-null fields correctly', () {
      final now = DateTime(2024, 6, 15);
      final receivedAt = DateTime(2024, 6, 16);

      final stock = WarehouseStock(
        id: 'stock_001',
        familyId: 'fam_001',
        donationId: 'don_001',
        donorId: 'donor_001',
        donorName: 'Test Donor',
        items: const {'Rice': 10},
        itemValueSnapshot: const {'Rice': 800.0},
        totalLockedValue: 8000.0,
        status: 'pending_pickup',
        pickupAddress: '123 Test St',
        contactNumber: '03001234567',
        createdAt: now,
        receivedAt: receivedAt,
        inboundPickupId: 'pickup_001',
      );

      final map = stock.toFirestore();

      expect(map['familyId'], 'fam_001');
      expect(map['donationId'], 'don_001');
      expect(map['donorName'], 'Test Donor');
      expect(map['items']['Rice'], 10);
      expect(map['itemValueSnapshot']['Rice'], 800.0);
      expect(map['totalLockedValue'], 8000.0);
      expect(map['status'], 'pending_pickup');
      expect(map['pickupAddress'], '123 Test St');
      expect(map['contactNumber'], '03001234567');
      expect(map['receivedAt'], isA<Timestamp>());
      expect(map['inboundPickupId'], 'pickup_001');
      // createdAt uses serverTimestamp
      expect(map['createdAt'], isNotNull);
    });

    test('toFirestore omits null optional fields', () {
      final now = DateTime(2024, 6, 15);
      final stock = WarehouseStock(
        id: 'stock_002',
        familyId: 'fam_002',
        donationId: 'don_002',
        donorId: 'donor_002',
        donorName: 'Test Donor',
        items: const {},
        itemValueSnapshot: const {},
        totalLockedValue: 0.0,
        status: 'pending_pickup',
        pickupAddress: 'Test',
        contactNumber: '0300',
        createdAt: now,
        // All optional fields null
      );

      final map = stock.toFirestore();

      expect(map.containsKey('inboundPickupId'), false);
      expect(map.containsKey('pickupProofUrl'), false);
      expect(map.containsKey('receivedAt'), false);
      expect(map.containsKey('dispatchedAt'), false);
    });

    // ─────────────────────────────────────────────────────────────────
    // copyWith
    // ─────────────────────────────────────────────────────────────────
    test('copyWith updates status and timestamps without changing identity fields', () {
      final now = DateTime.now();
      final stock = WarehouseStock(
        id: 'stock_001',
        familyId: 'fam_001',
        donationId: 'don_001',
        donorId: 'donor_001',
        donorName: 'Original Donor',
        items: const {'Rice': 10},
        itemValueSnapshot: const {},
        totalLockedValue: 8000.0,
        status: 'pending_pickup',
        pickupAddress: '123 St',
        contactNumber: '0300',
        createdAt: now,
      );

      final updated = stock.copyWith(
        status: 'received',
        pickupProofUrl: 'https://cloudinary.com/new_proof.jpg',
        receivedAt: DateTime(2024, 7, 1),
      );

      // Updated fields
      expect(updated.status, 'received');
      expect(updated.pickupProofUrl, 'https://cloudinary.com/new_proof.jpg');
      expect(updated.receivedAt, DateTime(2024, 7, 1));

      // Preserved identity fields
      expect(updated.id, 'stock_001');
      expect(updated.familyId, 'fam_001');
      expect(updated.donationId, 'don_001');
      expect(updated.donorName, 'Original Donor');
      expect(updated.items['Rice'], 10);
    });
  });
}
