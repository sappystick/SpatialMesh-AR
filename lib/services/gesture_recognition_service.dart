import 'dart:async';
import 'package:vector_math/vector_math_64.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/app_config.dart';

class GestureRecognitionService {
  late final HandTracker _handTracker;
  late final GestureClassifier _gestureClassifier;
  late final GestureStateManager _stateManager;
  late final InteractionPredictor _predictor;

  final _gestureController = StreamController<RecognizedGesture>.broadcast();
  Stream<RecognizedGesture> get gestureStream => _gestureController.stream;

  bool _isInitialized = false;
  static const int _minConfidence = 0.85;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _handTracker = HandTracker(
      modelPath: 'assets/models/hand_landmark.tflite',
      numThreads: 2,
      useGPU: true,
    );

    _gestureClassifier = GestureClassifier(
      modelPath: 'assets/models/gesture_classifier.tflite',
      labelsPath: 'assets/models/gesture_labels.txt',
    );

    _stateManager = GestureStateManager(
      stabilityThreshold: Duration(milliseconds: 100),
      gestureTimeout: Duration(seconds: 2),
    );

    _predictor = InteractionPredictor(
      predictionWindow: Duration(milliseconds: 500),
      smoothingFactor: 0.8,
    );

    await _handTracker.initialize();
    await _gestureClassifier.initialize();
    
    _isInitialized = true;
  }

  Future<void> processFrame(ARCameraFrame frame) async {
    if (!_isInitialized) return;

    // Detect hand landmarks
    final hands = await _handTracker.detectHands(frame);
    
    for (final hand in hands) {
      // Skip low confidence detections
      if (hand.confidence < _minConfidence) continue;

      // Classify gesture
      final gesture = await _gestureClassifier.classifyGesture(hand);
      if (gesture == null) continue;

      // Update gesture state
      final stateUpdated = _stateManager.updateGestureState(gesture);
      if (!stateUpdated) continue;

      // Predict interaction
      final prediction = _predictor.predictInteraction(gesture);
      
      // Emit recognized gesture
      _gestureController.add(RecognizedGesture(
        type: gesture.type,
        hand: hand,
        confidence: gesture.confidence,
        prediction: prediction,
        timestamp: DateTime.now(),
      ));
    }
  }

  void dispose() {
    _gestureController.close();
    _handTracker.dispose();
    _gestureClassifier.dispose();
  }
}

class HandTracker {
  final String modelPath;
  final int numThreads;
  final bool useGPU;

  late final Interpreter _interpreter;
  late final InterpreterOptions _options;

  HandTracker({
    required this.modelPath,
    required this.numThreads,
    required this.useGPU,
  });

  Future<void> initialize() async {
    _options = InterpreterOptions()
      ..threads = numThreads
      ..useNnApiForAndroid = useGPU;

    _interpreter = await Interpreter.fromAsset(
      modelPath,
      options: _options,
    );
  }

  Future<List<Hand>> detectHands(ARCameraFrame frame) async {
    final hands = <Hand>[];
    
    try {
      // Process frame with ML model
      final inputArray = _prepareInput(frame);
      final outputBuffer = _createOutputBuffer();
      
      await _interpreter.run(inputArray, outputBuffer);
      
      // Parse results
      final landmarks = _processOutput(outputBuffer);
      
      // Create Hand objects
      for (final landmark in landmarks) {
        hands.add(Hand(
          landmarks: landmark,
          confidence: _calculateConfidence(landmark),
          isLeftHand: _determineHandedness(landmark),
        ));
      }
    } catch (e) {
      print('Hand detection error: $e');
    }
    
    return hands;
  }

  List<double> _prepareInput(ARCameraFrame frame) {
    // Convert frame to float32 array
    final inputArray = List<double>.filled(frame.width * frame.height * 3, 0);
    var idx = 0;
    
    // Normalize pixel values to [-1, 1]
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final pixel = frame.pixels[y * frame.width + x];
        inputArray[idx++] = (((pixel >> 16) & 0xFF) / 127.5) - 1.0; // R
        inputArray[idx++] = (((pixel >> 8) & 0xFF) / 127.5) - 1.0;  // G
        inputArray[idx++] = ((pixel & 0xFF) / 127.5) - 1.0;         // B
      }
    }
    
    return inputArray;
  }

  Map<String, dynamic> _createOutputBuffer() {
    return {
      'hand_landmarks': List<double>.filled(21 * 3, 0), // 21 landmarks x 3 coordinates
      'hand_presence': [0.0], // Confidence score
      'handedness': [0.0], // Left vs right hand probability
      'gesture_class': List<double>.filled(15, 0), // Support for 15 gesture classes
    };
  }

  List<List<Vector3>> _processOutput(Map<String, dynamic> output) {
    final landmarks = <List<Vector3>>[];
    final landmarkData = output['hand_landmarks'] as List<double>;
    
    // Process each hand detection
    for (var i = 0; i < landmarkData.length; i += 63) { // 21 landmarks * 3 coordinates
      final handLandmarks = <Vector3>[];
      
      // Convert each landmark to Vector3
      for (var j = 0; j < 21; j++) {
        final x = landmarkData[i + j * 3];
        final y = landmarkData[i + j * 3 + 1];
        final z = landmarkData[i + j * 3 + 2];
        
        handLandmarks.add(Vector3(x, y, z));
      }
      
      landmarks.add(handLandmarks);
    }
    
    return landmarks;
  }

  double _calculateConfidence(List<Vector3> landmarks) {
    // Calculate average distance between consecutive landmarks
    var totalDistance = 0.0;
    var validPairs = 0;
    
    for (var i = 0; i < landmarks.length - 1; i++) {
      final dist = landmarks[i].distanceTo(landmarks[i + 1]);
      if (dist > 0 && dist < 0.5) { // Filter out unrealistic distances
        totalDistance += dist;
        validPairs++;
      }
    }
    
    if (validPairs == 0) return 0.0;
    
    // Calculate stability score
    final avgDistance = totalDistance / validPairs;
    final stabilityScore = 1.0 - (avgDistance / 0.5); // Normalize to [0, 1]
    
    // Calculate visibility score
    var visibleLandmarks = 0;
    for (final landmark in landmarks) {
      if (landmark.z > -1.0) { // Consider landmark visible if not too far behind
        visibleLandmarks++;
      }
    }
    final visibilityScore = visibleLandmarks / landmarks.length;
    
    // Combine scores with weights
    return (stabilityScore * 0.6) + (visibilityScore * 0.4);
  }

  bool _determineHandedness(List<Vector3> landmarks) {
    // Calculate the cross product of vectors from wrist to thumb and wrist to pinky
    final wrist = landmarks[0];
    final thumb = landmarks[4];
    final pinky = landmarks[20];
    
    final wristToThumb = thumb - wrist;
    final wristToPinky = pinky - wrist;
    
    // Calculate cross product
    final cross = wristToThumb.cross(wristToPinky);
    
    // If z component is positive, it's a left hand; if negative, right hand
    return cross.z > 0;
  }

  void dispose() {
    _interpreter.close();
  }
}

class GestureClassifier {
  final String modelPath;
  final String labelsPath;

  late final Interpreter _interpreter;
  late final List<String> _labels;
  
  GestureClassifier({
    required this.modelPath,
    required this.labelsPath,
  });

  Future<void> initialize() async {
    _interpreter = await Interpreter.fromAsset(modelPath);
    _labels = await _loadLabels();
  }

  Future<List<String>> _loadLabels() async {
    // Load gesture labels from asset file
    return [];
  }

  Future<Gesture?> classifyGesture(Hand hand) async {
    try {
      // Prepare input features
      final features = _extractFeatures(hand);
      
      // Run classification
      final outputBuffer = Map<int, dynamic>();
      await _interpreter.run(features, outputBuffer);
      
      // Process results
      final results = _processClassification(outputBuffer);
      
      // Get top prediction
      if (results.isEmpty) return null;
      
      final topResult = results[0];
      return Gesture(
        type: _labels[topResult.index],
        confidence: topResult.score,
        hand: hand,
      );
    } catch (e) {
      print('Gesture classification error: $e');
      return null;
    }
  }

  List<double> _extractFeatures(Hand hand) {
    final features = <double>[];
    
    // Calculate relative positions to wrist
    final wrist = hand.landmarks[0];
    for (var i = 1; i < hand.landmarks.length; i++) {
      final landmark = hand.landmarks[i];
      final relative = landmark - wrist;
      features.addAll([relative.x, relative.y, relative.z]);
    }
    
    // Calculate angles between finger segments
    features.addAll(_calculateFingerAngles(hand.landmarks));
    
    // Calculate distances between key points
    features.addAll(_calculateKeyDistances(hand.landmarks));
    
    // Add dynamic features
    features.addAll(_calculateDynamicFeatures(hand.landmarks));
    
    return features;
  }

  List<double> _calculateFingerAngles(List<Vector3> landmarks) {
    final angles = <double>[];
    
    // Define finger joint indices
    final fingerJoints = [
      [1, 2, 3, 4],     // Thumb
      [5, 6, 7, 8],     // Index
      [9, 10, 11, 12],  // Middle
      [13, 14, 15, 16], // Ring
      [17, 18, 19, 20], // Pinky
    ];
    
    for (final finger in fingerJoints) {
      for (var i = 0; i < finger.length - 2; i++) {
        final p1 = landmarks[finger[i]];
        final p2 = landmarks[finger[i + 1]];
        final p3 = landmarks[finger[i + 2]];
        
        final v1 = (p2 - p1).normalized();
        final v2 = (p3 - p2).normalized();
        
        // Calculate angle between vectors
        final angle = acos(v1.dot(v2));
        angles.add(angle);
      }
    }
    
    return angles;
  }

  List<double> _calculateKeyDistances(List<Vector3> landmarks) {
    final distances = <double>[];
    
    // Distance between fingertips
    final fingertips = [4, 8, 12, 16, 20];
    for (var i = 0; i < fingertips.length; i++) {
      for (var j = i + 1; j < fingertips.length; j++) {
        final distance = landmarks[fingertips[i]]
            .distanceTo(landmarks[fingertips[j]]);
        distances.add(distance);
      }
    }
    
    // Distance from wrist to fingertips
    final wrist = landmarks[0];
    for (final tip in fingertips) {
      final distance = wrist.distanceTo(landmarks[tip]);
      distances.add(distance);
    }
    
    return distances;
  }

  List<double> _calculateDynamicFeatures(List<Vector3> landmarks) {
    final features = <double>[];
    
    // Calculate palm orientation
    final palmNormal = _calculatePalmNormal(landmarks);
    features.addAll([palmNormal.x, palmNormal.y, palmNormal.z]);
    
    // Calculate hand spread
    final spread = _calculateHandSpread(landmarks);
    features.add(spread);
    
    // Calculate curvature
    final curvature = _calculateFingerCurvature(landmarks);
    features.addAll(curvature);
    
    return features;
  }

  Vector3 _calculatePalmNormal(List<Vector3> landmarks) {
    // Calculate palm normal using cross product of palm vectors
    final wrist = landmarks[0];
    final index = landmarks[5];
    final pinky = landmarks[17];
    
    final v1 = (index - wrist).normalized();
    final v2 = (pinky - wrist).normalized();
    
    return v1.cross(v2).normalized();
  }

  double _calculateHandSpread(List<Vector3> landmarks) {
    // Calculate average spread of fingers from palm center
    final palmCenter = _calculatePalmCenter(landmarks);
    final fingertips = [4, 8, 12, 16, 20];
    
    var totalSpread = 0.0;
    for (final tip in fingertips) {
      totalSpread += landmarks[tip].distanceTo(palmCenter);
    }
    
    return totalSpread / fingertips.length;
  }

  Vector3 _calculatePalmCenter(List<Vector3> landmarks) {
    // Calculate center of palm using wrist and finger bases
    final points = [0, 5, 9, 13, 17].map((i) => landmarks[i]).toList();
    
    var center = Vector3.zero();
    for (final point in points) {
      center += point;
    }
    
    return center.scaled(1.0 / points.length);
  }

  List<double> _calculateFingerCurvature(List<Vector3> landmarks) {
    final curvatures = <double>[];
    
    // Define finger segments
    final fingers = [
      [1, 2, 3, 4],     // Thumb
      [5, 6, 7, 8],     // Index
      [9, 10, 11, 12],  // Middle
      [13, 14, 15, 16], // Ring
      [17, 18, 19, 20], // Pinky
    ];
    
    for (final finger in fingers) {
      var totalCurvature = 0.0;
      
      for (var i = 0; i < finger.length - 2; i++) {
        final p1 = landmarks[finger[i]];
        final p2 = landmarks[finger[i + 1]];
        final p3 = landmarks[finger[i + 2]];
        
        // Calculate curvature using angle between segments
        final v1 = (p2 - p1).normalized();
        final v2 = (p3 - p2).normalized();
        totalCurvature += acos(v1.dot(v2));
      }
      
      curvatures.add(totalCurvature);
    }
    
    return curvatures;
  }

  List<PredictionResult> _processClassification(Map<int, dynamic> output) {
    final results = <PredictionResult>[];
    final scores = output[0] as List<double>;
    
    // Convert raw scores to probabilities using softmax
    final probabilities = _computeSoftmax(scores);
    
    // Create prediction results
    for (var i = 0; i < probabilities.length; i++) {
      results.add(PredictionResult(i, probabilities[i]));
    }
    
    // Sort by confidence
    results.sort((a, b) => b.score.compareTo(a.score));
    
    return results;
  }

  List<double> _computeSoftmax(List<double> scores) {
    // Compute softmax probabilities
    final maxScore = scores.reduce(max);
    final exps = scores.map((s) => exp(s - maxScore)).toList();
    final sumExps = exps.reduce((a, b) => a + b);
    
    return exps.map((e) => e / sumExps).toList();
  }

  void dispose() {
    _interpreter.close();
  }
}

class GestureStateManager {
  final Duration stabilityThreshold;
  final Duration gestureTimeout;
  
  Gesture? _currentGesture;
  DateTime? _gestureStartTime;
  
  GestureStateManager({
    required this.stabilityThreshold,
    required this.gestureTimeout,
  });

  bool updateGestureState(Gesture newGesture) {
    final now = DateTime.now();
    
    // Check for gesture timeout
    if (_gestureStartTime != null) {
      final elapsed = now.difference(_gestureStartTime!);
      if (elapsed > gestureTimeout) {
        _resetState();
      }
    }
    
    // New gesture detected
    if (_currentGesture == null) {
      _currentGesture = newGesture;
      _gestureStartTime = now;
      return true;
    }
    
    // Check if gesture is stable
    if (_currentGesture!.type == newGesture.type) {
      final elapsed = now.difference(_gestureStartTime!);
      if (elapsed >= stabilityThreshold) {
        return true;
      }
    } else {
      // Different gesture, reset state
      _currentGesture = newGesture;
      _gestureStartTime = now;
    }
    
    return false;
  }

  void _resetState() {
    _currentGesture = null;
    _gestureStartTime = null;
  }
}

class InteractionPredictor {
  final Duration predictionWindow;
  final double smoothingFactor;
  
  final List<GestureDataPoint> _history = [];
  
  InteractionPredictor({
    required this.predictionWindow,
    required this.smoothingFactor,
  });

  PredictedInteraction predictInteraction(Gesture gesture) {
    // Add to history
    _history.add(GestureDataPoint(
      gesture: gesture,
      timestamp: DateTime.now(),
    ));
    
    // Clean old history
    _cleanHistory();
    
    // Predict next state
    return _generatePrediction();
  }

  void _cleanHistory() {
    final cutoff = DateTime.now().subtract(predictionWindow);
    _history.removeWhere((point) => point.timestamp.isBefore(cutoff));
  }

  PredictedInteraction _generatePrediction() {
    if (_history.isEmpty) {
      return PredictedInteraction(
        confidence: 0.0,
        predictedDuration: Duration.zero,
      );
    }

    // Calculate gesture stability
    final stability = _calculateStability();
    
    // Predict duration
    final duration = _predictDuration();
    
    return PredictedInteraction(
      confidence: stability,
      predictedDuration: duration,
    );
  }

  double _calculateStability() {
    if (_history.length < 2) return 1.0;
    
    // Calculate variance in gesture positions
    var totalVariance = 0.0;
    for (var i = 1; i < _history.length; i++) {
      final prev = _history[i - 1].gesture;
      final curr = _history[i].gesture;
      
      totalVariance += _calculateVariance(prev, curr);
    }
    
    return 1.0 / (1.0 + totalVariance);
  }

  double _calculateVariance(Gesture g1, Gesture g2) {
    // Calculate position variance between gestures
    return 0.0;
  }

  Duration _predictDuration() {
    if (_history.length < 2) return Duration.zero;
    
    // Calculate average gesture duration
    final durations = <Duration>[];
    for (var i = 1; i < _history.length; i++) {
      durations.add(_history[i].timestamp.difference(_history[i - 1].timestamp));
    }
    
    final avg = durations.reduce((a, b) => a + b) ~/ durations.length;
    return Duration(milliseconds: avg.inMilliseconds);
  }
}

class Hand {
  final List<Vector3> landmarks;
  final double confidence;
  final bool isLeftHand;
  
  Hand({
    required this.landmarks,
    required this.confidence,
    required this.isLeftHand,
  });
}

class Gesture {
  final String type;
  final double confidence;
  final Hand hand;
  
  Gesture({
    required this.type,
    required this.confidence,
    required this.hand,
  });
}

class RecognizedGesture {
  final String type;
  final Hand hand;
  final double confidence;
  final PredictedInteraction prediction;
  final DateTime timestamp;
  
  RecognizedGesture({
    required this.type,
    required this.hand,
    required this.confidence,
    required this.prediction,
    required this.timestamp,
  });
}

class PredictedInteraction {
  final double confidence;
  final Duration predictedDuration;
  
  PredictedInteraction({
    required this.confidence,
    required this.predictedDuration,
  });
}

class GestureDataPoint {
  final Gesture gesture;
  final DateTime timestamp;
  
  GestureDataPoint({
    required this.gesture,
    required this.timestamp,
  });
}

class PredictionResult {
  final int index;
  final double score;
  
  PredictionResult(this.index, this.score);
}