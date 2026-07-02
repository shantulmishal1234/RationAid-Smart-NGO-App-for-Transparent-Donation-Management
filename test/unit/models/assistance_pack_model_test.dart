import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // PackItem
  // ─────────────────────────────────────────────────────────────────
  group('PackItem', () {
    test('creates with all required fields', () {
      final item = PackItem(
        name: 'Rice',
        quantityNum: 10.0,
        unit: 'kg',
        estimatedCost: 800.0,
      );
      expect(item.name, 'Rice');
      expect(item.quantityNum, 10.0);
      expect(item.unit, 'kg');
      expect(item.estimatedCost, 800.0);
    });

    test('quantity getter returns formatted string "10 kg"', () {
      final item = PackItem(name: 'Rice', quantityNum: 10.0, unit: 'kg', estimatedCost: 800.0);
      expect(item.quantity, '10 kg');
    });

    test('quantity getter strips trailing zero: 3.0 → "3 kg"', () {
      final item = PackItem(name: 'Oil', quantityNum: 3.0, unit: 'L', estimatedCost: 600.0);
      expect(item.quantity, '3 L');
    });

    test('quantity getter preserves decimal: 3.5 → "3.5 kg"', () {
      final item = PackItem(name: 'Flour', quantityNum: 3.5, unit: 'kg', estimatedCost: 200.0);
      expect(item.quantity, '3.5 kg');
    });

    test('toMap serializes all fields correctly', () {
      final item = PackItem(
        name: 'Sugar',
        quantityNum: 2.0,
        unit: 'kg',
        estimatedCost: 300.0,
      );
      final map = item.toMap();

      expect(map['name'], 'Sugar');
      expect(map['quantityNum'], 2.0);
      expect(map['unit'], 'kg');
      expect(map['quantity'], '2 kg'); // legacy backward-compat string
      expect(map['estimatedCost'], 300.0);
    });

    test('fromMap parses new explicit fields correctly', () {
      final map = {
        'name': 'Dates',
        'quantityNum': 1.5,
        'unit': 'kg',
        'estimatedCost': 500.0,
      };
      final item = PackItem.fromMap(map);

      expect(item.name, 'Dates');
      expect(item.quantityNum, 1.5);
      expect(item.unit, 'kg');
      expect(item.estimatedCost, 500.0);
    });

    test('fromMap falls back to parsing legacy quantity string "3.5 kg"', () {
      final map = {
        'name': 'Lentils',
        'quantity': '3.5 kg',
        'estimatedCost': 250.0,
      };
      final item = PackItem.fromMap(map);

      expect(item.quantityNum, 3.5);
      expect(item.unit, 'kg');
    });

    test('fromMap handles legacy quantity string with no unit', () {
      final map = {
        'name': 'Salt',
        'quantity': '500',
        'estimatedCost': 50.0,
      };
      final item = PackItem.fromMap(map);

      expect(item.quantityNum, 500.0);
    });

    test('fromMap handles missing quantity gracefully with defaults', () {
      final map = {'name': 'Unknown', 'estimatedCost': 100.0};
      final item = PackItem.fromMap(map);

      expect(item.quantityNum, 1.0);
      expect(item.unit, 'kg');
    });

    test('toMap and fromMap round-trip preserves values', () {
      final original = PackItem(
        name: 'Cooking Oil',
        quantityNum: 5.0,
        unit: 'L',
        estimatedCost: 1500.0,
      );
      final restored = PackItem.fromMap(original.toMap());

      expect(restored.name, original.name);
      expect(restored.quantityNum, original.quantityNum);
      expect(restored.unit, original.unit);
      expect(restored.estimatedCost, original.estimatedCost);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // AssistancePack
  // ─────────────────────────────────────────────────────────────────
  group('AssistancePack', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('fromFirestore correctly parses all fields', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('packs').doc('pack_001').set({
        'name': 'Basic Food Pack',
        'packType': 'food',
        'description': 'Essential food items for 4-6 members',
        'minMembers': 4,
        'maxMembers': 6,
        'budgetAmount': 15000.0,
        'isActive': true,
        'createdAt': now,
        'updatedAt': now,
        'items': [
          {
            'name': 'Rice',
            'quantityNum': 10.0,
            'unit': 'kg',
            'estimatedCost': 800.0,
            'quantity': '10 kg',
          },
          {
            'name': 'Flour',
            'quantityNum': 5.0,
            'unit': 'kg',
            'estimatedCost': 600.0,
            'quantity': '5 kg',
          },
        ],
      });

      final doc = await fakeFirestore.collection('packs').doc('pack_001').get();
      final pack = AssistancePack.fromFirestore(doc);

      expect(pack.id, 'pack_001');
      expect(pack.name, 'Basic Food Pack');
      expect(pack.packType, 'food');
      expect(pack.description, 'Essential food items for 4-6 members');
      expect(pack.minMembers, 4);
      expect(pack.maxMembers, 6);
      expect(pack.budgetAmount, 15000.0);
      expect(pack.isActive, true);
      expect(pack.items.length, 2);
      expect(pack.items[0].name, 'Rice');
      expect(pack.items[1].name, 'Flour');
    });

    test('fromFirestore uses default values for missing fields', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('packs').doc('pack_002').set({
        'name': 'Minimal Pack',
        'packType': 'medicine',
        'createdAt': now,
        'updatedAt': now,
      });

      final doc = await fakeFirestore.collection('packs').doc('pack_002').get();
      final pack = AssistancePack.fromFirestore(doc);

      expect(pack.minMembers, 1);
      expect(pack.maxMembers, 1);
      expect(pack.budgetAmount, 0.0);
      expect(pack.isActive, true);
      expect(pack.items, isEmpty);
      expect(pack.description, isNull);
    });

    test('toMap serializes all fields correctly', () {
      final now = DateTime(2024, 6, 15);
      final pack = AssistancePack(
        id: 'pack_001',
        name: 'Test Pack',
        packType: 'food',
        description: 'A test pack',
        minMembers: 2,
        maxMembers: 4,
        budgetAmount: 10000.0,
        items: [
          PackItem(name: 'Rice', quantityNum: 5.0, unit: 'kg', estimatedCost: 400.0),
        ],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final map = pack.toMap();

      expect(map['name'], 'Test Pack');
      expect(map['packType'], 'food');
      expect(map['description'], 'A test pack');
      expect(map['minMembers'], 2);
      expect(map['maxMembers'], 4);
      expect(map['budgetAmount'], 10000.0);
      expect(map['isActive'], true);
      expect((map['items'] as List).length, 1);
      expect(map['createdAt'], isA<Timestamp>());
      expect(map['updatedAt'], isA<Timestamp>());
    });

    test('copyWith updates only specified fields', () {
      final now = DateTime.now();
      final pack = AssistancePack(
        id: 'pack_001',
        name: 'Original Pack',
        packType: 'food',
        minMembers: 2,
        maxMembers: 5,
        budgetAmount: 10000.0,
        items: [],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final updated = pack.copyWith(
        name: 'Updated Pack',
        isActive: false,
        budgetAmount: 20000.0,
      );

      // Updated fields
      expect(updated.name, 'Updated Pack');
      expect(updated.isActive, false);
      expect(updated.budgetAmount, 20000.0);

      // Preserved fields
      expect(updated.id, 'pack_001');
      expect(updated.packType, 'food');
      expect(updated.minMembers, 2);
      expect(updated.maxMembers, 5);
    });
  });
}
