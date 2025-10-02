import 'package:json_annotation/json_annotation.dart';
import 'package:decimal/decimal.dart';

part 'user_earnings.g.dart';

@JsonSerializable()
class UserEarnings {
  @JsonKey(required: true)
  final String userId;
  
  @DecimalConverter()
  @JsonKey(required: true)
  final Decimal totalEarnings;
  
  @DecimalConverter()
  @JsonKey(required: true)
  final Decimal availableBalance;
  
  @DecimalConverter()
  @JsonKey(required: true)
  final Decimal pendingBalance;
  
  @DecimalConverter()
  @JsonKey(required: true)
  final Decimal lifetimeWithdrawals;
  
  @JsonKey(defaultValue: const {})
  final Map<String, Decimal> earningsByType;
  
  @JsonKey(defaultValue: const [])
  final List<EarningTransaction> recentTransactions;
  
  final DateTime lastUpdated;
  
  @JsonKey(defaultValue: 0)
  final int contributionCount;
  
  @JsonKey(defaultValue: 0.0)
  final double averageQualityScore;
  
  @JsonKey(defaultValue: const {})
  final Map<String, int> contributionsByType;
  
  UserEarnings({
    required this.userId,
    required this.totalEarnings,
    required this.availableBalance,
    required this.pendingBalance,
    required this.lifetimeWithdrawals,
    this.earningsByType = const {},
    this.recentTransactions = const [],
    DateTime? lastUpdated,
    this.contributionCount = 0,
    this.averageQualityScore = 0.0,
    this.contributionsByType = const {},
  }) : this.lastUpdated = lastUpdated ?? DateTime.now();
  
  factory UserEarnings.fromJson(Map<String, dynamic> json) => _$UserEarningsFromJson(json);
  
  Map<String, dynamic> toJson() => _$UserEarningsToJson(this);
  
  // Calculated properties
  Decimal get dailyEarnings {
    final today = DateTime.now();
    final todayTransactions = recentTransactions.where((tx) => 
        tx.timestamp.day == today.day &&
        tx.timestamp.month == today.month &&
        tx.timestamp.year == today.year
    );
    
    return todayTransactions.fold(
      Decimal.zero,
      (sum, tx) => sum + tx.amount,
    );
  }
  
  Decimal get weeklyEarnings {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final weekTransactions = recentTransactions.where((tx) => tx.timestamp.isAfter(weekAgo));
    
    return weekTransactions.fold(
      Decimal.zero,
      (sum, tx) => sum + tx.amount,
    );
  }
  
  Decimal get monthlyEarnings {
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final monthTransactions = recentTransactions.where((tx) => tx.timestamp.isAfter(monthAgo));
    
    return monthTransactions.fold(
      Decimal.zero,
      (sum, tx) => sum + tx.amount,
    );
  }
  
  Decimal get totalPendingWithdrawals {
    return recentTransactions
        .where((tx) => tx.status == 'pending' && tx.type == 'withdrawal')
        .fold(
          Decimal.zero,
          (sum, tx) => sum + tx.amount,
        );
  }
  
  String get topEarningType {
    if (earningsByType.isEmpty) return 'none';
    
    return earningsByType.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
  
  UserEarnings copyWith({
    String? userId,
    Decimal? totalEarnings,
    Decimal? availableBalance,
    Decimal? pendingBalance,
    Decimal? lifetimeWithdrawals,
    Map<String, Decimal>? earningsByType,
    List<EarningTransaction>? recentTransactions,
    DateTime? lastUpdated,
    int? contributionCount,
    double? averageQualityScore,
    Map<String, int>? contributionsByType,
  }) {
    return UserEarnings(
      userId: userId ?? this.userId,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      availableBalance: availableBalance ?? this.availableBalance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      lifetimeWithdrawals: lifetimeWithdrawals ?? this.lifetimeWithdrawals,
      earningsByType: earningsByType ?? this.earningsByType,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      contributionCount: contributionCount ?? this.contributionCount,
      averageQualityScore: averageQualityScore ?? this.averageQualityScore,
      contributionsByType: contributionsByType ?? this.contributionsByType,
    );
  }
}

@JsonSerializable()
@JsonSerializable()
class EarningTransaction {
  @JsonKey(required: true)
  final String id;
  
  @JsonKey(required: true)
  final String userId;
  
  @DecimalConverter()
  @JsonKey(required: true)
  final Decimal amount;
  
  @JsonKey(required: true)
  final String type;
  
  @JsonKey(required: true)
  final String contributionId;
  
  @JsonKey(required: true)
  final DateTime timestamp;
  
  @JsonKey(required: true)
  final String status;
  
  final String? transactionHash;
  
  @PaymentTypeConverter()
  @JsonKey(required: true)
  final PaymentType paymentMethod;
  
  @JsonKey(defaultValue: const {})
  final Map<String, dynamic> metadata;
  
  EarningTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.contributionId,
    required this.timestamp,
    required this.status,
    this.transactionHash,
    required this.paymentMethod,
    this.metadata = const {},
  });
  
  factory EarningTransaction.fromJson(Map<String, dynamic> json) => _$EarningTransactionFromJson(json);
  
  Map<String, dynamic> toJson() => _$EarningTransactionToJson(this);
}