import 'package:cloud_firestore/cloud_firestore.dart';

/// Family model for donor view (read-only, masked data)
/// Only shows accepted families with privacy-focused information
class Family {
  final String id;
  final String city; // New city field
  final String area; // masked location (neighborhood)
  final String? address;
  final String? phone;
  final int familySize;
  final int numberOfAdults;
  final int numberOfChildren;
  final Map<String, int> needs; // map of item name to quantity needed
  final List<String> assistanceNeeds; // Types of assistance needed
  final String status; // should always be 'accepted' for donor view
  final String? remarks; // Additional notes
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Location fields (Phase 1)
  final GeoPoint? unverifiedLocation;
  final String? locationCapturedBy;
  final DateTime? locationCapturedAt;
  final GeoPoint? verifiedLocation;
  final DateTime? locationVerifiedAt;
  final String? locationVerifiedBy;
  final String? locationAddress;

  // Review fields (Phase 2)
  final List<String> reviewerIds;
  final int approveCount;
  final int rejectCount;
  final int quorumThreshold;
  final bool quorumReached;

  // Pack assignment (Phase 3)
  final String? assignedPackId;
  final String? assignedPackName;

  // Final Approver decision (Phase 3)
  final String? finalApproverUid;
  final String? finalApproverName;
  final String? finalDecision; // 'accept' or 'reject'
  final String? finalDecisionComment;
  final DateTime? finalDecisionAt;

  // Funding pool (Phase 4)
  final double targetAmount;
  final double raisedAmount;
  final double pendingAmount;
  final double remainingAmount;
  final Map<String, int>
  pendingNeeds; // New field for immediate In-Kind updates

  // Fulfillment (Phase 5)
  final String
  fulfillmentStatus; // pending, ready_for_purchase, purchase_approved, delivered
  final String? purchaseApprovedBy;
  final DateTime? purchaseApprovedAt;
  final String? deliveryProof; // URL
  final String? deliveredBy;
  final DateTime? deliveredAt;

  Family({
    required this.id,
    required this.city,
    required this.area,
    this.address,
    this.phone,
    required this.familySize,
    required this.numberOfAdults,
    required this.numberOfChildren,
    required this.needs,
    required this.assistanceNeeds,
    required this.status,
    this.remarks,
    this.createdAt,
    this.updatedAt,
    // Location fields
    this.unverifiedLocation,
    this.locationCapturedBy,
    this.locationCapturedAt,
    this.verifiedLocation,
    this.locationVerifiedAt,
    this.locationVerifiedBy,
    this.locationAddress,
    // Review fields
    this.reviewerIds = const [],
    this.approveCount = 0,
    this.rejectCount = 0,
    this.quorumThreshold = 3,
    this.quorumReached = false,
    // Pack assignment
    this.assignedPackId,
    this.assignedPackName,
    // Final Approver decision
    this.finalApproverUid,
    this.finalApproverName,
    this.finalDecision,
    this.finalDecisionComment,
    this.finalDecisionAt,
    // Funding pool
    this.targetAmount = 0,
    this.raisedAmount = 0,
    this.pendingAmount = 0,
    this.remainingAmount = 0,
    this.pendingNeeds = const {},
    // Fulfillment
    this.fulfillmentStatus = 'pending',
    this.purchaseApprovedBy,
    this.purchaseApprovedAt,
    this.deliveryProof,
    this.deliveredBy,
    this.deliveredAt,
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
      city: data['city'] ?? '',
      area: data['area'] ?? 'Unknown Area',
      address: data['address'],
      phone: data['phone'],
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
      remarks: data['remarks'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      // Location fields
      unverifiedLocation: data['unverifiedLocation'],
      locationCapturedBy: data['locationCapturedBy'],
      locationCapturedAt: data['locationCapturedAt'] != null
          ? (data['locationCapturedAt'] as Timestamp).toDate()
          : null,
      verifiedLocation: data['verifiedLocation'],
      locationVerifiedAt: data['locationVerifiedAt'] != null
          ? (data['locationVerifiedAt'] as Timestamp).toDate()
          : null,
      locationVerifiedBy: data['locationVerifiedBy'],
      locationAddress: data['locationAddress'],
      // Review fields
      reviewerIds: data['reviewerIds'] != null
          ? List<String>.from(data['reviewerIds'] as List)
          : [],
      approveCount: data['approveCount'] ?? 0,
      rejectCount: data['rejectCount'] ?? 0,
      quorumThreshold: data['quorumThreshold'] ?? 3,
      quorumReached: data['quorumReached'] ?? false,
      // Pack assignment
      assignedPackId: data['assignedPackId'],
      assignedPackName: data['assignedPackName'],
      // Final Approver decision
      finalApproverUid: data['finalApproverUid'],
      finalApproverName: data['finalApproverName'],
      finalDecision: data['finalDecision'],
      finalDecisionComment: data['finalDecisionComment'],
      finalDecisionAt: data['finalDecisionAt'] != null
          ? (data['finalDecisionAt'] as Timestamp).toDate()
          : null,
      // Funding pool
      targetAmount: (data['targetAmount'] ?? 0).toDouble(),
      raisedAmount: (data['raisedAmount'] ?? 0).toDouble(),
      pendingAmount: (data['pendingAmount'] ?? 0).toDouble(),
      remainingAmount: (data['remainingAmount'] ?? 0).toDouble(),
      pendingNeeds: data['pendingNeeds'] != null
          ? Map<String, int>.from(data['pendingNeeds'] as Map)
          : {},
      // Fulfillment
      fulfillmentStatus: data['fulfillmentStatus'] ?? 'pending',
      purchaseApprovedBy: data['purchaseApprovedBy'],
      purchaseApprovedAt: (data['purchaseApprovedAt'] as Timestamp?)?.toDate(),
      deliveryProof: data['deliveryProof'],
      deliveredBy: data['deliveredBy'],
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
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

  /// Helper: Get total funded amount (raised + pending)
  /// This is used for immediate UI updates so donors see their impact instantly
  double get totalFunded => raisedAmount + pendingAmount;

  /// Copy with method (rarely needed for read-only model)
  Family copyWith({
    String? id,
    String? city,
    String? area,
    String? address,
    String? phone,
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
      address: address ?? this.address,
      phone: phone ?? this.phone,
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
