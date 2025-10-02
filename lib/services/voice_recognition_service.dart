import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dialogflow_grpc/dialogflow_grpc.dart';
import 'package:dialogflow_grpc/generated/google/cloud/dialogflow/v2beta1/session.pb.dart';

class VoiceRecognitionService {
  late final SpeechToText _speechToText;
  late final FlutterTts _tts;
  late final DialogflowGrpcV2Beta1 _dialogflow;
  late final VoiceCommandProcessor _commandProcessor;
  late final ContextManager _contextManager;
  late final NLPEngine _nlpEngine;
  
  final _voiceController = StreamController<RecognizedVoiceCommand>.broadcast();
  Stream<RecognizedVoiceCommand> get voiceStream => _voiceController.stream;

  bool _isListening = false;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _speechToText = SpeechToText();
    _tts = FlutterTts();
    _dialogflow = DialogflowGrpcV2Beta1.viaServiceAccount(
      'assets/service-account.json',
    );

    _commandProcessor = VoiceCommandProcessor();
    _contextManager = ContextManager();
    _nlpEngine = NLPEngine();

    await _initializeSpeechRecognition();
    await _initializeTextToSpeech();
    
    _isInitialized = true;
  }

  Future<void> _initializeSpeechRecognition() async {
    try {
      final available = await _speechToText.initialize(
        onError: _handleError,
        options: [
          SpeechConfigOption.enableDictation,
          SpeechConfigOption.enableContinuousListening,
        ],
      );

      if (!available) {
        throw Exception('Speech recognition not available');
      }

      // Configure recognition settings
      await _speechToText.setRecognitionParameters(
        enablePartialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      );
    } catch (e) {
      print('Speech recognition initialization error: $e');
      rethrow;
    }
  }

  Future<void> _initializeTextToSpeech() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.9);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      print('Text to speech initialization error: $e');
      rethrow;
    }
  }

  Future<void> startListening() async {
    if (!_isInitialized || _isListening) return;

    try {
      _isListening = true;
      
      await _speechToText.listen(
        onResult: _handleSpeechResult,
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: Duration(seconds: 3),
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isListening = false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _speechToText.stop();
      _isListening = false;
    } catch (e) {
      print('Error stopping speech recognition: $e');
    }
  }

  Future<void> _handleSpeechResult(SpeechRecognitionResult result) async {
    if (!result.finalResult) {
      // Process partial results if needed
      return;
    }

    try {
      // Process the recognized text
      final text = result.recognizedWords;
      
      // Extract intent using Dialogflow
      final intent = await _processWithDialogflow(text);
      
      // Process with NLP engine
      final nlpResult = await _nlpEngine.processText(text);
      
      // Create command context
      final context = _contextManager.getCurrentContext();
      
      // Process command
      final command = await _commandProcessor.processCommand(
        text: text,
        intent: intent,
        nlpResult: nlpResult,
        context: context,
      );
      
      if (command != null) {
        // Update context
        _contextManager.updateContext(command);
        
        // Emit command
        _voiceController.add(command);
        
        // Provide feedback
        await provideFeedback(command);
      }
    } catch (e) {
      print('Error processing speech result: $e');
    }
  }

  Future<DialogflowIntent?> _processWithDialogflow(String text) async {
    try {
      final queryInput = QueryInput()
        ..text = (TextInput()..text = text)
        ..languageCode = 'en-US';

      final response = await _dialogflow.detectIntent(queryInput);
      
      return DialogflowIntent(
        name: response.queryResult.intent.displayName,
        confidence: response.queryResult.intentDetectionConfidence,
        parameters: response.queryResult.parameters.toProto3Json(),
      );
    } catch (e) {
      print('Dialogflow processing error: $e');
      return null;
    }
  }

  Future<void> provideFeedback(RecognizedVoiceCommand command) async {
    try {
      final feedback = _generateFeedback(command);
      if (feedback != null) {
        await _tts.speak(feedback);
      }
    } catch (e) {
      print('Error providing feedback: $e');
    }
  }

  String? _generateFeedback(RecognizedVoiceCommand command) {
    // Generate appropriate feedback based on command type and context
    switch (command.type) {
      case VoiceCommandType.navigation:
        return 'Navigating to ${command.parameters['destination']}';
      case VoiceCommandType.creation:
        return 'Creating ${command.parameters['object']}';
      case VoiceCommandType.manipulation:
        return 'Adjusting ${command.parameters['property']}';
      case VoiceCommandType.query:
        return 'Looking up information about ${command.parameters['subject']}';
      default:
        return 'Command received';
    }
  }

  void _handleError(SpeechRecognitionError error) {
    print('Speech recognition error: ${error.errorMsg}');
    _isListening = false;
  }

  void dispose() {
    _voiceController.close();
    _speechToText.cancel();
    _tts.stop();
  }
}

class VoiceCommandProcessor {
  Future<RecognizedVoiceCommand?> processCommand({
    required String text,
    required DialogflowIntent? intent,
    required NLPResult nlpResult,
    required CommandContext context,
  }) async {
    if (intent == null) return null;

    try {
      // Determine command type
      final type = _determineCommandType(intent, nlpResult);
      
      // Extract parameters
      final parameters = _extractParameters(
        intent: intent,
        nlpResult: nlpResult,
        context: context,
      );
      
      // Validate command
      if (!_validateCommand(type, parameters)) {
        return null;
      }
      
      return RecognizedVoiceCommand(
        type: type,
        originalText: text,
        intent: intent,
        parameters: parameters,
        confidence: intent.confidence,
        context: context,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('Error processing command: $e');
      return null;
    }
  }

  VoiceCommandType _determineCommandType(
    DialogflowIntent intent,
    NLPResult nlpResult,
  ) {
    // Map intent to command type
    switch (intent.name) {
      case 'navigation.goto':
      case 'navigation.move':
        return VoiceCommandType.navigation;
      
      case 'object.create':
      case 'object.spawn':
        return VoiceCommandType.creation;
      
      case 'object.modify':
      case 'object.transform':
        return VoiceCommandType.manipulation;
      
      case 'system.query':
      case 'information.get':
        return VoiceCommandType.query;
      
      default:
        return VoiceCommandType.unknown;
    }
  }

  Map<String, dynamic> _extractParameters({
    required DialogflowIntent intent,
    required NLPResult nlpResult,
    required CommandContext context,
  }) {
    final params = <String, dynamic>{};
    
    // Merge parameters from different sources
    if (intent.parameters != null) {
      params.addAll(intent.parameters!);
    }
    
    // Add NLP extracted information
    params.addAll(nlpResult.extractedInfo);
    
    // Add contextual information
    if (context.relevantParams.isNotEmpty) {
      params.addAll(context.relevantParams);
    }
    
    return params;
  }

  bool _validateCommand(
    VoiceCommandType type,
    Map<String, dynamic> parameters,
  ) {
    // Validate required parameters for each command type
    switch (type) {
      case VoiceCommandType.navigation:
        return parameters.containsKey('destination');
      
      case VoiceCommandType.creation:
        return parameters.containsKey('object');
      
      case VoiceCommandType.manipulation:
        return parameters.containsKey('object') && 
               parameters.containsKey('property');
      
      case VoiceCommandType.query:
        return parameters.containsKey('subject');
      
      default:
        return false;
    }
  }
}

class ContextManager {
  CommandContext _currentContext = CommandContext();
  final _contextHistory = <CommandContext>[];
  static const _maxHistorySize = 10;

  CommandContext getCurrentContext() {
    return _currentContext;
  }

  void updateContext(RecognizedVoiceCommand command) {
    // Save current context to history
    _contextHistory.add(_currentContext);
    if (_contextHistory.length > _maxHistorySize) {
      _contextHistory.removeAt(0);
    }

    // Create new context
    _currentContext = CommandContext(
      previousCommand: command,
      relevantParams: _extractRelevantParams(command),
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> _extractRelevantParams(RecognizedVoiceCommand command) {
    final relevantParams = <String, dynamic>{};
    
    // Extract parameters that might be relevant for future commands
    switch (command.type) {
      case VoiceCommandType.creation:
        relevantParams['lastCreatedObject'] = command.parameters['object'];
        break;
      
      case VoiceCommandType.manipulation:
        relevantParams['lastModifiedObject'] = command.parameters['object'];
        relevantParams['lastModifiedProperty'] = command.parameters['property'];
        break;
      
      case VoiceCommandType.navigation:
        relevantParams['lastLocation'] = command.parameters['destination'];
        break;
      
      default:
        break;
    }
    
    return relevantParams;
  }

  CommandContext? getPreviousContext() {
    return _contextHistory.isNotEmpty ? _contextHistory.last : null;
  }

  void clearContext() {
    _currentContext = CommandContext();
    _contextHistory.clear();
  }
}

class NLPEngine {
  late final BertTokenizer _tokenizer;
  late final BertModel _model;
  late final IntentClassifier _intentClassifier;
  late final EntityRecognizer _entityRecognizer;
  late final SentimentAnalyzer _sentimentAnalyzer;
  late final Contextualizer _contextualizer;

  static const _vocabPath = 'assets/models/bert_vocab.txt';
  static const _modelPath = 'assets/models/bert_model.tflite';
  static const _maxSeqLength = 128;

  Future<void> initialize() async {
    // Initialize BERT tokenizer and model
    _tokenizer = await BertTokenizer.fromVocabFile(_vocabPath);
    _model = await BertModel.fromTflite(_modelPath);

    // Initialize NLP components
    _intentClassifier = IntentClassifier();
    _entityRecognizer = EntityRecognizer();
    _sentimentAnalyzer = SentimentAnalyzer();
    _contextualizer = Contextualizer();

    await Future.wait([
      _intentClassifier.initialize(),
      _entityRecognizer.initialize(),
      _sentimentAnalyzer.initialize(),
    ]);
  }

  Future<NLPResult> processText(String text) async {
    try {
      // Preprocess text
      final processedText = _preprocessText(text);
      
      // Tokenize input
      final tokens = await _tokenizer.tokenize(processedText);
      final inputIds = await _tokenizer.convertTokensToIds(tokens);
      final inputMask = List.filled(inputIds.length, 1);
      
      // Pad or truncate to max sequence length
      final paddedIds = _padSequence(inputIds);
      final paddedMask = _padSequence(inputMask);
      
      // Get BERT embeddings
      final embeddings = await _model.generateEmbeddings(
        inputIds: paddedIds,
        inputMask: paddedMask,
      );
      
      // Extract entities
      final entities = await _entityRecognizer.extractEntities(
        text: processedText,
        embeddings: embeddings,
      );
      
      // Analyze sentiment
      final sentiment = await _sentimentAnalyzer.analyzeSentiment(
        text: processedText,
        embeddings: embeddings,
      );
      
      // Extract semantic information
      final extractedInfo = await _extractSemanticInfo(
        text: processedText,
        embeddings: embeddings,
        entities: entities,
      );
      
      // Apply contextual understanding
      final contextualizedInfo = await _contextualizer.contextualize(
        text: processedText,
        extractedInfo: extractedInfo,
        entities: entities,
      );
      
      return NLPResult(
        entities: entities,
        sentiment: sentiment,
        extractedInfo: contextualizedInfo,
      );
    } catch (e) {
      print('Error processing text with NLP: $e');
      return NLPResult(
        entities: [],
        sentiment: 0.0,
        extractedInfo: {},
      );
    }
  }

  String _preprocessText(String text) {
    // Convert to lowercase
    text = text.toLowerCase();
    
    // Remove special characters but keep spaces
    text = text.replaceAll(RegExp(r'[^\w\s]'), '');
    
    // Remove extra whitespace
    text = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    
    return text;
  }

  List<int> _padSequence(List<int> sequence) {
    if (sequence.length > _maxSeqLength) {
      return sequence.sublist(0, _maxSeqLength);
    }
    
    return sequence + List.filled(_maxSeqLength - sequence.length, 0);
  }

  Future<Map<String, dynamic>> _extractSemanticInfo({
    required String text,
    required List<double> embeddings,
    required List<Entity> entities,
  }) async {
    final info = <String, dynamic>{};
    
    // Extract spatial references
    info['spatial'] = await _extractSpatialReferences(text, entities);
    
    // Extract temporal references
    info['temporal'] = await _extractTemporalReferences(text, entities);
    
    // Extract actions
    info['actions'] = await _extractActions(text, embeddings);
    
    // Extract properties
    info['properties'] = await _extractProperties(text, entities);
    
    // Extract relationships
    info['relationships'] = await _extractRelationships(text, entities);
    
    return info;
  }

  Future<Map<String, dynamic>> _extractSpatialReferences(
    String text,
    List<Entity> entities,
  ) async {
    final spatial = <String, dynamic>{};
    
    // Extract locations
    spatial['locations'] = entities
        .where((e) => e.type == 'LOCATION')
        .map((e) => e.value)
        .toList();
    
    // Extract directions
    spatial['directions'] = _extractDirections(text);
    
    // Extract distances
    spatial['distances'] = _extractDistances(text);
    
    return spatial;
  }

  Future<Map<String, dynamic>> _extractTemporalReferences(
    String text,
    List<Entity> entities,
  ) async {
    final temporal = <String, dynamic>{};
    
    // Extract time expressions
    temporal['timeExpressions'] = entities
        .where((e) => e.type == 'TIME')
        .map((e) => e.value)
        .toList();
    
    // Extract durations
    temporal['durations'] = _extractDurations(text);
    
    // Extract sequences
    temporal['sequences'] = _extractSequences(text);
    
    return temporal;
  }

  Future<List<String>> _extractActions(
    String text,
    List<double> embeddings,
  ) async {
    // Extract action verbs and their targets
    final actions = <String>[];
    
    // Use dependency parsing to identify verb phrases
    final doc = await _parseText(text);
    for (final token in doc.tokens) {
      if (token.posTag == 'VERB') {
        final action = _constructActionPhrase(token, doc);
        if (action != null) {
          actions.add(action);
        }
      }
    }
    
    return actions;
  }

  Future<Map<String, dynamic>> _extractProperties(
    String text,
    List<Entity> entities,
  ) async {
    final properties = <String, dynamic>{};
    
    // Extract attributes
    properties['attributes'] = entities
        .where((e) => e.type == 'ATTRIBUTE')
        .map((e) => e.value)
        .toList();
    
    // Extract measurements
    properties['measurements'] = _extractMeasurements(text);
    
    // Extract colors
    properties['colors'] = _extractColors(text);
    
    return properties;
  }

  Future<List<Map<String, dynamic>>> _extractRelationships(
    String text,
    List<Entity> entities,
  ) async {
    final relationships = <Map<String, dynamic>>[];
    
    // Use dependency parsing to identify relationships between entities
    final doc = await _parseText(text);
    for (final entity1 in entities) {
      for (final entity2 in entities) {
        if (entity1 != entity2) {
          final relationship = _findRelationship(entity1, entity2, doc);
          if (relationship != null) {
            relationships.add(relationship);
          }
        }
      }
    }
    
    return relationships;
  }

  List<String> _extractDirections(String text) {
    final directions = <String>[];
    final directionKeywords = [
      'up', 'down', 'left', 'right',
      'north', 'south', 'east', 'west',
      'above', 'below', 'behind', 'in front'
    ];
    
    for (final keyword in directionKeywords) {
      if (text.contains(keyword)) {
        directions.add(keyword);
      }
    }
    
    return directions;
  }

  List<Map<String, dynamic>> _extractDistances(String text) {
    final distances = <Map<String, dynamic>>[];
    final pattern = RegExp(r'(\d+(?:\.\d+)?)\s*(meter|meters|m|cm|kilometer|kilometers|km)');
    
    for (final match in pattern.allMatches(text)) {
      distances.add({
        'value': double.parse(match.group(1)!),
        'unit': match.group(2)!,
      });
    }
    
    return distances;
  }

  List<Map<String, dynamic>> _extractDurations(String text) {
    final durations = <Map<String, dynamic>>[];
    final pattern = RegExp(r'(\d+(?:\.\d+)?)\s*(second|seconds|minute|minutes|hour|hours)');
    
    for (final match in pattern.allMatches(text)) {
      durations.add({
        'value': double.parse(match.group(1)!),
        'unit': match.group(2)!,
      });
    }
    
    return durations;
  }

  List<String> _extractSequences(String text) {
    final sequences = <String>[];
    final sequenceKeywords = [
      'first', 'second', 'third', 'next',
      'before', 'after', 'then', 'finally'
    ];
    
    for (final keyword in sequenceKeywords) {
      if (text.contains(keyword)) {
        sequences.add(keyword);
      }
    }
    
    return sequences;
  }

  List<Map<String, dynamic>> _extractMeasurements(String text) {
    final measurements = <Map<String, dynamic>>[];
    final pattern = RegExp(r'(\d+(?:\.\d+)?)\s*(degree|degrees|°|mm|cm|m|kg|g)');
    
    for (final match in pattern.allMatches(text)) {
      measurements.add({
        'value': double.parse(match.group(1)!),
        'unit': match.group(2)!,
      });
    }
    
    return measurements;
  }

  List<String> _extractColors(String text) {
    final colors = <String>[];
    final colorKeywords = [
      'red', 'green', 'blue', 'yellow', 'orange',
      'purple', 'pink', 'black', 'white', 'gray'
    ];
    
    for (final keyword in colorKeywords) {
      if (text.contains(keyword)) {
        colors.add(keyword);
      }
    }
    
    return colors;
  }

  Future<Document> _parseText(String text) async {
    // Placeholder for actual NLP parsing
    return Document();
  }

  String? _constructActionPhrase(Token verb, Document doc) {
    // Placeholder for action phrase construction
    return null;
  }

  Map<String, dynamic>? _findRelationship(
    Entity entity1,
    Entity entity2,
    Document doc,
  ) {
    // Placeholder for relationship extraction
    return null;
  }

  void dispose() {
    _model.dispose();
  }
}

class BertTokenizer {
  static Future<BertTokenizer> fromVocabFile(String path) async {
    // Initialize BERT tokenizer from vocabulary file
    return BertTokenizer();
  }
  
  Future<List<String>> tokenize(String text) async {
    // Tokenize text using BERT tokenizer
    return [];
  }
  
  Future<List<int>> convertTokensToIds(List<String> tokens) async {
    // Convert tokens to input IDs
    return [];
  }
}

class BertModel {
  static Future<BertModel> fromTflite(String path) async {
    // Initialize BERT model from TFLite file
    return BertModel();
  }
  
  Future<List<double>> generateEmbeddings({
    required List<int> inputIds,
    required List<int> inputMask,
  }) async {
    // Generate BERT embeddings
    return [];
  }
  
  void dispose() {
    // Clean up resources
  }
}

class IntentClassifier {
  Future<void> initialize() async {
    // Initialize intent classifier
  }
}

class EntityRecognizer {
  Future<void> initialize() async {
    // Initialize entity recognizer
  }
  
  Future<List<Entity>> extractEntities({
    required String text,
    required List<double> embeddings,
  }) async {
    // Extract named entities
    return [];
  }
}

class SentimentAnalyzer {
  Future<void> initialize() async {
    // Initialize sentiment analyzer
  }
  
  Future<double> analyzeSentiment({
    required String text,
    required List<double> embeddings,
  }) async {
    // Analyze sentiment
    return 0.0;
  }
}

class Contextualizer {
  Future<Map<String, dynamic>> contextualize({
    required String text,
    required Map<String, dynamic> extractedInfo,
    required List<Entity> entities,
  }) async {
    // Add contextual understanding
    return extractedInfo;
  }
}

class Document {
  List<Token> tokens = [];
}

class Token {
  final String text;
  final String posTag;
  
  Token({
    required this.text,
    required this.posTag,
  });
}

class DialogflowIntent {
  final String name;
  final double confidence;
  final Map<String, dynamic>? parameters;

  DialogflowIntent({
    required this.name,
    required this.confidence,
    this.parameters,
  });
}

class RecognizedVoiceCommand {
  final VoiceCommandType type;
  final String originalText;
  final DialogflowIntent intent;
  final Map<String, dynamic> parameters;
  final double confidence;
  final CommandContext context;
  final DateTime timestamp;

  RecognizedVoiceCommand({
    required this.type,
    required this.originalText,
    required this.intent,
    required this.parameters,
    required this.confidence,
    required this.context,
    required this.timestamp,
  });
}

class CommandContext {
  final RecognizedVoiceCommand? previousCommand;
  final Map<String, dynamic> relevantParams;
  final DateTime? timestamp;

  CommandContext({
    this.previousCommand,
    this.relevantParams = const {},
    this.timestamp,
  });
}

class NLPResult {
  final List<Entity> entities;
  final double sentiment;
  final Map<String, dynamic> extractedInfo;

  NLPResult({
    required this.entities,
    required this.sentiment,
    required this.extractedInfo,
  });
}

class Entity {
  final String type;
  final String value;
  final double confidence;

  Entity({
    required this.type,
    required this.value,
    required this.confidence,
  });
}

enum VoiceCommandType {
  navigation,
  creation,
  manipulation,
  query,
  unknown,
}