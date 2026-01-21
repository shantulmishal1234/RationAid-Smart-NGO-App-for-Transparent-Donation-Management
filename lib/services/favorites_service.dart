import 'package:cloud_firestore/cloud_firestore.dart';

/// Service to manage favorite/saved families for donors
class FavoritesService {
  static final _firestore = FirebaseFirestore.instance;

  /// Get the favorites subcollection for a user
  static CollectionReference _getFavoritesCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('favorites');
  }

  /// Add a family to favorites
  static Future<bool> addFavorite(String userId, String familyId) async {
    try {
      await _getFavoritesCollection(userId).doc(familyId).set({
        'familyId': familyId,
        'savedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove a family from favorites
  static Future<bool> removeFavorite(String userId, String familyId) async {
    try {
      await _getFavoritesCollection(userId).doc(familyId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Toggle favorite status
  static Future<bool> toggleFavorite(String userId, String familyId) async {
    final isFav = await isFavorite(userId, familyId);
    if (isFav) {
      return await removeFavorite(userId, familyId);
    } else {
      return await addFavorite(userId, familyId);
    }
  }

  /// Check if a family is in favorites
  static Future<bool> isFavorite(String userId, String familyId) async {
    try {
      final doc = await _getFavoritesCollection(userId).doc(familyId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Stream favorite family IDs for a user
  static Stream<List<String>> streamFavoriteIds(String userId) {
    return _getFavoritesCollection(userId)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
  }

  /// Get list of favorite family IDs (one-time)
  static Future<List<String>> getFavoriteIds(String userId) async {
    try {
      final snapshot = await _getFavoritesCollection(
        userId,
      ).orderBy('savedAt', descending: true).get();
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      return [];
    }
  }
}
