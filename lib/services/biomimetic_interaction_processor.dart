import 'package:vector_math/vector_math_64.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:injectable/injectable.dart';

@singleton
class BiomimeticInteractionProcessor {
  late Interpreter _gestureModel;
  late Interpreter _interactionModel;
  
  final Map<String, List<double>> _gesturePatterns = {};
  final Map<String, double> _adaptiveThresholds = {};
  
  static const String _gestureModelPath = 'assets/models/gesture_recognition.tflite';
  static const String _interactionModelPath = 'assets/models/interaction_patterns.tflite';
  
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    try {
      _gestureModel = await Interpreter.fromAsset(_gestureModelPath);
      _interactionModel = await Interpreter.fromAsset(_interactionModelPath);
      _initializeAdaptiveThresholds();
      _isInitialized = true;
    } catch (e) {
      print('❌ Biomimetic processor initialization failed: $e');
      rethrow;
    }
  }
  
  void _initializeAdaptiveThresholds() {
    _adaptiveThresholds.addAll({
      'gestureConfidence': 0.85,
      'patternMatching': 0.75,
      'temporalConsistency': 0.90,
      'spatialCoherence': 0.80,
    });
  }
  
  Future<Map<String, dynamic>> processInteraction({
    required List<Vector3> handPositions,
    required List<double> fingerAngles,
    required Vector3 devicePosition,
    required Matrix4 deviceOrientation,
  }) async {
    if (!_isInitialized) {
      throw Exception('Biomimetic processor not initialized');
    }
    
    // Prepare neural network inputs
    final gestureInput = _prepareGestureInput(handPositions, fingerAngles);
    final interactionInput = _prepareInteractionInput(
      handPositions,
      devicePosition,
      deviceOrientation,
    );
    
    // Process gesture recognition
    final gestureOutput = List<double>.filled(20, 0); // Adjust size based on model
    await _gestureModel.run(gestureInput, gestureOutput);
    
    // Process interaction patterns
    final interactionOutput = List<double>.filled(30, 0); // Adjust size based on model
    await _interactionModel.run(interactionInput, interactionOutput);
    
    // Analyze results
    final gestureAnalysis = _analyzeGesture(gestureOutput);
    final interactionAnalysis = _analyzeInteraction(interactionOutput);
    
    // Update adaptive learning
    _updateGesturePatterns(gestureAnalysis);
    _updateAdaptiveThresholds(gestureAnalysis, interactionAnalysis);
    
    return {
      'recognizedGesture': gestureAnalysis['gesture'],
      'gestureConfidence': gestureAnalysis['confidence'],
      'interactionType': interactionAnalysis['type'],
      'predictedIntent': interactionAnalysis['intent'],
      'suggestedResponse': _generateResponse(gestureAnalysis, interactionAnalysis),
    };
  }
  
  List<double> _prepareGestureInput(List<Vector3> handPositions, List<double> fingerAngles) {
    final input = List<double>.filled(63, 0); // 21 joints x 3 coordinates
    
    // Convert hand positions to normalized coordinates
    for (var i = 0; i < handPositions.length; i++) {
      final pos = handPositions[i];
      input[i * 3] = pos.x;
      input[i * 3 + 1] = pos.y;
      input[i * 3 + 2] = pos.z;
    }
    
    // Add finger angles
    for (var i = 0; i < fingerAngles.length; i++) {
      input[63 + i] = fingerAngles[i];
    }
    
    return input;
  }
  
  List<double> _prepareInteractionInput(
    List<Vector3> handPositions,
    Vector3 devicePosition,
    Matrix4 deviceOrientation,
  ) {
    final input = List<double>.filled(90, 0); // Adjust size based on model
    
    // Add hand movement trajectory
    for (var i = 0; i < handPositions.length; i++) {
      final pos = handPositions[i];
      input[i * 3] = pos.x;
      input[i * 3 + 1] = pos.y;
      input[i * 3 + 2] = pos.z;
    }
    
    // Add device context
    input[63] = devicePosition.x;
    input[64] = devicePosition.y;
    input[65] = devicePosition.z;
    
    // Add orientation quaternion
    final quat = Quaternion.fromRotation(deviceOrientation.getRotation());
    input[66] = quat.x;
    input[67] = quat.y;
    input[68] = quat.z;
    input[69] = quat.w;
    
    return input;
  }
  
  Map<String, dynamic> _analyzeGesture(List<double> output) {
    final gestureClasses = [
      'point', 'grab', 'pinch', 'swipe', 'rotate',
      'wave', 'tap', 'hold', 'release', 'custom',
    ];
    
    // Find most likely gesture
    var maxIndex = 0;
    var maxConfidence = output[0];
    
    for (var i = 1; i < output.length; i++) {
      if (output[i] > maxConfidence) {
        maxConfidence = output[i];
        maxIndex = i;
      }
    }
    
    final gesture = maxIndex < gestureClasses.length
        ? gestureClasses[maxIndex]
        : 'unknown';
    
    return {
      'gesture': gesture,
      'confidence': maxConfidence,
      'variations': _identifyGestureVariations(output, gestureClasses),
    };
  }
  
  List<Map<String, dynamic>> _identifyGestureVariations(
    List<double> output,
    List<String> gestureClasses,
  ) {
    final variations = <Map<String, dynamic>>[];
    
    // Look for gesture combinations and variations
    for (var i = 0; i < gestureClasses.length; i++) {
      if (output[i] > _adaptiveThresholds['gestureConfidence']!) {
        variations.add({
          'gesture': gestureClasses[i],
          'confidence': output[i],
          'isVariation': output[i] < output.reduce((a, b) => a > b ? a : b),
        });
      }
    }
    
    return variations;
  }
  
  Map<String, dynamic> _analyzeInteraction(List<double> output) {
    final interactionTypes = [
      'select', 'manipulate', 'navigate', 'draw', 'command',
      'zoom', 'scroll', 'rotate', 'system', 'custom',
    ];
    
    // Analyze interaction pattern
    var maxIndex = 0;
    var maxConfidence = output[0];
    
    for (var i = 1; i < output.length; i++) {
      if (output[i] > maxConfidence) {
        maxConfidence = output[i];
        maxIndex = i;
      }
    }
    
    final interactionType = maxIndex < interactionTypes.length
        ? interactionTypes[maxIndex]
        : 'unknown';
    
    return {
      'type': interactionType,
      'confidence': maxConfidence,
      'intent': _inferInteractionIntent(output),
      'context': _analyzeInteractionContext(output),
    };
  }
  
  Map<String, dynamic> _inferInteractionIntent(List<double> output) {
    final intentCategories = [
      'navigation', 'manipulation', 'creation', 'deletion',
      'modification', 'selection', 'system', 'custom',
    ];
    
    // Calculate intent probabilities
    final intentProbs = <String, double>{};
    var totalProb = 0.0;
    
    for (var i = 0; i < intentCategories.length; i++) {
      final prob = output[20 + i]; // Intent probabilities start at index 20
      intentProbs[intentCategories[i]] = prob;
      totalProb += prob;
    }
    
    // Normalize probabilities
    intentProbs.updateAll((key, value) => value / totalProb);
    
    // Find primary and secondary intents
    var sortedIntents = intentProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return {
      'primary': sortedIntents[0].key,
      'secondary': sortedIntents[1].key,
      'confidence': sortedIntents[0].value,
      'distribution': intentProbs,
    };
  }
  
  Map<String, dynamic> _analyzeInteractionContext(List<double> output) {
    return {
      'spatialCoherence': output[28], // Spatial consistency score
      'temporalStability': output[29], // Temporal stability score
      'environmentalContext': {
        'indoors': output[30] > 0.5,
        'crowded': output[31] > 0.5,
        'moving': output[32] > 0.5,
        'lightingQuality': output[33],
      },
    };
  }
  
  void _updateGesturePatterns(Map<String, dynamic> gestureAnalysis) {
    final gesture = gestureAnalysis['gesture'] as String;
    final confidence = gestureAnalysis['confidence'] as double;
    
    if (confidence > _adaptiveThresholds['gestureConfidence']!) {
      // Update gesture pattern history
      _gesturePatterns[gesture] = _gesturePatterns[gesture] ?? [];
      _gesturePatterns[gesture]!.add(confidence);
      
      // Keep only recent history
      if (_gesturePatterns[gesture]!.length > 100) {
        _gesturePatterns[gesture]!.removeAt(0);
      }
    }
  }
  
  void _updateAdaptiveThresholds(
    Map<String, dynamic> gestureAnalysis,
    Map<String, dynamic> interactionAnalysis,
  ) {
    // Update confidence threshold based on recent performance
    final recentConfidence = gestureAnalysis['confidence'] as double;
    final spatialCoherence = interactionAnalysis['context']['spatialCoherence'] as double;
    
    _adaptiveThresholds['gestureConfidence'] = _adaptiveThresholds['gestureConfidence']! * 0.95 +
        recentConfidence * 0.05;
    
    _adaptiveThresholds['spatialCoherence'] = _adaptiveThresholds['spatialCoherence']! * 0.95 +
        spatialCoherence * 0.05;
  }
  
  Map<String, dynamic> _generateResponse(
    Map<String, dynamic> gestureAnalysis,
    Map<String, dynamic> interactionAnalysis,
  ) {
    // Generate appropriate system response
    final response = <String, dynamic>{
      'action': _determineResponseAction(
        gestureAnalysis['gesture'],
        interactionAnalysis['type'],
      ),
      'parameters': _generateResponseParameters(
        gestureAnalysis,
        interactionAnalysis,
      ),
      'feedback': _generateFeedbackSuggestion(
        gestureAnalysis['confidence'],
        interactionAnalysis['context'],
      ),
    };
    
    return response;
  }
  
  String _determineResponseAction(String gesture, String interactionType) {
    // Map gesture and interaction type to system action
    final actionMap = {
      'point_select': 'highlight',
      'grab_manipulate': 'move',
      'pinch_zoom': 'scale',
      'swipe_navigate': 'scroll',
      'rotate_rotate': 'rotate',
      'tap_select': 'select',
      'hold_command': 'menu',
    };
    
    return actionMap['${gesture}_$interactionType'] ?? 'default';
  }
  
  Map<String, dynamic> _generateResponseParameters(
    Map<String, dynamic> gestureAnalysis,
    Map<String, dynamic> interactionAnalysis,
  ) {
    return {
      'intensity': gestureAnalysis['confidence'],
      'duration': _calculateResponseDuration(
        gestureAnalysis['gesture'],
        interactionAnalysis['type'],
      ),
      'style': _determineResponseStyle(
        gestureAnalysis['variations'],
        interactionAnalysis['context'],
      ),
    };
  }
  
  double _calculateResponseDuration(String gesture, String interactionType) {
    // Calculate appropriate response duration based on gesture and interaction
    final baseDuration = {
      'tap': 0.1,
      'hold': 0.5,
      'swipe': 0.3,
      'pinch': 0.4,
      'rotate': 0.6,
    }[gesture] ?? 0.3;
    
    final typeMultiplier = {
      'select': 1.0,
      'manipulate': 1.2,
      'navigate': 1.5,
      'command': 0.8,
    }[interactionType] ?? 1.0;
    
    return baseDuration * typeMultiplier;
  }
  
  String _determineResponseStyle(
    List<Map<String, dynamic>> variations,
    Map<String, dynamic> context,
  ) {
    // Determine appropriate feedback style based on context
    if (context['environmentalContext']['crowded']) {
      return 'subtle';
    } else if (context['spatialCoherence'] < 0.5) {
      return 'emphasized';
    } else if (variations.length > 1) {
      return 'adaptive';
    }
    return 'standard';
  }
  
  Map<String, dynamic> _generateFeedbackSuggestion(
    double confidence,
    Map<String, dynamic> context,
  ) {
    return {
      'type': confidence < 0.7 ? 'visual' : 'minimal',
      'intensity': _calculateFeedbackIntensity(confidence, context),
      'duration': confidence < 0.5 ? 'extended' : 'standard',
      'style': context['environmentalContext']['lightingQuality'] < 0.5
          ? 'high-contrast'
          : 'standard',
    };
  }
  
  double _calculateFeedbackIntensity(
    double confidence,
    Map<String, dynamic> context,
  ) {
    // Calculate feedback intensity based on confidence and context
    var intensity = 1.0 - confidence; // Base intensity on inverse of confidence
    
    // Adjust for environmental factors
    if (context['environmentalContext']['crowded']) intensity *= 0.7;
    if (context['environmentalContext']['moving']) intensity *= 1.3;
    if (context['environmentalContext']['lightingQuality'] < 0.5) intensity *= 1.2;
    
    return intensity.clamp(0.1, 1.0); // Ensure reasonable bounds
  }
  
  void dispose() {
    if (_isInitialized) {
      _gestureModel.close();
      _interactionModel.close();
      _gesturePatterns.clear();
      _adaptiveThresholds.clear();
    }
  }
}