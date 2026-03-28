import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/funding_service.dart';

class InventoryService {
  static final _db = FirebaseFirestore.instance;

  /// Transfers a warehouse stock entry from one family to another.
  /// This is used when an admin decides to re-route incoming or stored goods.
  static Future<void> transferStock({
    required String stockId,
    required String fromFamilyId,
    required String toFamilyId,
    required String adminUid,
  }) async {
    await _db.runTransaction((tx) async {
      final stockRef = _db.collection('warehouse_stock').doc(stockId);
      final fromFamilyRef = _db.collection('families').doc(fromFamilyId);
      final toFamilyRef = _db.collection('families').doc(toFamilyId);

      final stockSnap = await tx.get(stockRef);
      final fromSnap = await tx.get(fromFamilyRef);
      final toSnap = await tx.get(toFamilyRef);

      if (!stockSnap.exists) throw Exception('Stock record not found');
      if (!fromSnap.exists) throw Exception('Source family not found');
      if (!toSnap.exists) throw Exception('Target family not found');

      final stockData = stockSnap.data()!;
      final items = Map<String, num>.from(stockData['items'] ?? {});
      final double stockValue = (stockData['totalLockedValue'] ?? 0).toDouble();

      // 1. Revert Source Family
      final fromData = fromSnap.data()!;
      final fromNeeds = Map<String, dynamic>.from(fromData['needs'] ?? {});
      final Map<String, dynamic> fromUpdate = {};
      items.forEach((item, qty) {
        final current = fromNeeds[item] ?? 0;
        fromUpdate['needs.$item'] = current + qty;
      });
      fromUpdate['inKindValue'] = FieldValue.increment(-stockValue);
      fromUpdate['combinedProgress'] = FieldValue.increment(-stockValue);
      fromUpdate['updatedAt'] = FieldValue.serverTimestamp();
      tx.update(fromFamilyRef, fromUpdate);

      // 2. Apply to Target Family
      final toData = toSnap.data()!;
      final toNeeds = Map<String, dynamic>.from(toData['needs'] ?? {});
      final Map<String, dynamic> toUpdate = {};
      items.forEach((item, qty) {
        final current = toNeeds[item] ?? 0;
        toUpdate['needs.$item'] = (current - qty).clamp(0, 99999);
      });
      toUpdate['inKindValue'] = FieldValue.increment(stockValue);
      toUpdate['combinedProgress'] = FieldValue.increment(stockValue);
      toUpdate['updatedAt'] = FieldValue.serverTimestamp();
      tx.update(toFamilyRef, toUpdate);

      // 3. Update Stock Record
      tx.update(stockRef, {
        'familyId': toFamilyId,
        'updatedAt': FieldValue.serverTimestamp(),
        'transferHistory': FieldValue.arrayUnion([
          {
            'fromFamilyId': fromFamilyId,
            'toFamilyId': toFamilyId,
            'timestamp': Timestamp.now(),
            'adminUid': adminUid,
          },
        ]),
      });

      // 4. Update linked Inbound Pickup if it exists
      final pickupId = stockData['inboundPickupId'];
      if (pickupId != null) {
        tx.update(_db.collection('inbound_pickups').doc(pickupId), {
          'familyId': toFamilyId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // Post-transaction recalculations (non-atomic but safe due to periodic sweeps)
    await FundingService.recalculateFamilyFunding(fromFamilyId);
    await FundingService.recalculateFamilyFunding(toFamilyId);

    await AuditService.logAction(
      action: 'inventory_transfer',
      entityType: 'warehouse_stock',
      entityId: stockId,
      details: 'Transferred from $fromFamilyId to $toFamilyId by $adminUid',
    );
  }
}
