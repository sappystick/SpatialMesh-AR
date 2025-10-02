import 'dart:async';
import 'package:vector_math/vector_math_64.dart';
import '../services/gesture_recognition_service.dart';
import '../services/voice_recognition_service.dart';

class NaturalInteractionCoordinator {
  late final GestureRecognitionService _gestureService;
  late final VoiceRecognitionService _voiceService;
  late final MultimodalFusionEngine _fusionEngine;
  late final InteractionContextManager _contextManager;
  late final IntentResolver _intentResolver;
  
  final _interactionController = StreamController<MultimodalInteraction>.broadcast();
  Stream<MultimodalInteraction> get interactionStream => _interactionController.stream;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize services
    _gestureService = GestureRecognitionService();
    _voiceService = VoiceRecognitionService();
    await _gestureService.initialize();
    await _voiceService.initialize();

    // Initialize components
    _fusionEngine = MultimodalFusionEngine(
      temporalWindow: Duration(milliseconds: 500),
      spatialThreshold: 0.5,
    );

    _contextManager = InteractionContextManager();
    
    _intentResolver = IntentResolver();

    // Set up listeners
    _setupListeners();
    
    _isInitialized = true;
  }

  void _setupListeners() {
    // Listen for gesture events
    _gestureService.gestureStream.listen((gesture) {
      _handleGestureInput(gesture);
    });

    // Listen for voice commands
    _voiceService.voiceStream.listen((command) {
      _handleVoiceInput(command);
    });
  }

  Future<void> _handleGestureInput(RecognizedGesture gesture) async {
    try {
      // Update context
      _contextManager.updateGestureContext(gesture);
      
      // Check for multimodal fusion
      final fusedInteraction = await _fusionEngine.processGesture(
        gesture,
        _contextManager.currentContext,
      );
      
      if (fusedInteraction != null) {
        // Resolve intent
        final resolvedIntent = await _intentResolver.resolveMultimodalIntent(
          fusedInteraction,
          _contextManager.currentContext,
        );
        
        // Emit interaction
        _emitInteraction(resolvedIntent);
      }
    } catch (e) {
      print('Error handling gesture input: $e');
    }
  }

  Future<void> _handleVoiceInput(RecognizedVoiceCommand command) async {
    try {
      // Update context
      _contextManager.updateVoiceContext(command);
      
      // Check for multimodal fusion
      final fusedInteraction = await _fusionEngine.processVoiceCommand(
        command,
        _contextManager.currentContext,
      );
      
      if (fusedInteraction != null) {
        // Resolve intent
        final resolvedIntent = await _intentResolver.resolveMultimodalIntent(
          fusedInteraction,
          _contextManager.currentContext,
        );
        
        // Emit interaction
        _emitInteraction(resolvedIntent);
      }
    } catch (e) {
      print('Error handling voice input: $e');
    }
  }

  void _emitInteraction(ResolvedInteraction interaction) {
    _interactionController.add(MultimodalInteraction(
      type: interaction.type,
      gesture: interaction.gesture,
      voice: interaction.voice,
      intent: interaction.intent,
      confidence: interaction.confidence,
      context: _contextManager.currentContext,
      timestamp: DateTime.now(),
    ));
  }

  void dispose() {
    _interactionController.close();
    _gestureService.dispose();
    _voiceService.dispose();
  }
}

class MultimodalFusionEngine {
  final Duration temporalWindow;
  final double spatialThreshold;
  
  final List<InputEvent> _recentEvents = [];

  MultimodalFusionEngine({
    required this.temporalWindow,
    required this.spatialThreshold,
  });

  Future<FusedInteraction?> processGesture(
    RecognizedGesture gesture,
    InteractionContext context,
  ) async {
    // Add to recent events
    _recentEvents.add(InputEvent(
      type: InputType.gesture,
      gesture: gesture,
      timestamp: DateTime.now(),
    ));
    
    // Clean old events
    _cleanEvents();
    
    // Try to fuse with recent voice commands
    return _attemptFusion();
  }

  Future<FusedInteraction?> processVoiceCommand(
    RecognizedVoiceCommand command,
    InteractionContext context,
  ) async {
    // Add to recent events
    _recentEvents.add(InputEvent(
      type: InputType.voice,
      voice: command,
      timestamp: DateTime.now(),
    ));
    
    // Clean old events
    _cleanEvents();
    
    // Try to fuse with recent gestures
    return _attemptFusion();
  }

  void _cleanEvents() {
    final cutoff = DateTime.now().subtract(temporalWindow);
    _recentEvents.removeWhere((event) => event.timestamp.isBefore(cutoff));
  }

  FusedInteraction? _attemptFusion() {
    // Look for complementary gesture and voice inputs
    final gestures = _recentEvents
        .where((e) => e.type == InputType.gesture)
        .map((e) => e.gesture!)
        .toList();
    
    final commands = _recentEvents
        .where((e) => e.type == InputType.voice)
        .map((e) => e.voice!)
        .toList();
    
    if (gestures.isEmpty || commands.isEmpty) return null;
    
    // Find best matching pair
    var bestMatch = _findBestMatch(gestures, commands);
    if (bestMatch == null) return null;
    
    return FusedInteraction(
      gesture: bestMatch.gesture,
      voice: bestMatch.voice,
      confidence: _calculateFusionConfidence(bestMatch),
    );
  }

  ModalityMatch? _findBestMatch(
    List<RecognizedGesture> gestures,
    List<RecognizedVoiceCommand> commands,
  ) {
    ModalityMatch? bestMatch;
    double bestScore = 0;
    
    for (final gesture in gestures) {
      for (final command in commands) {
        final score = _calculateMatchScore(gesture, command);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = ModalityMatch(gesture, command);
        }
      }
    }
    
    return bestMatch;
  }

  double _calculateMatchScore(
    RecognizedGesture gesture,
    RecognizedVoiceCommand command,
  ) {
    // Calculate temporal alignment
    final timeDiff = gesture.timestamp.difference(command.timestamp).abs();
    final temporalScore = 1.0 - (timeDiff.inMilliseconds / temporalWindow.inMilliseconds);
    
    // Calculate spatial relevance
    final spatialScore = _calculateSpatialRelevance(gesture, command);
    
    // Calculate semantic compatibility
    final semanticScore = _calculateSemanticCompatibility(gesture, command);
    
    // Weighted combination
    return (temporalScore * 0.4) + (spatialScore * 0.3) + (semanticScore * 0.3);
  }

  double _calculateSpatialRelevance(
    RecognizedGesture gesture,
    RecognizedVoiceCommand command,
  ) {
    // Calculate how well the gesture location matches the command context
    return 1.0; // Placeholder implementation
  }

  double _calculateSemanticCompatibility(
    RecognizedGesture gesture,
    RecognizedVoiceCommand command,
  ) {
    // Calculate how well the gesture type matches the command intent
    return 1.0; // Placeholder implementation
  }

  double _calculateFusionConfidence(ModalityMatch match) {
    return (match.gesture.confidence + match.voice.confidence) / 2.0;
  }
}

class InteractionContextManager {
  InteractionContext _currentContext = InteractionContext();
  final List<InteractionContext> _contextHistory = [];
  static const _maxHistorySize = 10;

  InteractionContext get currentContext => _currentContext;

  void updateGestureContext(RecognizedGesture gesture) {
    _saveCurrentContext();
    
    _currentContext = _currentContext.copyWith(
      lastGesture: gesture,
      gestureLocation: gesture.hand.landmarks[0], // Use palm position
      timestamp: DateTime.now(),
    );
  }

  void updateVoiceContext(RecognizedVoiceCommand command) {
    _saveCurrentContext();
    
    _currentContext = _currentContext.copyWith(
      lastVoiceCommand: command,
      timestamp: DateTime.now(),
    );
  }

  void _saveCurrentContext() {
    _contextHistory.add(_currentContext);
    if (_contextHistory.length > _maxHistorySize) {
      _contextHistory.removeAt(0);
    }
  }

  InteractionContext? getPreviousContext() {
    return _contextHistory.isNotEmpty ? _contextHistory.last : null;
  }

  void clearContext() {
    _currentContext = InteractionContext();
    _contextHistory.clear();
  }
}

class IntentResolver {
  Future<ResolvedInteraction> resolveMultimodalIntent(
    FusedInteraction interaction,
    InteractionContext context,
  ) async {
    // Determine interaction type
    final type = _determineInteractionType(interaction);
    
    // Calculate confidence
    final confidence = _calculateConfidence(interaction);
    
    // Resolve intent parameters
    final intent = await _resolveIntent(interaction, type);
    
    return ResolvedInteraction(
      type: type,
      gesture: interaction.gesture,
      voice: interaction.voice,
      intent: intent,
      confidence: confidence,
    );
  }

  InteractionType _determineInteractionType(FusedInteraction interaction) {
    final gesture = interaction.gesture;
    final voice = interaction.voice;
    
    // Determine type based on gesture and voice combination
    if (voice.type == VoiceCommandType.creation && 
        gesture.type == 'pointing') {
      return InteractionType.create;
    }
    
    if (voice.type == VoiceCommandType.manipulation && 
        gesture.type == 'grab') {
      return InteractionType.manipulate;
    }
    
    if (voice.type == VoiceCommandType.navigation && 
        gesture.type == 'pointing') {
      return InteractionType.navigate;
    }
    
    return InteractionType.unknown;
  }

  double _calculateConfidence(FusedInteraction interaction) {
    return (interaction.confidence * 0.6) + 
           (interaction.gesture.confidence * 0.2) + 
           (interaction.voice.confidence * 0.2);
  }

  Future<Map<String, dynamic>> _resolveIntent(
    FusedInteraction interaction,
    InteractionType type,
  ) async {
    final intent = <String, dynamic>{};
    
    // Combine parameters from both modalities
    intent.addAll(interaction.voice.parameters);
    
    // Add gesture-specific parameters
    switch (type) {
      case InteractionType.create:
        intent['location'] = interaction.gesture.hand.landmarks[0];
        break;
      
      case InteractionType.manipulate:
        intent['grabPosition'] = interaction.gesture.hand.landmarks[0];
        break;
      
      case InteractionType.navigate:
        intent['direction'] = interaction.gesture.hand.landmarks[0];
        break;
      
      default:
        break;
    }
    
    return intent;
  }
}

class InteractionContext {
  final RecognizedGesture? lastGesture;
  final RecognizedVoiceCommand? lastVoiceCommand;
  final Vector3? gestureLocation;
  final DateTime? timestamp;

  InteractionContext({
    this.lastGesture,
    this.lastVoiceCommand,
    this.gestureLocation,
    this.timestamp,
  });

  InteractionContext copyWith({
    RecognizedGesture? lastGesture,
    RecognizedVoiceCommand? lastVoiceCommand,
    Vector3? gestureLocation,
    DateTime? timestamp,
  }) {
    return InteractionContext(
      lastGesture: lastGesture ?? this.lastGesture,
      lastVoiceCommand: lastVoiceCommand ?? this.lastVoiceCommand,
      gestureLocation: gestureLocation ?? this.gestureLocation,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class InputEvent {
  final InputType type;
  final RecognizedGesture? gesture;
  final RecognizedVoiceCommand? voice;
  final DateTime timestamp;

  InputEvent({
    required this.type,
    this.gesture,
    this.voice,
    required this.timestamp,
  });
}

class FusedInteraction {
  final RecognizedGesture gesture;
  final RecognizedVoiceCommand voice;
  final double confidence;

  FusedInteraction({
    required this.gesture,
    required this.voice,
    required this.confidence,
  });
}

class MultimodalInteraction {
  final InteractionType type;
  final RecognizedGesture gesture;
  final RecognizedVoiceCommand voice;
  final Map<String, dynamic> intent;
  final double confidence;
  final InteractionContext context;
  final DateTime timestamp;

  MultimodalInteraction({
    required this.type,
    required this.gesture,
    required this.voice,
    required this.intent,
    required this.confidence,
    required this.context,
    required this.timestamp,
  });
}

class ResolvedInteraction {
  final InteractionType type;
  final RecognizedGesture gesture;
  final RecognizedVoiceCommand voice;
  final Map<String, dynamic> intent;
  final double confidence;

  ResolvedInteraction({
    required this.type,
    required this.gesture,
    required this.voice,
    required this.intent,
    required this.confidence,
  });
}

class ModalityMatch {
  final RecognizedGesture gesture;
  final RecognizedVoiceCommand voice;

  ModalityMatch(this.gesture, this.voice);
}

enum InputType {
  gesture,
  voice,
}

enum InteractionType {
  create,
  manipulate,
  navigate,
  query,
  unknown,
}