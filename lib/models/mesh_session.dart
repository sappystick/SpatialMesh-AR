import 'package:json_annotation/json_annotation.dart';

part 'mesh_session.g.dart';

@JsonSerializable()
class MeshSession {
  final String id;
  final List<String> participants;
  final DateTime createdAt;
  final String status;
  final Map<String, dynamic> spatialData;
  final Map<String, DateTime> participantJoinTimes;
  final Map<String, int> dataTransferredByParticipant;
  final double totalEarnings;
  final String sessionType;
  final Map<String, dynamic> configuration;
  
  MeshSession({
    required this.id,
    required this.participants,
    required this.createdAt,
    required this.status,
    required this.spatialData,
    Map<String, DateTime>? participantJoinTimes,
    Map<String, int>? dataTransferredByParticipant,
    this.totalEarnings = 0.0,
    this.sessionType = 'collaborative',
    this.configuration = const {},
  }) : participantJoinTimes = participantJoinTimes ?? {},
       dataTransferredByParticipant = dataTransferredByParticipant ?? {};
  
  factory MeshSession.fromJson(Map<String, dynamic> json) => _$MeshSessionFromJson(json);
  
  Map<String, dynamic> toJson() => _$MeshSessionToJson(this);
  
  // Calculated properties
  Duration get sessionDuration => DateTime.now().difference(createdAt);
  
  int get totalDataTransferred => dataTransferredByParticipant.values.fold(0, (sum, data) => sum + data);
  
  double get averageParticipationTime {
    if (participantJoinTimes.isEmpty) return 0.0;
    
    final now = DateTime.now();
    final durations = participantJoinTimes.values.map((joinTime) => now.difference(joinTime).inMinutes);
    
    return durations.fold(0, (sum, duration) => sum + duration) / durations.length;
  }
  
  List<String> get activeParticipants {
    if (status != 'active') return [];
    return participants;
  }
  
  MeshSession copyWith({
    String? id,
    List<String>? participants,
    DateTime? createdAt,
    String? status,
    Map<String, dynamic>? spatialData,
    Map<String, DateTime>? participantJoinTimes,
    Map<String, int>? dataTransferredByParticipant,
    double? totalEarnings,
    String? sessionType,
    Map<String, dynamic>? configuration,
  }) {
    return MeshSession(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      spatialData: spatialData ?? this.spatialData,
      participantJoinTimes: participantJoinTimes ?? this.participantJoinTimes,
      dataTransferredByParticipant: dataTransferredByParticipant ?? this.dataTransferredByParticipant,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      sessionType: sessionType ?? this.sessionType,
      configuration: configuration ?? this.configuration,
    );
  }
}