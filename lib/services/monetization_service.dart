import 'package:injectable/injectable.dart';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

import '../core/app_config.dart';
import '../models/spatial_anchor.dart';
import '../models/user_earnings.dart';
import 'aws_service.dart';
import 'analytics_service.dart';
import '../core/service_locator.dart';
import 'blockchain/blockchain_manager.dart';
import 'lightning/lightning_manager.dart';

@singleton
class MonetizationService {
  static const BLOCKCHAIN_THRESHOLD = Decimal.parse('0.1');  // 0.1 ETH
  static const MIN_WITHDRAWAL = Decimal.parse('0.01');  // 0.01 ETH/BTC

  late final BlockchainManager _blockchainManager;
  late final LightningManager _lightningManager;
  
  final Map<String, UserEarnings> _userEarnings = {};
  final Map<String, Decimal> _pendingPayouts = {};
  final _earningsController = StreamController<UserEarnings>.broadcast();
  
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  Stream<UserEarnings> get earningsStream => _earningsController.stream;
  
  Future<void> initialize() async {
    try {
      // Initialize blockchain manager
      _blockchainManager = BlockchainManager(
        network: BlockchainNetwork.polygon,  // Use Polygon for low fees
      );
      await _blockchainManager.initialize();
      
      // Initialize lightning manager if in production
      if (AppConfig.isProduction) {
        _lightningManager = LightningManager(
          nodeUrl: const String.fromEnvironment('LIGHTNING_NODE_URL'),
          macaroon: const String.fromEnvironment('LIGHTNING_MACAROON'),
        );
        await _lightningManager.initialize();
      }
      
      // Subscribe to payment events
      _subscribeToEvents();
      
      _isInitialized = true;
      safePrint('✅ Monetization Service initialized successfully');
    } catch (e) {
      safePrint('❌ Monetization Service initialization failed: $e');
      rethrow;
    }
  }
  
  void _subscribeToEvents() {
    // Subscribe to blockchain events
    _blockchainManager.events.listen((event) {
      switch (event.type) {
        case BlockchainEventType.paymentConfirmed:
          _handlePaymentConfirmed(
            event.payment.userId,
            event.payment.amount,
            PaymentType.blockchain,
          );
          break;
        default:
          break;
      }
    });
    
    // Subscribe to lightning events if in production
    if (_lightningManager != null) {
      _lightningManager.events.listen((event) {
        switch (event.type) {
          case LightningEventType.invoicePaid:
            _handlePaymentConfirmed(
              event.invoice.userId,
              event.invoice.amount,
              PaymentType.lightning,
            );
            break;
          default:
            break;
        }
      });
    }
  }
  
  void _handlePaymentConfirmed(
    String userId,
    Decimal amount,
    PaymentType type,
  ) {
    // Update user earnings
    _userEarnings.update(
      userId,
      (earnings) => earnings.copyWith(
        totalEarnings: earnings.totalEarnings + amount,
        availableBalance: earnings.availableBalance + amount,
      ),
      ifAbsent: () => UserEarnings(
        userId: userId,
        totalEarnings: amount,
        availableBalance: amount,
        pendingBalance: Decimal.zero,
        lifetimeWithdrawals: Decimal.zero,
      ),
    );
    
    final earnings = _userEarnings[userId]!;
    _earningsController.add(earnings);
    
    // Track analytics
    final analyticsService = getIt<AnalyticsService>();
    analyticsService.trackEvent('payment_confirmed', {
      'user_id': userId,
      'amount': amount.toString(),
      'payment_type': type.toString(),
    });
  }
  
  Future<Decimal> recordSpatialContribution(
    String userId,
    SpatialContribution contribution,
  ) async {
    if (!_isInitialized) {
      throw StateError('Monetization Service not initialized');
    }
    
    try {
      // Calculate earnings based on contribution type and quality
      final earnings = _calculateEarnings(contribution);
      final decimalEarnings = Decimal.parse(earnings.toStringAsFixed(6));
      
      // Update user earnings
      final currentEarnings = await getUserEarnings(userId);
      final updatedEarnings = currentEarnings.copyWith(
        totalEarnings: currentEarnings.totalEarnings + decimalEarnings,
        pendingBalance: currentEarnings.pendingBalance + decimalEarnings,
      );
      
      _userEarnings[userId] = updatedEarnings;
      _earningsController.add(updatedEarnings);
      
      // Store in AWS DynamoDB
      final awsService = getIt<AWSService>();
      await awsService.updateUserEarnings(userId, decimalEarnings);
      
      // Process instant payment if threshold met
      _pendingPayouts[userId] = (_pendingPayouts[userId] ?? Decimal.zero) + decimalEarnings;
      
      if (_pendingPayouts[userId]! >= MIN_WITHDRAWAL) {
        await _processInstantPayout(userId, _pendingPayouts[userId]!);
        _pendingPayouts[userId] = Decimal.zero;
      }
      
      // Track analytics
      final analyticsService = getIt<AnalyticsService>();
      await analyticsService.trackEvent('earnings_recorded', {
        'user_id': userId,
        'contribution_type': contribution.type,
        'earnings': decimalEarnings.toString(),
        'quality_score': contribution.qualityScore,
      });
      
      return decimalEarnings;
      
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
    
    await recordSpatialContribution(userId, contribution);
  }
  
  Future<UserEarnings> getUserEarnings(String userId) async {
    // Check local cache first
    final cachedEarnings = _userEarnings[userId];
    if (cachedEarnings != null) return cachedEarnings;
    
    // Fetch from AWS if not in cache
    final awsService = getIt<AWSService>();
    final earnings = await awsService.getUserEarnings(userId);
    
    _userEarnings[userId] = earnings;
    return earnings;
  }
  
  Future<String> createPaymentRequest({
    required String userId,
    required Decimal amount,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Choose payment method based on amount
      if (amount >= BLOCKCHAIN_THRESHOLD) {
        return await _blockchainManager.createPaymentRequest(
          userId: userId,
          amount: amount,
          metadata: metadata,
        );
      } else if (_lightningManager != null) {
        return await _lightningManager.createInvoice(
          userId: userId,
          amount: amount,
          metadata: metadata,
        );
      } else {
        throw UnsupportedError('No payment method available for amount: \$${amount.toString()}');
      }
    } catch (e) {
      safePrint('❌ Error creating payment request: $e');
      rethrow;
    }
  }
  
  Future<PaymentStatus> checkPayment(String paymentId) async {
    try {
      // Try blockchain first
      final blockchainStatus = await _blockchainManager.checkPayment(paymentId);
      if (blockchainStatus != PaymentStatus.notFound) {
        return blockchainStatus;
      }
      
      // Try lightning if available
      if (_lightningManager != null) {
        return await _lightningManager.checkInvoice(paymentId);
      }
      
      return PaymentStatus.notFound;
      
    } catch (e) {
      safePrint('❌ Error checking payment: $e');
      rethrow;
    }
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
  
  Future<void> _processInstantPayout(String userId, Decimal amount) async {
    try {
      final userPreferences = await _getUserPaymentPreferences(userId);
      
      String txId;
      if (amount >= BLOCKCHAIN_THRESHOLD && userPreferences.blockchainAddress != null) {
        // Use blockchain for larger amounts
        txId = await _blockchainManager.withdraw(
          userId: userId,
          address: userPreferences.blockchainAddress!,
          amount: amount,
        );
      } else if (_lightningManager != null && userPreferences.lightningAddress != null) {
        // Use Lightning Network for smaller amounts
        txId = await _lightningManager.sendPayment(
          paymentRequest: userPreferences.lightningAddress!,
        );
      } else {
        throw UnsupportedError('No payment method available for user: $userId');
      }
      
      await _recordPayoutSuccess(userId, amount, txId);
      safePrint('💰 Instant payout processed: \$${amount.toString()} to $userId');
      
    } catch (e) {
      safePrint('❌ Payout processing failed: $e');
      // Queue for later processing
      _queueFailedPayout(userId, amount);
    }
  }
  
  Future<UserPaymentPreferences> _getUserPaymentPreferences(String userId) async {
    final awsService = getIt<AWSService>();
    return await awsService.getUserPaymentPreferences(userId);
  }
  
  Future<void> _recordPayoutSuccess(
    String userId,
    Decimal amount,
    String transactionId,
  ) async {
    final awsService = getIt<AWSService>();
    
    // Get current earnings
    final earnings = await getUserEarnings(userId);
    
    // Update earnings
    final updatedEarnings = earnings.copyWith(
      availableBalance: earnings.availableBalance - amount,
      lifetimeWithdrawals: earnings.lifetimeWithdrawals + amount,
    );
    
    // Update in AWS and local cache
    await awsService.updateUserEarnings(userId, -amount);
    _userEarnings[userId] = updatedEarnings;
    _earningsController.add(updatedEarnings);
    
    // Record payout transaction
    await awsService.recordPayout(userId, amount, transactionId);
    
    // Track analytics
    final analyticsService = getIt<AnalyticsService>();
    await analyticsService.trackEvent('payout_processed', {
      'user_id': userId,
      'amount': amount.toString(),
      'transaction_id': transactionId,
    });
  }
  
  void _queueFailedPayout(String userId, Decimal amount) {
    // Queue failed payout for retry
    _pendingPayouts[userId] = (_pendingPayouts[userId] ?? Decimal.zero) + amount;
  }
  
  @override
  Future<void> dispose() async {
    await _blockchainManager.dispose();
    if (_lightningManager != null) {
      await _lightningManager.dispose();
    }
    await _earningsController.close();
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