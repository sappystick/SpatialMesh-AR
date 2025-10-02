import 'dart:async';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class MeshAnalytics {
  static const ANALYTICS_FILE = 'mesh_analytics.json';
  static const METRICS_INTERVAL = Duration(minutes: 1);
  static const PERSIST_INTERVAL = Duration(minutes: 15);
  static const MAX_EVENTS = 1000;
  
  final bool enabled;
  final _events = Queue<AnalyticsEvent>();
  final _metrics = <String, MetricSeries>{};
  
  Timer? _metricsTimer;
  Timer? _persistTimer;
  DateTime? _lastPersist;
  
  // Real-time metrics
  int _activeConnections = 0;
  int _messagesSent = 0;
  int _messagesReceived = 0;
  Map<String, double> _peerLatencies = {};
  Map<String, int> _peerErrors = {};
  
  MeshAnalytics({required this.enabled});
  
  Future<void> initialize() async {
    if (!enabled) return;
    
    try {
      // Restore previous analytics
      await _restoreAnalytics();
      
      // Start periodic metrics collection
      _metricsTimer = Timer.periodic(
        METRICS_INTERVAL,
        (_) => _collectMetrics(),
      );
      
      // Start periodic persistence
      _persistTimer = Timer.periodic(
        PERSIST_INTERVAL,
        (_) => _persistAnalytics(),
      );
      
    } catch (e) {
      print('Analytics initialization error: $e');
    }
  }
  
  void trackPeerConnection(String peerId) {
    if (!enabled) return;
    
    _activeConnections++;
    _trackEvent(AnalyticsEventType.peerConnected, {
      'peer_id': peerId,
      'active_connections': _activeConnections,
    });
  }
  
  void trackPeerDisconnection(String peerId) {
    if (!enabled) return;
    
    _activeConnections--;
    _trackEvent(AnalyticsEventType.peerDisconnected, {
      'peer_id': peerId,
      'active_connections': _activeConnections,
    });
    
    // Clean up peer metrics
    _peerLatencies.remove(peerId);
    _peerErrors.remove(peerId);
  }
  
  void trackMessage(MeshMessage message) {
    if (!enabled) return;
    
    _messagesSent++;
    _trackEvent(AnalyticsEventType.messageSent, {
      'message_id': message.id,
      'message_type': message.type.toString(),
      'sender_id': message.senderId,
      'timestamp': message.timestamp.toIso8601String(),
    });
  }
  
  void trackMessageReceived(
    String messageId,
    String senderId,
    Duration latency,
  ) {
    if (!enabled) return;
    
    _messagesReceived++;
    _updatePeerLatency(senderId, latency);
    
    _trackEvent(AnalyticsEventType.messageReceived, {
      'message_id': messageId,
      'sender_id': senderId,
      'latency_ms': latency.inMilliseconds,
    });
  }
  
  void trackMessageError(
    String messageId,
    String peerId,
    String error,
  ) {
    if (!enabled) return;
    
    _peerErrors[peerId] = (_peerErrors[peerId] ?? 0) + 1;
    
    _trackEvent(AnalyticsEventType.messageError, {
      'message_id': messageId,
      'peer_id': peerId,
      'error': error,
      'error_count': _peerErrors[peerId],
    });
  }
  
  void trackConnectionDegradation(String peerId) {
    if (!enabled) return;
    
    _trackEvent(AnalyticsEventType.connectionDegraded, {
      'peer_id': peerId,
      'error_count': _peerErrors[peerId] ?? 0,
      'latency_ms': _peerLatencies[peerId]?.round(),
    });
  }
  
  void _updatePeerLatency(String peerId, Duration latency) {
    final currentLatency = _peerLatencies[peerId] ?? 0;
    final weight = 0.7; // Exponential moving average weight
    
    _peerLatencies[peerId] = (currentLatency * (1 - weight)) +
                            (latency.inMilliseconds * weight);
  }
  
  void _trackEvent(
    AnalyticsEventType type,
    Map<String, dynamic> data,
  ) {
    final event = AnalyticsEvent(
      type: type,
      timestamp: DateTime.now(),
      data: data,
    );
    
    _events.add(event);
    
    // Trim events if needed
    while (_events.length > MAX_EVENTS) {
      _events.removeFirst();
    }
  }
  
  void _collectMetrics() {
    if (!enabled) return;
    
    final timestamp = DateTime.now();
    
    // Network metrics
    _updateMetricSeries('active_connections', timestamp, _activeConnections);
    _updateMetricSeries('messages_sent', timestamp, _messagesSent);
    _updateMetricSeries('messages_received', timestamp, _messagesReceived);
    
    // Peer metrics
    for (final entry in _peerLatencies.entries) {
      _updateMetricSeries(
        'peer_latency_${entry.key}',
        timestamp,
        entry.value,
      );
    }
    
    for (final entry in _peerErrors.entries) {
      _updateMetricSeries(
        'peer_errors_${entry.key}',
        timestamp,
        entry.value,
      );
    }
  }
  
  void _updateMetricSeries(
    String name,
    DateTime timestamp,
    num value,
  ) {
    if (!_metrics.containsKey(name)) {
      _metrics[name] = MetricSeries(name: name);
    }
    
    _metrics[name]!.addPoint(MetricPoint(
      timestamp: timestamp,
      value: value,
    ));
  }
  
  Future<void> _persistAnalytics() async {
    if (!enabled) return;
    
    try {
      final file = await _getAnalyticsFile();
      
      // Create analytics snapshot
      final snapshot = {
        'events': _events.map((e) => e.toJson()).toList(),
        'metrics': _metrics.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
      };
      
      // Add checksum
      final checksum = _computeChecksum(snapshot);
      snapshot['checksum'] = checksum;
      
      // Write to temporary file first
      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(json.encode(snapshot));
      
      // Replace analytics file
      await tempFile.rename(file.path);
      
      _lastPersist = DateTime.now();
      
    } catch (e) {
      print('Error persisting analytics: $e');
    }
  }
  
  Future<void> _restoreAnalytics() async {
    try {
      final file = await _getAnalyticsFile();
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        final json = jsonDecode(contents);
        
        // Validate analytics file
        if (!_validateAnalytics(json)) {
          print('Invalid analytics file, starting fresh');
          return;
        }
        
        // Restore events
        _events.clear();
        final events = json['events'] as List;
        for (final event in events) {
          _events.add(AnalyticsEvent.fromJson(event));
        }
        
        // Restore metrics
        _metrics.clear();
        final metrics = json['metrics'] as Map<String, dynamic>;
        for (final entry in metrics.entries) {
          _metrics[entry.key] = MetricSeries.fromJson(entry.value);
        }
      }
      
    } catch (e) {
      print('Error restoring analytics: $e');
    }
  }
  
  bool _validateAnalytics(Map<String, dynamic> json) {
    try {
      if (!json.containsKey('events') ||
          !json.containsKey('metrics') ||
          !json.containsKey('checksum')) {
        return false;
      }
      
      // Verify checksum
      final checksum = json['checksum'];
      final snapshot = {
        'events': json['events'],
        'metrics': json['metrics'],
      };
      
      final computedChecksum = _computeChecksum(snapshot);
      return checksum == computedChecksum;
    } catch (e) {
      print('Analytics validation error: $e');
      return false;
    }
  }
  
  String _computeChecksum(Map<String, dynamic> data) {
    final bytes = utf8.encode(json.encode(data));
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  Future<File> _getAnalyticsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$ANALYTICS_FILE');
  }
  
  Future<AnalyticsReport> generateReport({
    DateTime? start,
    DateTime? end,
  }) async {
    if (!enabled) {
      return AnalyticsReport(
        events: [],
        metrics: {},
        summary: {},
      );
    }
    
    final now = DateTime.now();
    start ??= now.subtract(const Duration(hours: 24));
    end ??= now;
    
    // Filter events in time range
    final filteredEvents = _events.where((event) =>
        event.timestamp.isAfter(start!) &&
        event.timestamp.isBefore(end!)).toList();
    
    // Filter metrics in time range
    final filteredMetrics = <String, List<MetricPoint>>{};
    for (final series in _metrics.entries) {
      filteredMetrics[series.key] = series.value.points
          .where((point) =>
              point.timestamp.isAfter(start!) &&
              point.timestamp.isBefore(end!))
          .toList();
    }
    
    // Generate summary statistics
    final summary = _generateSummary(
      filteredEvents,
      filteredMetrics,
      start,
      end,
    );
    
    return AnalyticsReport(
      events: filteredEvents,
      metrics: filteredMetrics,
      summary: summary,
    );
  }
  
  Map<String, dynamic> _generateSummary(
    List<AnalyticsEvent> events,
    Map<String, List<MetricPoint>> metrics,
    DateTime start,
    DateTime end,
  ) {
    final duration = end.difference(start);
    
    // Count events by type
    final eventCounts = <AnalyticsEventType, int>{};
    for (final event in events) {
      eventCounts[event.type] = (eventCounts[event.type] ?? 0) + 1;
    }
    
    // Calculate metric statistics
    final metricStats = <String, Map<String, num>>{};
    for (final entry in metrics.entries) {
      if (entry.value.isEmpty) continue;
      
      final values = entry.value.map((p) => p.value).toList();
      metricStats[entry.key] = {
        'min': values.reduce(min),
        'max': values.reduce(max),
        'avg': values.reduce((a, b) => a + b) / values.length,
      };
    }
    
    return {
      'time_range': {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'duration_hours': duration.inHours,
      },
      'events': eventCounts.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'metrics': metricStats,
    };
  }
  
  Future<void> dispose() async {
    _metricsTimer?.cancel();
    _persistTimer?.cancel();
    
    if (enabled) {
      await _persistAnalytics();
    }
  }
}

class AnalyticsEvent {
  final AnalyticsEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  
  AnalyticsEvent({
    required this.type,
    required this.timestamp,
    required this.data,
  });
  
  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return AnalyticsEvent(
      type: AnalyticsEventType.values[json['type']],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'type': type.index,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
  };
}

class MetricSeries {
  final String name;
  final List<MetricPoint> points;
  
  MetricSeries({
    required this.name,
    List<MetricPoint>? points,
  }) : points = points ?? [];
  
  void addPoint(MetricPoint point) {
    points.add(point);
    
    // Keep last 24 hours of data
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    points.removeWhere((p) => p.timestamp.isBefore(cutoff));
  }
  
  factory MetricSeries.fromJson(Map<String, dynamic> json) {
    return MetricSeries(
      name: json['name'],
      points: (json['points'] as List)
          .map((p) => MetricPoint.fromJson(p))
          .toList(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'points': points.map((p) => p.toJson()).toList(),
  };
}

class MetricPoint {
  final DateTime timestamp;
  final num value;
  
  MetricPoint({
    required this.timestamp,
    required this.value,
  });
  
  factory MetricPoint.fromJson(Map<String, dynamic> json) {
    return MetricPoint(
      timestamp: DateTime.parse(json['timestamp']),
      value: json['value'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'value': value,
  };
}

class AnalyticsReport {
  final List<AnalyticsEvent> events;
  final Map<String, List<MetricPoint>> metrics;
  final Map<String, dynamic> summary;
  
  AnalyticsReport({
    required this.events,
    required this.metrics,
    required this.summary,
  });
}

enum AnalyticsEventType {
  peerConnected,
  peerDisconnected,
  messageSent,
  messageReceived,
  messageError,
  connectionDegraded,
}

T min<T extends num>(T a, T b) => a < b ? a : b;
T max<T extends num>(T a, T b) => a > b ? a : b;