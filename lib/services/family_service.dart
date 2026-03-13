import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/family_model.dart';

/// Service for accessing family data (read-only for donors)
/// Only shows accepted families with masked data
class FamilyService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream all accepted families for donor view
  Stream<List<Family>> streamAcceptedFamilies() {
    return _firestore
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Family.fromFirestore(doc))
              .where((f) => f.id != 'general_relief_fund')
              .toList();
        });
  }

  /// Get single family by ID (only if accepted)
  Future<Family?> getFamilyById(String familyId) async {
    try {
      final doc = await _firestore.collection('families').doc(familyId).get();

      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;

      // Only return if status is accepted
      if (data['status'] != 'accepted') {
        return null;
      }

      return Family.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get family: $e');
    }
  }

  /// Get accepted families by area filter
  Stream<List<Family>> streamAcceptedFamiliesByArea(String area) {
    return _firestore
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .where('area', isEqualTo: area)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Family.fromFirestore(doc))
              .where((f) => f.id != 'general_relief_fund')
              .toList();
        });
  }

  /// Get list of unique areas (for filter options)
  Future<List<String>> getAvailableAreas() async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      final areas = snapshot.docs
          .map((doc) => (doc.data()['area'] ?? '') as String)
          .where((area) => area.isNotEmpty && area != 'General Relief Fund')
          .toSet()
          .toList();

      areas.sort();
      return areas;
    } catch (e) {
      throw Exception('Failed to get available areas: $e');
    }
  }

  /// Get count of accepted families
  Future<int> getAcceptedFamiliesCount() async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      return snapshot.docs
          .where((doc) => doc.id != 'general_relief_fund')
          .length;
    } catch (e) {
      return 0;
    }
  }

  /// Search families by area (case-insensitive)
  Future<List<Family>> searchFamiliesByArea(String searchQuery) async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      final families = snapshot.docs
          .map((doc) => Family.fromFirestore(doc))
          .where((f) => f.id != 'general_relief_fund')
          .where(
            (family) =>
                family.area.toLowerCase().contains(searchQuery.toLowerCase()),
          )
          .toList();

      return families;
    } catch (e) {
      throw Exception('Failed to search families: $e');
    }
  }
}
