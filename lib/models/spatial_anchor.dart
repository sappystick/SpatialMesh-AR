import 'package:json_annotation/json_annotation.dart';
import 'package:vector_math/vector_math_64.dart';

part 'spatial_anchor.g.dart';

@JsonSerializable()
class SpatialAnchor {
  final String id;
  final String userId;
  final Vector3 position;
  final Vector3 rotation;
  final Map<String, dynamic> metadata;
  final double qualityScore;
  final DateTime createdAt;
  final String? cloudAnchorId;
  final bool isPersistent;
  final List<String> sharedWith;
  final double earnings;
  
  SpatialAnchor({
    required this.id,
    required this.userId,
    required this.position,
    required this.rotation,
    required this.metadata,
    required this.qualityScore,
    required this.createdAt,
    this.cloudAnchorId,
    this.isPersistent = true,
    this.sharedWith = const [],
    this.earnings = 0.0,
  });
  
  factory SpatialAnchor.fromJson(Map<String, dynamic> json) => _$SpatialAnchorFromJson(json);
  
  Map<String, dynamic> toJson() => _$SpatialAnchorToJson(this);
  
  SpatialAnchor copyWith({
    String? id,
    String? userId,
    Vector3? position,
    Vector3? rotation,
    Map<String, dynamic>? metadata,
    double? qualityScore,
    DateTime? createdAt,
    String? cloudAnchorId,
    bool? isPersistent,
    List<String>? sharedWith,
    double? earnings,
  }) {
    return SpatialAnchor(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      metadata: metadata ?? this.metadata,
      qualityScore: qualityScore ?? this.qualityScore,
      createdAt: createdAt ?? this.createdAt,
      cloudAnchorId: cloudAnchorId ?? this.cloudAnchorId,
      isPersistent: isPersistent ?? this.isPersistent,
      sharedWith: sharedWith ?? this.sharedWith,
      earnings: earnings ?? this.earnings,
    );
  }
  
  @override
  String toString() {
    return 'SpatialAnchor{id: $id, userId: $userId, qualityScore: $qualityScore, earnings: $earnings}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpatialAnchor && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
}