import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for assistance pack items
///
/// Stores the quantity as BOTH:
///   • [quantityNum] — the precise numeric value (double), e.g. 3.5
///   • [unit]        — the display unit string, e.g. "kg"
///   • [quantity]    — a computed display string "3.5 kg" for legacy views
///
/// This eliminates the previous free-text quantity bug where '3.5 kg'
/// could be mistyped as '35 kg', causing 10× errors in family.needs.
class PackItem {
  final String name;
  final double quantityNum; // e.g. 3.5
  final String unit; // e.g. "kg", "L", "pcs", "bars", "packets"
  final double estimatedCost;

  PackItem({
    required this.name,
    required this.quantityNum,
    required this.unit,
    required this.estimatedCost,
  });

  /// Legacy display string, e.g. "3.5 kg"
  String get quantity => '${_fmtNum(quantityNum)} $unit'.trim();

  /// Format number: strip trailing zeros (3.0 → "3", 3.5 → "3.5")
  static String _fmtNum(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantityNum': quantityNum,
      'unit': unit,
      // Keep 'quantity' string for backwards-compatible reads by older app versions
      'quantity': quantity,
      'estimatedCost': estimatedCost,
    };
  }

  factory PackItem.fromMap(Map<String, dynamic> map) {
    // Prefer new explicit fields; fall back to parsing old string if missing
    final double? explicitNum = (map['quantityNum'] as num?)?.toDouble();
    final String? explicitUnit = map['unit'] as String?;

    double num0;
    String unit0;

    if (explicitNum != null) {
      num0 = explicitNum;
      unit0 = explicitUnit ?? 'kg';
    } else {
      // Legacy: parse from string e.g. "3.5 kg"
      final raw = (map['quantity'] ?? '') as String;
      final match = RegExp(r'([\d.]+)\s*(.*)').firstMatch(raw.trim());
      num0 = double.tryParse(match?.group(1) ?? '1') ?? 1.0;
      unit0 = match?.group(2)?.trim() ?? 'kg';
    }

    return PackItem(
      name: map['name'] ?? '',
      quantityNum: num0,
      unit: unit0,
      estimatedCost: (map['estimatedCost'] ?? 0).toDouble(),
    );
  }
}

/// Model for assistance packs
class AssistancePack {
  final String id;
  final String name;
  final String packType;
  final String? description;
  final int minMembers;
  final int maxMembers;
  final double budgetAmount;
  final List<PackItem> items;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  AssistancePack({
    required this.id,
    required this.name,
    required this.packType,
    this.description,
    required this.minMembers,
    required this.maxMembers,
    required this.budgetAmount,
    required this.items,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'packType': packType,
      'description': description,
      'minMembers': minMembers,
      'maxMembers': maxMembers,
      'budgetAmount': budgetAmount,
      'items': items.map((item) => item.toMap()).toList(),
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory AssistancePack.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AssistancePack(
      id: doc.id,
      name: data['name'] ?? '',
      packType: data['packType'] ?? '',
      description: data['description'],
      minMembers: data['minMembers'] ?? 1,
      maxMembers: data['maxMembers'] ?? 1,
      budgetAmount: (data['budgetAmount'] ?? 0).toDouble(),
      items:
          (data['items'] as List<dynamic>?)
              ?.map((item) => PackItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  AssistancePack copyWith({
    String? id,
    String? name,
    String? packType,
    String? description,
    int? minMembers,
    int? maxMembers,
    double? budgetAmount,
    List<PackItem>? items,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AssistancePack(
      id: id ?? this.id,
      name: name ?? this.name,
      packType: packType ?? this.packType,
      description: description ?? this.description,
      minMembers: minMembers ?? this.minMembers,
      maxMembers: maxMembers ?? this.maxMembers,
      budgetAmount: budgetAmount ?? this.budgetAmount,
      items: items ?? this.items,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
