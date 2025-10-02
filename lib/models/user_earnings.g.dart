// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_earnings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserEarnings _$UserEarningsFromJson(Map<String, dynamic> json) => UserEarnings(
      userId: json['userId'] as String,
      totalEarnings:
          const DecimalConverter().fromJson(json['totalEarnings'] as String),
      availableBalance:
          const DecimalConverter().fromJson(json['availableBalance'] as String),
      pendingBalance:
          const DecimalConverter().fromJson(json['pendingBalance'] as String),
      lifetimeWithdrawals:
          const DecimalConverter().fromJson(json['lifetimeWithdrawals'] as String),
      earningsByType: (json['earningsByType'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, const DecimalConverter().fromJson(e as String)),
          ) ??
          const {},
      recentTransactions: (json['recentTransactions'] as List<dynamic>?)
              ?.map((e) =>
                  EarningTransaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.parse(json['lastUpdated'] as String),
      contributionCount: json['contributionCount'] as int? ?? 0,
      averageQualityScore:
          (json['averageQualityScore'] as num?)?.toDouble() ?? 0.0,
      contributionsByType:
          (json['contributionsByType'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, e as int),
              ) ??
              const {},
    );

Map<String, dynamic> _$UserEarningsToJson(UserEarnings instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'totalEarnings': const DecimalConverter().toJson(instance.totalEarnings),
      'availableBalance':
          const DecimalConverter().toJson(instance.availableBalance),
      'pendingBalance': const DecimalConverter().toJson(instance.pendingBalance),
      'lifetimeWithdrawals':
          const DecimalConverter().toJson(instance.lifetimeWithdrawals),
      'earningsByType': instance.earningsByType
          .map((k, e) => MapEntry(k, const DecimalConverter().toJson(e))),
      'recentTransactions':
          instance.recentTransactions.map((e) => e.toJson()).toList(),
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'contributionCount': instance.contributionCount,
      'averageQualityScore': instance.averageQualityScore,
      'contributionsByType': instance.contributionsByType,
    };

EarningTransaction _$EarningTransactionFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    requiredKeys: const [
      'id',
      'userId',
      'amount',
      'type',
      'contributionId',
      'timestamp',
      'status',
      'paymentMethod'
    ],
  );
  return EarningTransaction(
    id: json['id'] as String,
    userId: json['userId'] as String,
    amount: const DecimalConverter().fromJson(json['amount'] as String),
    type: json['type'] as String,
    contributionId: json['contributionId'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    status: json['status'] as String,
    transactionHash: json['transactionHash'] as String?,
    paymentMethod:
        const PaymentTypeConverter().fromJson(json['paymentMethod'] as String),
    metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
  );
}

Map<String, dynamic> _$EarningTransactionToJson(EarningTransaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'amount': const DecimalConverter().toJson(instance.amount),
      'type': instance.type,
      'contributionId': instance.contributionId,
      'timestamp': instance.timestamp.toIso8601String(),
      'status': instance.status,
      'transactionHash': instance.transactionHash,
      'paymentMethod': const PaymentTypeConverter().toJson(instance.paymentMethod),
      'metadata': instance.metadata,
    };