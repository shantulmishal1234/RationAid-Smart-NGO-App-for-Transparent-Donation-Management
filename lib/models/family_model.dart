import 'package:cloud_firestore/cloud_firestore.dart';

/// Family model for donor view (read-only, masked data)
/// Only shows accepted families with privacy-focused information
class Family {
  final String id;
  final String city; // New city field
  final String area; // masked location (neighborhood)
  final int familySize;
  final int numberOfAdults;
  final int numberOfChildren;
  final Map<String, int> needs; // map of item name to quantity needed
  final List<String> assistanceNeeds; // Types of assistance needed
  final String status; // should always be 'accepted' for donor view
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Family({
    required this.id,
    required this.city,
    required this.area,
    required this.familySize,
    required this.numberOfAdults,
    required this.numberOfChildren,
    required this.needs,
    required this.assistanceNeeds,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor from Firestore document
  factory Family.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Get family size
    final familySize = data['familySize'] ?? 0;

    // Try to get adult/children counts, or derive from family size if not available
    int numberOfAdults = data['numberOfAdults'] ?? 0;
    int numberOfChildren = data['numberOfChildren'] ?? 0;

    // If both are 0 but family size exists, assume adults based on family size
    if (numberOfAdults == 0 && numberOfChildren == 0 && familySize > 0) {
      // Default assumption: at least 2 adults, rest are children
      numberOfAdults = familySize >= 2 ? 2 : familySize;
      numberOfChildren = familySize > 2 ? (familySize - 2) : 0;
    }

    return Family(
      id: doc.id,
      city: data['city'] ?? '', // Default to empty if missing (legacy data)
      area: data['area'] ?? 'Unknown Area',
      familySize: familySize,
      numberOfAdults: numberOfAdults,
      numberOfChildren: numberOfChildren,
      needs: data['needs'] != null
          ? Map<String, int>.from(data['needs'] as Map)
          : {},
      assistanceNeeds: data['assistanceNeeds'] != null
          ? List<String>.from(data['assistanceNeeds'] as List)
          : [],
      status: data['status'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert to map (read-only, so rarely used)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'city': city,
      'area': area,
      'familySize': familySize,
      'numberOfAdults': numberOfAdults,
      'numberOfChildren': numberOfChildren,
      'needs': needs,
      'assistanceNeeds': assistanceNeeds,
      'status': status,
    };
  }

  /// Helper: Get total items needed
  int get totalItemsNeeded {
    return needs.values.fold(0, (sum, qty) => sum + qty);
  }

  /// Helper: Get count of different item types
  int get itemTypesCount {
    return needs.length;
  }

  /// Helper: Check if family is accepted
  bool get isAccepted {
    return status.toLowerCase() == 'accepted';
  }

  /// Helper: Get formatted needs string for display
  String get needsSummary {
    if (needs.isEmpty) return 'No items specified';
    if (needs.length == 1) {
      final item = needs.entries.first;
      return '${item.value} ${item.key}';
    }
    return '${needs.length} types of items needed';
  }

  /// Helper: Get list of needed item names
  List<String> get neededItemNames {
    return needs.keys.toList();
  }

  /// Copy with method (rarely needed for read-only model)
  Family copyWith({
    String? id,
    String? city,
    String? area,
    int? familySize,
    int? numberOfAdults,
    int? numberOfChildren,
    Map<String, int>? needs,
    List<String>? assistanceNeeds,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Family(
      id: id ?? this.id,
      city: city ?? this.city,
      area: area ?? this.area,
      familySize: familySize ?? this.familySize,
      numberOfAdults: numberOfAdults ?? this.numberOfAdults,
      numberOfChildren: numberOfChildren ?? this.numberOfChildren,
      needs: needs ?? this.needs,
      assistanceNeeds: assistanceNeeds ?? this.assistanceNeeds,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
