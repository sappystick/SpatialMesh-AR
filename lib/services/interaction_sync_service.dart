import 'dart:async';
import 'package:vector_math/vector_math_64.dart';
import '../services/collaborative_ar_service.dart';

class InteractionSynchronizer {
  final bool predictionEnabled;
  final bool interpolationEnabled;
  final bool latencyCompensation;

  final _predictionEngine = InteractionPredictionEngine();
  final _interpolator = InteractionInterpolator();
  final _latencyCompensator = LatencyCompensator();

  InteractionSynchronizer({
    required this.predictionEnabled,
    required this.interpolationEnabled,
    required this.latencyCompensation,
  });

  Future<ARInteraction> predictInteraction(ARInteraction interaction) async {
    var processedInteraction = interaction;

    if (predictionEnabled) {
      processedInteraction = await _predictionEngine.predictInteraction(
        processedInteraction,
      );
    }

    if (interpolationEnabled) {
      processedInteraction = await _interpolator.interpolateInteraction(
        processedInteraction,
      );
    }

    if (latencyCompensation) {
      processedInteraction = await _latencyCompensator.compensateLatency(
        processedInteraction,
      );
    }

    return processedInteraction;
  }
}

class InteractionPredictionEngine {
  final List<ARInteraction> _recentInteractions = [];
  static const _maxHistorySize = 10;

  Future<ARInteraction> predictInteraction(ARInteraction interaction) async {
    // Add to history
    _recentInteractions.add(interaction);
    if (_recentInteractions.length > _maxHistorySize) {
      _recentInteractions.removeAt(0);
    }

    // Predict next position and orientation based on recent movement patterns
    if (_recentInteractions.length >= 2) {
      final predictedPosition = _predictPosition(interaction);
      final predictedOrientation = _predictOrientation(interaction);

      return ARInteraction(
        userId: interaction.userId,
        type: interaction.type,
        position: predictedPosition,
        orientation: predictedOrientation,
        data: interaction.data,
        timestamp: interaction.timestamp,
      );
    }

    return interaction;
  }

  Vector3 _predictPosition(ARInteraction current) {
    if (_recentInteractions.length < 2) return current.position;

    final previous = _recentInteractions[_recentInteractions.length - 2];
    final velocity = current.position - previous.position;
    final timeDelta = current.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    
    // Simple linear prediction
    return current.position + (velocity * timeDelta);
  }

  Quaternion _predictOrientation(ARInteraction current) {
    if (_recentInteractions.length < 2) return current.orientation;

    final previous = _recentInteractions[_recentInteractions.length - 2];
    
    // Calculate angular velocity
    final diff = current.orientation * previous.orientation.inverted();
    final angle = 2.0 * acos(diff.w);
    final timeDelta = current.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    
    if (angle.abs() < 1e-6) return current.orientation;

    final axis = Vector3(diff.x, diff.y, diff.z).normalized();
    final angularVelocity = angle / timeDelta;
    
    // Predict next orientation
    final predictedAngle = angularVelocity * timeDelta;
    final prediction = Quaternion.axisAngle(axis, predictedAngle);
    
    return prediction * current.orientation;
  }
}

class InteractionInterpolator {
  static const _interpolationSteps = 10;

  Future<ARInteraction> interpolateInteraction(ARInteraction interaction) async {
    // For now, return the original interaction
    // In a real implementation, this would smooth out movement between updates
    return interaction;
  }

  Vector3 _interpolatePosition(Vector3 start, Vector3 end, double t) {
    return start + (end - start) * t;
  }

  Quaternion _interpolateOrientation(Quaternion start, Quaternion end, double t) {
    return Quaternion.slerp(start, end, t);
  }
}

class LatencyCompensator {
  final _latencyWindow = Duration(milliseconds: 100);
  final Map<String, List<ARInteraction>> _interactionHistory = {};

  Future<ARInteraction> compensateLatency(ARInteraction interaction) async {
    _updateHistory(interaction);
    
    // Apply latency compensation based on network conditions
    // This is a simplified implementation
    return interaction;
  }

  void _updateHistory(ARInteraction interaction) {
    if (!_interactionHistory.containsKey(interaction.userId)) {
      _interactionHistory[interaction.userId] = [];
    }

    _interactionHistory[interaction.userId]!.add(interaction);
    
    // Cleanup old history
    final cutoff = DateTime.now().subtract(_latencyWindow);
    _interactionHistory[interaction.userId]!.removeWhere(
      (i) => i.timestamp.isBefore(cutoff)
    );
  }
}

class InteractionBuffer {
  final int maxSize;
  final List<ARInteraction> _buffer = [];
  
  InteractionBuffer({this.maxSize = 100});
  
  void add(ARInteraction interaction) {
    _buffer.add(interaction);
    if (_buffer.length > maxSize) {
      _buffer.removeAt(0);
    }
  }
  
  List<ARInteraction> getRecent(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return _buffer.where((i) => i.timestamp.isAfter(cutoff)).toList();
  }
  
  void clear() {
    _buffer.clear();
  }
}