import 'dart:async';
import 'dart:math';
import 'package:injectable/injectable.dart';
import 'package:amplitude_flutter/amplitude.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:aws_cloudwatch/aws_cloudwatch.dart';

import '../core/app_config.dart';
import '../core/service_locator.dart';
import '../models/user_earnings.dart';
import '../models/spatial_anchor.dart';
import '../services/mesh_network_service.dart';
import '../services/ar_service.dart';
import '../services/monetization_service.dart';

@singleton
class AnalyticsService {
  static const BATCH_SIZE = 100;
  static const BATCH_INTERVAL = Duration(seconds: 30);
  static const PERFORMANCE_SAMPLE_RATE = 0.1;
  static const ERROR_SAMPLE_RATE = 1.0;
  static const METRICS_INTERVAL = Duration(minutes: 1);
  
  // Analytics providers
  late final Amplitude _amplitude;
  late final Mixpanel _mixpanel;
  late final FirebaseAnalytics _firebaseAnalytics;
  late final CloudWatch _cloudWatch;
  
  // Event batching
  final List<Map<String, dynamic>> _eventQueue = [];
  Timer? _batchTimer;
  
  // Performance monitoring
  final Map<String, List<double>> _performanceMetrics = {};
  final Map<String, DateTime> _sessionStarts = {};
  Timer? _metricsTimer;
  
  // Error tracking
  int _errorCount = 0;
  final Map<String, int> _errorsByType = {};
  
  // User session data
  String? _currentUserId;
  final Map<String, dynamic> _userProperties = {};
  final Map<String, dynamic> _sessionProperties = {};
  
  bool _isInitialized = false;
  
  AnalyticsService();
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize Amplitude
      _amplitude = Amplitude.getInstance();
      await _amplitude.init(AppConfig.amplitudeApiKey);
      await _amplitude.enableCoppaControl();
      await _amplitude.setServerUrl(AppConfig.amplitudeServerUrl);
      
      // Initialize Mixpanel
      _mixpanel = await Mixpanel.init(
        AppConfig.mixpanelToken,
        optOutTrackingDefault: !AppConfig.isAnalyticsEnabled,
      );
      
      // Initialize Firebase Analytics
      _firebaseAnalytics = FirebaseAnalytics.instance;
      await _firebaseAnalytics.setAnalyticsCollectionEnabled(AppConfig.isAnalyticsEnabled);
      
      // Initialize CloudWatch
      _cloudWatch = CloudWatch(
        region: AppConfig.awsRegion,
        namespace: 'SpatialMeshAR/${AppConfig.environment}',
      );
      
      // Start event batching
      _startEventBatching();
      
      // Start metrics collection
      _startMetricsCollection();
      
      // Initialize error tracking
      await _initializeErrorTracking();
      
      // Set up automatic event tracking
      _setupAutoTracking();
      
      _isInitialized = true;
      print('✅ Analytics Service initialized successfully');
    } catch (e) {
      print('❌ Analytics Service initialization failed: $e');
      rethrow;
    }
  }
  
  void _startEventBatching() {
    _batchTimer = Timer.periodic(BATCH_INTERVAL, (_) => _processBatch());
  }
  
  void _startMetricsCollection() {
    _metricsTimer = Timer.periodic(METRICS_INTERVAL, (_) => _collectMetrics());
  }
  
  Future<void> _initializeErrorTracking() async {
    await Sentry.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.environment;
        options.tracesSampleRate = ERROR_SAMPLE_RATE;
        options.attachStacktrace = true;
        options.beforeSend = _beforeSendError;
      },
    );
  }
  
  Future<SentryEvent?> _beforeSendError(SentryEvent event, {dynamic hint}) async {
    // Update error stats
    _errorCount++;
    _errorsByType[event.exceptions?.first.type ?? 'unknown'] =
        (_errorsByType[event.exceptions?.first.type ?? 'unknown'] ?? 0) + 1;
    
    // Add session context
    event = event.copyWith(
      extra: {
        ...event.extra ?? {},
        'session_id': _sessionProperties['session_id'],
        'session_duration': _getSessionDuration(),
        'user_properties': _userProperties,
      },
    );
    
    return event;
  }
  
  void _setupAutoTracking() {
    // Track AR sessions
    final arService = getIt<ARService>();
    arService.stateChanges.listen((state) {
      if (state.isActive) {
        _trackSessionStart('ar_session');
      } else {
        _trackSessionEnd('ar_session');
      }
    });
    
    // Track mesh network events
    final meshService = getIt<MeshNetworkService>();
    meshService.events.listen((event) {
      _trackEvent(
        'mesh_network_event',
        {
          'type': event.type.toString(),
          'peers': event.peers?.length ?? 0,
          'data_transferred': event.dataTransferred,
        },
      );
    });
    
    // Track monetization events
    final monetizationService = getIt<MonetizationService>();
    monetizationService.earningsStream.listen((earnings) {
      _trackEvent(
        'earnings_update',
        {
          'total_earnings': earnings.totalEarnings.toString(),
          'available_balance': earnings.availableBalance.toString(),
          'pending_balance': earnings.pendingBalance.toString(),
        },
      );
    });
  }
  
  Future<void> setUser(String userId, {Map<String, dynamic>? properties}) async {
    _currentUserId = userId;
    
    if (properties != null) {
      _userProperties.addAll(properties);
    }
    
    // Update user in all providers
    await Future.wait([
      _amplitude.setUserId(userId),
      _amplitude.setUserProperties(_userProperties),
      _mixpanel.identify(userId),
      _mixpanel.getPeople().set(_userProperties),
      _firebaseAnalytics.setUserId(id: userId),
      for (final entry in _userProperties.entries)
        _firebaseAnalytics.setUserProperty(
          name: entry.key,
          value: entry.value.toString(),
        ),
    ]);
  }
  
  Future<void> trackEvent(
    String name,
    Map<String, dynamic> properties, {
    bool immediate = false,
  }) async {
    if (!_isInitialized) {
      print('❌ Analytics Service not initialized');
      return;
    }
    
    final event = {
      'name': name,
      'properties': {
        ...properties,
        'timestamp': DateTime.now().toIso8601String(),
        'session_id': _sessionProperties['session_id'],
        'user_id': _currentUserId,
      },
    };
    
    if (immediate) {
      await _sendEvent(event);
    } else {
      _eventQueue.add(event);
      
      if (_eventQueue.length >= BATCH_SIZE) {
        await _processBatch();
      }
    }
  }
  
  void _trackEvent(String name, Map<String, dynamic> properties) {
    trackEvent(name, properties);
  }
  
  Future<void> _processBatch() async {
    if (_eventQueue.isEmpty) return;
    
    final batch = List<Map<String, dynamic>>.from(_eventQueue);
    _eventQueue.clear();
    
    try {
      await Future.wait([
        _sendToAmplitude(batch),
        _sendToMixpanel(batch),
        _sendToFirebase(batch),
        _sendToCloudWatch(batch),
      ]);
    } catch (e) {
      print('❌ Error processing analytics batch: $e');
      // Re-queue failed events
      _eventQueue.insertAll(0, batch);
    }
  }
  
  Future<void> _sendEvent(Map<String, dynamic> event) async {
    try {
      await Future.wait([
        _amplitude.logEvent(
          name: event['name'],
          properties: event['properties'],
        ),
        _mixpanel.track(
          event['name'],
          properties: event['properties'],
        ),
        _firebaseAnalytics.logEvent(
          name: event['name'],
          parameters: event['properties'],
        ),
        _cloudWatch.putMetricData([
          MetricDatum(
            metricName: event['name'],
            value: 1,
            timestamp: DateTime.parse(event['properties']['timestamp']),
            dimensions: event['properties'].entries.map(
              (e) => Dimension(name: e.key, value: e.value.toString()),
            ).toList(),
          ),
        ]),
      ]);
    } catch (e) {
      print('❌ Error sending event: $e');
      rethrow;
    }
  }
  
  void trackPerformanceMetric(String name, double value) {
    if (!_shouldSampleMetric()) return;
    
    _performanceMetrics.putIfAbsent(name, () => []).add(value);
  }
  
  void _trackSessionStart(String type) {
    _sessionStarts[type] = DateTime.now();
    
    _sessionProperties['${type}_start'] = _sessionStarts[type]!.toIso8601String();
    
    _trackEvent('session_start', {
      'type': type,
      'timestamp': _sessionStarts[type]!.toIso8601String(),
    });
  }
  
  void _trackSessionEnd(String type) {
    final startTime = _sessionStarts[type];
    if (startTime == null) return;
    
    final duration = DateTime.now().difference(startTime);
    
    _trackEvent('session_end', {
      'type': type,
      'duration': duration.inSeconds,
      'start_time': startTime.toIso8601String(),
      'end_time': DateTime.now().toIso8601String(),
    });
    
    _sessionStarts.remove(type);
    _sessionProperties.remove('${type}_start');
  }
  
  Future<void> _collectMetrics() async {
    try {
      // Collect performance metrics
      for (final entry in _performanceMetrics.entries) {
        final values = entry.value;
        if (values.isEmpty) continue;
        
        final avgValue = values.reduce((a, b) => a + b) / values.length;
        
        await _cloudWatch.putMetricData([
          MetricDatum(
            metricName: '${entry.key}_avg',
            value: avgValue,
            unit: StandardUnit.milliseconds,
          ),
          MetricDatum(
            metricName: '${entry.key}_p95',
            value: _calculatePercentile(values, 0.95),
            unit: StandardUnit.milliseconds,
          ),
        ]);
        
        values.clear();
      }
      
      // Collect error metrics
      if (_errorCount > 0) {
        await _cloudWatch.putMetricData([
          MetricDatum(
            metricName: 'error_count',
            value: _errorCount.toDouble(),
            unit: StandardUnit.count,
          ),
          for (final entry in _errorsByType.entries)
            MetricDatum(
              metricName: 'errors_by_type',
              value: entry.value.toDouble(),
              dimensions: [
                Dimension(
                  name: 'error_type',
                  value: entry.key,
                ),
              ],
            ),
        ]);
        
        _errorCount = 0;
        _errorsByType.clear();
      }
      
    } catch (e) {
      print('❌ Error collecting metrics: $e');
    }
  }
  
  double _calculatePercentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    
    final sorted = List<double>.from(values)..sort();
    final index = (sorted.length * percentile).round() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }
  
  bool _shouldSampleMetric() {
    return Random().nextDouble() < PERFORMANCE_SAMPLE_RATE;
  }
  
  Duration _getSessionDuration() {
    final firstStart = _sessionStarts.values.fold<DateTime?>(
      null,
      (min, time) => min == null || time.isBefore(min) ? time : min,
    );
    
    if (firstStart == null) return Duration.zero;
    return DateTime.now().difference(firstStart);
  }
  
  @override
  Future<void> dispose() async {
    _batchTimer?.cancel();
    _metricsTimer?.cancel();
    
    // Process remaining events
    await _processBatch();
    
    // End all active sessions
    final activeSessions = List<String>.from(_sessionStarts.keys);
    for (final sessionType in activeSessions) {
      _trackSessionEnd(sessionType);
    }
    
    _isInitialized = false;
  }
}
