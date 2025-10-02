import 'dart:convert';

class UserPaymentPreferences {
  final String userId;
  final String? blockchainAddress;
  final String? lightningAddress;
  final String? preferredNetwork;
  final Map<String, dynamic>? metadata;
  
  UserPaymentPreferences({
    required this.userId,
    this.blockchainAddress,
    this.lightningAddress,
    this.preferredNetwork,
    this.metadata,
  });
  
  factory UserPaymentPreferences.fromJson(Map<String, dynamic> json) {
    return UserPaymentPreferences(
      userId: json['userId'] as String,
      blockchainAddress: json['blockchainAddress'] as String?,
      lightningAddress: json['lightningAddress'] as String?,
      preferredNetwork: json['preferredNetwork'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'blockchainAddress': blockchainAddress,
      'lightningAddress': lightningAddress,
      'preferredNetwork': preferredNetwork,
      'metadata': metadata,
    };
  }
  
  UserPaymentPreferences copyWith({
    String? blockchainAddress,
    String? lightningAddress,
    String? preferredNetwork,
    Map<String, dynamic>? metadata,
  }) {
    return UserPaymentPreferences(
      userId: userId,
      blockchainAddress: blockchainAddress ?? this.blockchainAddress,
      lightningAddress: lightningAddress ?? this.lightningAddress,
      preferredNetwork: preferredNetwork ?? this.preferredNetwork,
      metadata: metadata ?? this.metadata,
    );
  }
  
  @override
  String toString() {
    return 'UserPaymentPreferences{userId: $userId, blockchainAddress: $blockchainAddress, lightningAddress: $lightningAddress, preferredNetwork: $preferredNetwork}';
  }
}