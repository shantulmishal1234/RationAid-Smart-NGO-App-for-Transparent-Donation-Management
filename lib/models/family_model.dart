import 'package:cloud_firestore/cloud_firestore.dart';

/// Category of assistance a family requires.
/// Drives donation-type gating in the Donor UI.
enum FamilyCategory { food, medicine, combined }

/// Family model for donor view (read-only, masked data)
/// Only shows accepted families with privacy-focused information
class Family {
  final String id;
  final String? name; // Admin only, masked from donors in UI
  final String city; // New city field
  final String area; // masked location (neighborhood)
  final String? address;
  final String? phone;
  final int familySize;
  final int numberOfAdults;
  final int numberOfChildren;
  final Map<String, num> needs; // map of item name to quantity needed
  final List<String> assistanceNeeds; // Types of assistance needed
  final String status; // should always be 'accepted' for donor view
  final String? remarks; // Additional notes
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Extended Demographics & Housing (Phase 3 Expansion)
  final String? husbandName;
  final bool isWidow;
  final String? houseStatus; // 'rented' | 'owned'
  final double rentAmount;
  final String? houseCondition;
  final String? houseSize; // e.g., '2 Marla', '5 Marla'
  final String? biography;
  final bool hasHusbandWife;

  // Children Details
  final List<Map<String, dynamic>> childrenDetails;

  // Assets
  final bool hasTransport;
  final String? transportDetails; // e.g., 'Motorcycle v1'
  final List<String> electronicsOwned; // e.g., ['TV', 'Fridge']

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
  final double customMedicineBudget;

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
  final double surplusAmount; // New field for over-funded amount
  final double spentAmount; // Track amount spent on fulfillment
  final Map<String, num>
  pendingNeeds; // current status of in-kind needsiate In-Kind updates

  // Fulfillment (Phase 5)
  final String
  fulfillmentStatus; // pending, ready_for_purchase, purchase_approved, delivered
  final String? purchaseApprovedBy;
  final DateTime? purchaseApprovedAt;
  final String? deliveryProof; // URL
  final String? deliveredBy;
  final DateTime? deliveredAt;

  // Smart Allocation (Phase 6 — Hybrid Architecture)
  final double
  priorityScore; // Computed by AllocationService (higher = more urgent)
  final bool isEmergency; // Admin-flagged emergency family
  final String? emergencyNote; // Admin note explaining the emergency
  final String fundingStatus; // 'pending' | 'partially_funded' | 'fully_funded'

  // In-Kind Tracking (Phase IK — Dual-Track Fulfillment)
  /// Sum of locked monetary values of all warehouse-received in-kind batches.
  /// Locked at admin-approval time from the pack price snapshot.
  final double inKindValue;

  /// raisedAmount + inKindValue — drives all progress bars across the app.
  final double combinedProgress;

  Family({
    required this.id,
    this.name,
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
    // Extended Demographics
    this.husbandName,
    this.isWidow = false,
    this.houseStatus,
    this.rentAmount = 0.0,
    this.houseCondition,
    this.houseSize,
    this.biography,
    this.hasHusbandWife = false,
    this.childrenDetails = const [],
    this.hasTransport = false,
    this.transportDetails,
    this.electronicsOwned = const [],
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
    this.customMedicineBudget = 0.0,
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
    this.surplusAmount = 0,
    this.spentAmount = 0,
    this.pendingNeeds = const {},
    // Fulfillment
    this.fulfillmentStatus = 'pending',
    this.purchaseApprovedBy,
    this.purchaseApprovedAt,
    this.deliveryProof,
    this.deliveredBy,
    this.deliveredAt,
    // Smart Allocation
    this.priorityScore = 0.0,
    this.isEmergency = false,
    this.emergencyNote,
    this.fundingStatus = 'pending',
    // In-Kind Tracking
    this.inKindValue = 0.0,
    this.combinedProgress = 0.0,
  });

  /// Factory constructor from Firestore document
  factory Family.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Get family size
    final familySize = data['familySize'] ?? 0;

    // Read adults/children — add_family_screen saves as 'adults'/'children'.
    // Fall back to 'numberOfAdults'/'numberOfChildren' for any legacy docs.
    final int numberOfAdults =
        (data['adults'] ?? data['numberOfAdults'] ?? 0) as int;
    final int numberOfChildren =
        (data['children'] ?? data['numberOfChildren'] ?? 0) as int;

    return Family(
      id: doc.id,
      name: data['name'],
      city: data['city'] ?? '',
      area: data['area'] ?? 'Unknown Area',
      address: data['address'],
      phone: data['phone'],
      familySize: familySize,
      numberOfAdults: numberOfAdults,
      numberOfChildren: numberOfChildren,
      needs: data['needs'] != null
          ? Map<String, num>.from(data['needs'] as Map)
          : {},
      assistanceNeeds: data['assistanceNeeds'] != null
          ? List<String>.from(data['assistanceNeeds'] as List)
          : [],
      status: data['status'] ?? '',
      remarks: data['remarks'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      // Extended Demographics & Housing
      husbandName: data['husbandName'],
      isWidow: data['isWidow'] ?? false,
      houseStatus: data['houseStatus'],
      rentAmount: (data['rentAmount'] ?? 0).toDouble(),
      houseCondition: data['houseCondition'],
      houseSize: data['houseSize'],
      biography: data['biography'],
      hasHusbandWife: data['hasHusbandWife'] ?? false,
      childrenDetails: data['childrenDetails'] != null
          ? List<Map<String, dynamic>>.from(
              (data['childrenDetails'] as List).map(
                (i) => Map<String, dynamic>.from(i as Map),
              ),
            )
          : [],
      hasTransport: data['hasTransport'] ?? false,
      transportDetails: data['transportDetails'],
      electronicsOwned: data['electronicsOwned'] != null
          ? List<String>.from(data['electronicsOwned'] as List)
          : [],
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
      customMedicineBudget: (data['customMedicineBudget'] ?? 0.0).toDouble(),
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
      surplusAmount: (data['surplusAmount'] ?? 0).toDouble(),
      spentAmount: (data['spentAmount'] ?? 0).toDouble(),
      pendingNeeds: data['pendingNeeds'] != null
          ? Map<String, num>.from(data['pendingNeeds'] as Map)
          : {},
      // Fulfillment
      fulfillmentStatus: data['fulfillmentStatus'] ?? 'pending',
      purchaseApprovedBy: data['purchaseApprovedBy'],
      purchaseApprovedAt: (data['purchaseApprovedAt'] as Timestamp?)?.toDate(),
      deliveryProof: data['deliveryProof'],
      deliveredBy: data['deliveredBy'],
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      // Smart Allocation (safe defaults for existing docs)
      priorityScore: (data['priorityScore'] ?? 0.0).toDouble(),
      isEmergency: data['isEmergency'] ?? false,
      emergencyNote: data['emergencyNote'],
      fundingStatus: data['fundingStatus'] ?? 'pending',
      // In-Kind Tracking (safe defaults — 0 for legacy docs without these fields)
      inKindValue: (data['inKindValue'] ?? 0.0).toDouble(),
      combinedProgress:
          (data['combinedProgress'] as num?)?.toDouble() ??
          (data['raisedAmount'] as num? ?? 0).toDouble(),
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
      'customMedicineBudget': customMedicineBudget,
      'husbandName': husbandName,
      'isWidow': isWidow,
      'houseStatus': houseStatus,
      'rentAmount': rentAmount,
      'houseCondition': houseCondition,
      'houseSize': houseSize,
      'biography': biography,
      'hasHusbandWife': hasHusbandWife,
      'childrenDetails': childrenDetails,
      'hasTransport': hasTransport,
      'transportDetails': transportDetails,
      'electronicsOwned': electronicsOwned,
    };
  }

  /// Helper: Get total items needed
  num get totalItemsNeeded {
    return needs.values.fold<num>(0, (sum, qty) => sum + qty);
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

  /// Helper: Get total funded amount (raised + pending).
  /// Shown in donor UI as an optimistic total; verified portion is [raisedAmount].
  double get totalFunded => raisedAmount + pendingAmount;

  /// Fix #7 — computed remainingAmount (never stale).
  /// Always derived so that stale Firestore field can no longer cause UI drift.
  double get computedRemainingAmount =>
      (targetAmount - raisedAmount).clamp(0.0, double.infinity);

  /// Always derived so that stale Firestore field can no longer cause UI drift.
  double get computedSurplusAmount =>
      (raisedAmount - targetAmount).clamp(0.0, double.infinity);

  /// In-Kind overhaul: combined progress percent (0.0 → 1.0).
  /// Uses combinedProgress (cash + in-kind value) against total target.
  double get combinedFundingPercent => targetAmount > 0
      ? (combinedProgress / targetAmount).clamp(0.0, 1.0)
      : 0.0;

  /// Remaining cash still needed after subtracting in-kind contributions.
  /// Used to show donors the correct cash gap.
  double get remainingCashNeeded =>
      (targetAmount - combinedProgress).clamp(0.0, double.infinity);

  /// Fix #11 — derives the donation category from assistanceNeeds.
  /// Used by the Donor UI to gate the In-Kind donation tab.
  FamilyCategory get category {
    final hasFood = assistanceNeeds.contains('Food');
    final hasMed = assistanceNeeds.contains('Medicine');
    if (hasFood && hasMed) return FamilyCategory.combined;
    if (hasMed) return FamilyCategory.medicine;
    return FamilyCategory.food;
  }

  /// Whether this family can receive in-kind (physical item) donations.
  bool get acceptsInKind => category != FamilyCategory.medicine;

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
    Map<String, num>? needs,
    List<String>? assistanceNeeds,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? surplusAmount,
    double? customMedicineBudget,
    String? husbandName,
    bool? isWidow,
    String? houseStatus,
    double? rentAmount,
    String? houseCondition,
    String? houseSize,
    String? biography,
    bool? hasHusbandWife,
    List<Map<String, dynamic>>? childrenDetails,
    bool? hasTransport,
    String? transportDetails,
    List<String>? electronicsOwned,
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
      surplusAmount: surplusAmount ?? this.surplusAmount,
      husbandName: husbandName ?? this.husbandName,
      isWidow: isWidow ?? this.isWidow,
      houseStatus: houseStatus ?? this.houseStatus,
      rentAmount: rentAmount ?? this.rentAmount,
      houseCondition: houseCondition ?? this.houseCondition,
      houseSize: houseSize ?? this.houseSize,
      biography: biography ?? this.biography,
      hasHusbandWife: hasHusbandWife ?? this.hasHusbandWife,
      childrenDetails: childrenDetails ?? this.childrenDetails,
      hasTransport: hasTransport ?? this.hasTransport,
      transportDetails: transportDetails ?? this.transportDetails,
      electronicsOwned: electronicsOwned ?? this.electronicsOwned,
    );
  }
}
