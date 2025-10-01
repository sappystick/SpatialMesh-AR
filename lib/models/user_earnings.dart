import 'package:json_annotation/json_annotation.dart';

part 'user_earnings.g.dart';

@JsonSerializable()
class UserEarnings {
  final String userId;
  final double totalEarnings;
  final double totalPaid;
  final double pendingEarnings;
  final Map<String, double> earningsByType;
  final List<EarningTransaction> recentTransactions;
  final DateTime lastUpdated;
  final int contributionCount;
  final double averageQualityScore;
  final Map<String, int> contributionsByType;
  
  UserEarnings({
    required this.userId,
    required this.totalEarnings,
    required this.totalPaid,
    required this.pendingEarnings,
    required this.earningsByType,
    required this.recentTransactions,
    required this.lastUpdated,
    required this.contributionCount,
    required this.averageQualityScore,
    required this.contributionsByType,
  });
  
  factory UserEarnings.fromJson(Map<String, dynamic> json) => _$UserEarningsFromJson(json);
  
  Map<String, dynamic> toJson() => _$UserEarningsToJson(this);
  
  // Calculated properties
  double get dailyEarnings {
    final today = DateTime.now();
    final todayTransactions = recentTransactions.where((tx) => 
        tx.timestamp.day == today.day &&
        tx.timestamp.month == today.month &&
        tx.timestamp.year == today.year
    );
    
    return todayTransactions.fold(0.0, (sum, tx) => sum + tx.amount);
  }
  
  double get weeklyEarnings {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final weekTransactions = recentTransactions.where((tx) => tx.timestamp.isAfter(weekAgo));
    
    return weekTransactions.fold(0.0, (sum, tx) => sum + tx.amount);
  }
  
  double get monthlyEarnings {
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final monthTransactions = recentTransactions.where((tx) => tx.timestamp.isAfter(monthAgo));
    
    return monthTransactions.fold(0.0, (sum, tx) => sum + tx.amount);
  }
  
  String get topEarningType {
    if (earningsByType.isEmpty) return 'none';
    
    return earningsByType.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
  
  UserEarnings copyWith({
    String? userId,
    double? totalEarnings,
    double? totalPaid,
    double? pendingEarnings,
    Map<String, double>? earningsByType,
    List<EarningTransaction>? recentTransactions,
    DateTime? lastUpdated,
    int? contributionCount,
    double? averageQualityScore,
    Map<String, int>? contributionsByType,
  }) {
    return UserEarnings(
      userId: userId ?? this.userId,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      totalPaid: totalPaid ?? this.totalPaid,
      pendingEarnings: pendingEarnings ?? this.pendingEarnings,
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
class EarningTransaction {
  final String id;
  final String userId;
  final double amount;
  final String type;
  final String contributionId;
  final DateTime timestamp;
  final String status;
  final String? transactionHash;
  final String paymentMethod;
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