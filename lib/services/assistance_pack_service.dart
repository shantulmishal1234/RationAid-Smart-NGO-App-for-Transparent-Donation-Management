import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/services/audit_service.dart';

/// Service for managing assistance packs
class AssistancePackService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'assistance_packs';

  /// Create new assistance pack
  static Future<String> createPack(AssistancePack pack) async {
    try {
      final docRef = await _firestore.collection(_collection).add(pack.toMap());

      // Log audit
      await AuditService.logAction(
        action: 'create_assistance_pack',
        entityType: 'assistance_pack',
        entityId: docRef.id,
        details: 'Created assistance pack: ${pack.name}',
        metadata: {
          'packName': pack.name,
          'packType': pack.packType,
          'minMembers': pack.minMembers,
          'maxMembers': pack.maxMembers,
          'budgetAmount': pack.budgetAmount,
        },
      );

      return docRef.id;
    } catch (e) {
      print('Error creating pack: $e');
      rethrow;
    }
  }

  /// Update existing assistance pack
  static Future<void> updatePack(String packId, AssistancePack pack) async {
    try {
      await _firestore.collection(_collection).doc(packId).update(pack.toMap());

      // Log audit
      await AuditService.logAction(
        action: 'update_assistance_pack',
        entityType: 'assistance_pack',
        entityId: packId,
        details: 'Updated assistance pack: ${pack.name}',
        metadata: {'packName': pack.name, 'packType': pack.packType},
      );
    } catch (e) {
      print('Error updating pack: $e');
      rethrow;
    }
  }

  /// Delete assistance pack (soft delete - mark as inactive)
  static Future<void> deletePack(String packId) async {
    try {
      await _firestore.collection(_collection).doc(packId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log audit
      await AuditService.logAction(
        action: 'delete_assistance_pack',
        entityType: 'assistance_pack',
        entityId: packId,
        details: 'Deleted assistance pack (soft delete)',
      );
    } catch (e) {
      print('Error deleting pack: $e');
      rethrow;
    }
  }

  /// Toggle pack active status
  static Future<void> toggleActiveStatus(String packId, bool isActive) async {
    try {
      await _firestore.collection(_collection).doc(packId).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log audit
      await AuditService.logAction(
        action: 'toggle_pack_status',
        entityType: 'assistance_pack',
        entityId: packId,
        details: 'Toggled pack status to ${isActive ? "active" : "inactive"}',
      );
    } catch (e) {
      print('Error toggling pack status: $e');
      rethrow;
    }
  }

  /// Stream all assistance packs
  static Stream<QuerySnapshot> getPacksStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get active packs only
  static Future<List<AssistancePack>> getActivePacks() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => AssistancePack.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting active packs: $e');
      return [];
    }
  }

  /// Get pack by ID
  static Future<AssistancePack?> getPackById(String packId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(packId).get();
      if (doc.exists) {
        return AssistancePack.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting pack by ID: $e');
      return null;
    }
  }

  /// Find best matching pack for family size
  /// Priority: exact fit (smallest range), then lower budget
  static Future<AssistancePack?> findMatchingPack(int familySize) async {
    try {
      // Get all active packs
      final activePacks = await getActivePacks();

      // Filter packs that match family size
      final matchingPacks = activePacks.where((pack) {
        return familySize >= pack.minMembers && familySize <= pack.maxMembers;
      }).toList();

      if (matchingPacks.isEmpty) return null;

      // Sort by range size (smaller is better), then by budget (lower is better)
      matchingPacks.sort((a, b) {
        final rangeA = a.maxMembers - a.minMembers;
        final rangeB = b.maxMembers - b.minMembers;

        if (rangeA != rangeB) {
          return rangeA.compareTo(rangeB);
        } else {
          return a.budgetAmount.compareTo(b.budgetAmount);
        }
      });

      return matchingPacks.first;
    } catch (e) {
      print('Error finding matching pack: $e');
      return null;
    }
  }

  /// Assign pack to family
  static Future<void> assignPackToFamily({
    required String familyId,
    required String packId,
    required String packName,
    required double packBudget,
  }) async {
    try {
      await _firestore.collection('families').doc(familyId).update({
        'assignedPackId': packId,
        'assignedPackName': packName,
        'assignedPackBudget': packBudget,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log audit
      await AuditService.logAction(
        action: 'assign_pack_to_family',
        entityType: 'family',
        entityId: familyId,
        details: 'Assigned assistance pack: $packName',
        metadata: {
          'packId': packId,
          'packName': packName,
          'packBudget': packBudget,
        },
      );
    } catch (e) {
      print('Error assigning pack to family: $e');
      rethrow;
    }
  }
}
