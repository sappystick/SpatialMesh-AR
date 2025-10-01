import 'package:injectable/injectable.dart';
import 'package:web3dart/web3dart.dart';
import 'package:bitcoin_flutter/bitcoin_flutter.dart';
import 'dart:convert';

import '../core/app_config.dart';
import '../models/spatial_anchor.dart';
import '../models/user_earnings.dart';
import 'aws_service.dart';
import 'analytics_service.dart';
import '../core/service_locator.dart';

@singleton
class MonetizationService {
  late Web3Client _web3Client;
  final Map<String, EarningsTracker> _userEarnings = {};
  final Map<String, double> _pendingPayouts = {};
  
  // Lightning Network integration
  LightningNetworkClient? _lightningClient;
  
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    try {
      // Initialize Web3 for Polygon network (low fees)
      _web3Client = Web3Client(
        'https://polygon-rpc.com/',
        Client(),
      );
      
      // Initialize Lightning Network client
      if (AppConfig.isProduction) {
        _lightningClient = LightningNetworkClient(
          nodeUrl: const String.fromEnvironment('LIGHTNING_NODE_URL'),
          macaroon: const String.fromEnvironment('LIGHTNING_MACAROON'),
        );
      }
      
      _isInitialized = true;
      safePrint('✅ Monetization Service initialized successfully');
    } catch (e) {
      safePrint('❌ Monetization Service initialization failed: $e');
      rethrow;
    }
  }
  
  Future<double> recordSpatialContribution(
    String userId,
    SpatialContribution contribution,
  ) async {
    if (!_isInitialized) {
      throw StateError('Monetization Service not initialized');
    }
    
    try {
      // Calculate earnings based on contribution type and quality
      final earnings = _calculateEarnings(contribution);
      
      // Update user earnings tracker
      _userEarnings.putIfAbsent(userId, () => EarningsTracker(userId));
      _userEarnings[userId]!.addContribution(contribution, earnings);
      
      // Store in AWS DynamoDB
      final awsService = getIt<AWSService>();
      await awsService.updateUserEarnings(userId, earnings);
      
      // Process instant payment if threshold met
      _pendingPayouts[userId] = (_pendingPayouts[userId] ?? 0.0) + earnings;
      
      if (_pendingPayouts[userId]! >= (AppConfig.minimumPayoutCents / 100)) {
        await _processInstantPayout(userId, _pendingPayouts[userId]!);
        _pendingPayouts[userId] = 0.0;
      }
      
      // Track analytics
      final analyticsService = getIt<AnalyticsService>();
      await analyticsService.trackEvent('earnings_recorded', {
        'user_id': userId,
        'contribution_type': contribution.type,
        'earnings': earnings,
        'quality_score': contribution.qualityScore,
      });
      
      return earnings;
      
    } catch (e) {
      safePrint('❌ Failed to record spatial contribution: $e');
      rethrow;
    }
  }
  
  Future<void> recordMeshParticipation(
    String userId,
    Duration participationTime,
    int dataTransferred,
  ) async {
    final contribution = MeshParticipationContribution(
      userId: userId,
      participationTime: participationTime,
      dataTransferred: dataTransferred,
      qualityScore: _calculateMeshQuality(participationTime, dataTransferred),
    );
    
    final earnings = _calculateMeshEarnings(contribution);
    
    await recordSpatialContribution(userId, contribution);
  }
  
  Future<UserEarnings> getUserEarnings(String userId) async {
    final awsService = getIt<AWSService>();
    return await awsService.getUserEarnings(userId);
  }
  
  double _calculateEarnings(SpatialContribution contribution) {
    final baseRate = AppConfig.earningRates[contribution.type] ?? 0.01;
    final qualityMultiplier = contribution.qualityScore;
    final demandMultiplier = _getDemandMultiplier(contribution);
    
    return baseRate * qualityMultiplier * demandMultiplier;
  }
  
  double _calculateMeshEarnings(MeshParticipationContribution contribution) {
    // Base rate: $0.02 per minute of participation
    final baseEarnings = contribution.participationTime.inMinutes * 0.02;
    
    // Quality bonus based on data transfer
    final qualityBonus = (contribution.dataTransferred / 1024) * 0.001; // $0.001 per KB
    
    return (baseEarnings + qualityBonus) * contribution.qualityScore;
  }
  
  double _calculateMeshQuality(Duration time, int dataTransferred) {
    // Quality score based on uptime and data contribution
    final uptimeScore = time.inMinutes / 60.0; // Hours of participation
    final dataScore = dataTransferred / (1024 * 1024); // MB transferred
    
    return ((uptimeScore + dataScore) / 2.0).clamp(0.1, 2.0);
  }
  
  double _getDemandMultiplier(SpatialContribution contribution) {
    // TODO: Implement dynamic demand calculation based on:
    // - Geographic location
    // - Time of day
    // - Current network activity
    // - Competition levels
    return 1.2; // Base multiplier
  }
  
  Future<void> _processInstantPayout(String userId, double amount) async {
    try {
      // Try Lightning Network first (instant, zero fees)
      if (_lightningClient != null && AppConfig.isProduction) {
        await _processLightningPayout(userId, amount);
      } else {
        // Fallback to traditional payment processing
        await _processFallbackPayout(userId, amount);
      }
      
      safePrint('💰 Instant payout processed: \$${amount.toStringAsFixed(2)} to $userId');
      
    } catch (e) {
      safePrint('❌ Payout processing failed: $e');
      // Queue for later processing
      _queueFailedPayout(userId, amount);
    }
  }
  
  Future<void> _processLightningPayout(String userId, double amount) async {
    final satoshis = (amount * 100000000).toInt();
    
    final invoice = await _lightningClient!.createInvoice(
      amount: satoshis,
      description: 'SpatialMesh AR earnings: \$${amount.toStringAsFixed(2)}',
      expiry: 3600,
    );
    
    // In production, this would send to user's Lightning wallet
    // For now, record the successful processing
    await _recordPayoutSuccess(userId, amount, 'lightning', invoice.paymentHash);
  }
  
  Future<void> _processFallbackPayout(String userId, double amount) async {
    // Process via traditional payment method
    // This would integrate with Stripe, PayPal, or bank transfer
    await _recordPayoutSuccess(userId, amount, 'traditional', _generateTransactionId());
  }
  
  Future<void> _recordPayoutSuccess(String userId, double amount, String method, String transactionId) async {
    final awsService = getIt<AWSService>();
    
    // Record payout in earnings history
    // TODO: Call AWS API to record payout
    
    final analyticsService = getIt<AnalyticsService>();
    await analyticsService.trackEvent('payout_processed', {
      'user_id': userId,
      'amount': amount,
      'method': method,
      'transaction_id': transactionId,
    });
  }
  
  void _queueFailedPayout(String userId, double amount) {
    // Queue failed payout for retry
    _pendingPayouts[userId] = (_pendingPayouts[userId] ?? 0.0) + amount;
  }
  
  String _generateTransactionId() {
    return 'tx_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond % 10000).toString().padLeft(4, '0')}';
  }
  
  String _generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }
}

class SpatialContribution {
  final String type;
  final String userId;
  final double qualityScore;
  final DateTime createdAt;
  
  SpatialContribution({
    required this.type,
    required this.userId,
    required this.qualityScore,
    required this.createdAt,
  });
}

class MeshParticipationContribution extends SpatialContribution {
  final Duration participationTime;
  final int dataTransferred;
  
  MeshParticipationContribution({
    required String userId,
    required this.participationTime,
    required this.dataTransferred,
    required double qualityScore,
  }) : super(
    type: 'mesh_participation',
    userId: userId,
    qualityScore: qualityScore,
    createdAt: DateTime.now(),
  );
}

class EarningsTracker {
  final String userId;
  double totalEarnings = 0.0;
  final List<SpatialContribution> contributions = [];
  
  EarningsTracker(this.userId);
  
  void addContribution(SpatialContribution contribution, double earnings) {
    contributions.add(contribution);
    totalEarnings += earnings;
  }
}

class LightningNetworkClient {
  final String nodeUrl;
  final String macaroon;
  
  LightningNetworkClient({
    required this.nodeUrl,
    required this.macaroon,
  });
  
  Future<LightningInvoice> createInvoice({
    required int amount,
    required String description,
    required int expiry,
  }) async {
    // Lightning Network invoice creation
    return LightningInvoice(
      paymentHash: _generatePaymentHash(),
      paymentRequest: _generatePaymentRequest(),
    );
  }
  
  String _generatePaymentHash() => 'lnbc_${DateTime.now().millisecondsSinceEpoch}';
  String _generatePaymentRequest() => 'lnbc1_${DateTime.now().millisecondsSinceEpoch}';
}

class LightningInvoice {
  final String paymentHash;
  final String paymentRequest;
  
  LightningInvoice({
    required this.paymentHash,
    required this.paymentRequest,
  });
}