import 'dart:async';
import 'dart:convert';
import 'package:vector_math/vector_math_64.dart';
import '../models/spatial_anchor.dart';
import '../models/mesh_session.dart';
import '../services/mesh_network_service.dart';
import '../core/app_config.dart';

class CollaborativeARService {
  late final MeshNetworkService _networkService;
  late final SpatialAnchorManager _anchorManager;
  late final UserPresenceTracker _presenceTracker;
  late final SharedStateManager _stateManager;
  late final InteractionSynchronizer _interactionSync;
  
  final _participantController = StreamController<List<ARParticipant>>.broadcast();
  final _anchorController = StreamController<List<SharedAnchor>>.broadcast();
  final _interactionController = StreamController<ARInteraction>.broadcast();
  
  Stream<List<ARParticipant>> get participantUpdates => _participantController.stream;
  Stream<List<SharedAnchor>> get anchorUpdates => _anchorController.stream;
  Stream<ARInteraction> get interactionUpdates => _interactionController.stream;
  
  String get sessionId => _stateManager.sessionId;
  List<ARParticipant> get activeParticipants => _presenceTracker.activeParticipants;

  Future<void> initialize({
    required String userId,
    required String sessionId,
  }) async {
    // Initialize network service
    _networkService = MeshNetworkService(userId, sessionId);
    await _networkService.initialize();

    // Initialize spatial anchor management
    _anchorManager = SpatialAnchorManager(
      cloudPersistence: true,
      localPersistence: true,
      syncInterval: Duration(milliseconds: 100),
    );

    // Initialize presence tracking
    _presenceTracker = UserPresenceTracker(
      heartbeatInterval: Duration(seconds: 1),
      timeoutDuration: Duration(seconds: 5),
    );

    // Initialize shared state management
    _stateManager = SharedStateManager(
      sessionId: sessionId,
      userId: userId,
      consistencyModel: ConsistencyModel.eventualWithCRDT,
    );

    // Initialize interaction synchronization
    _interactionSync = InteractionSynchronizer(
      predictionEnabled: true,
      interpolationEnabled: true,
      latencyCompensation: true,
    );

    // Set up network listeners
    _setupNetworkListeners();

    // Start presence broadcasting
    _startPresenceBroadcast();
  }

  void _setupNetworkListeners() {
    // Listen for participant updates
    _networkService.peerUpdates.listen((peers) {
      _presenceTracker.updatePeers(peers);
      _participantController.add(_presenceTracker.activeParticipants);
    });

    // Listen for anchor updates
    _networkService.anchorUpdates.listen((anchor) {
      _handleAnchorUpdate(anchor);
    });

    // Listen for shared state updates
    _networkService.sessionUpdates.listen((session) {
      _handleSessionUpdate(session);
    });
  }

  void _startPresenceBroadcast() {
    Timer.periodic(Duration(seconds: 1), (_) {
      _broadcastPresence();
    });
  }

  Future<void> _broadcastPresence() async {
    final presence = UserPresence(
      userId: _stateManager.userId,
      position: await _getCurrentPosition(),
      orientation: await _getCurrentOrientation(),
      timestamp: DateTime.now(),
    );

    await _presenceTracker.updatePresence(presence);
    await _networkService.broadcastSpatialData({
      'type': 'presence',
      'data': presence.toJson(),
    });
  }

  Future<SharedAnchor> createSharedAnchor({
    required Vector3 position,
    required Quaternion orientation,
    Map<String, dynamic>? metadata,
  }) async {
    // Create anchor with unique ID
    final anchor = SharedAnchor(
      id: _generateUniqueId(),
      position: position,
      orientation: orientation,
      creatorId: _stateManager.userId,
      timestamp: DateTime.now(),
      metadata: metadata ?? {},
    );

    // Save anchor locally
    await _anchorManager.saveAnchor(anchor);

    // Broadcast to peers
    await _networkService.broadcastSpatialData({
      'type': 'anchor',
      'data': anchor.toJson(),
    });

    return anchor;
  }

  Future<void> updateSharedAnchor(
    String anchorId,
    Map<String, dynamic> updates,
  ) async {
    final anchor = await _anchorManager.getAnchor(anchorId);
    if (anchor == null) throw Exception('Anchor not found');

    // Apply updates
    final updatedAnchor = anchor.copyWith(
      position: updates['position'] ?? anchor.position,
      orientation: updates['orientation'] ?? anchor.orientation,
      metadata: {...anchor.metadata, ...?updates['metadata']},
      timestamp: DateTime.now(),
    );

    // Save locally
    await _anchorManager.saveAnchor(updatedAnchor);

    // Broadcast updates
    await _networkService.broadcastSpatialData({
      'type': 'anchor_update',
      'data': updatedAnchor.toJson(),
    });
  }

  Future<void> shareInteraction(ARInteraction interaction) async {
    // Apply prediction
    final predictedInteraction = await _interactionSync.predictInteraction(
      interaction,
    );

    // Broadcast interaction
    await _networkService.broadcastSpatialData({
      'type': 'interaction',
      'data': predictedInteraction.toJson(),
    });

    // Apply locally
    _interactionController.add(predictedInteraction);
  }

  Future<void> _handleAnchorUpdate(SpatialAnchor anchor) async {
    // Validate anchor
    if (!await _anchorManager.isValidAnchor(anchor)) {
      print('Invalid anchor received: ${anchor.id}');
      return;
    }

    // Save anchor
    await _anchorManager.saveAnchor(anchor);

    // Notify listeners
    _anchorController.add(await _anchorManager.getAnchors());
  }

  Future<void> _handleSessionUpdate(MeshSession session) async {
    // Update shared state
    await _stateManager.applySessionUpdate(session);

    // Reconcile anchors
    await _reconcileAnchors(session);
  }

  Future<void> _reconcileAnchors(MeshSession session) async {
    final localAnchors = await _anchorManager.getAnchors();
    final sessionAnchors = session.spatialData['anchors'] as List<SharedAnchor>?;

    if (sessionAnchors == null) return;

    // Find anchors to sync
    for (final anchor in sessionAnchors) {
      final localAnchor = localAnchors.firstWhere(
        (a) => a.id == anchor.id,
        orElse: () => null as SharedAnchor,
      );

      if (localAnchor == null || localAnchor.timestamp.isBefore(anchor.timestamp)) {
        await _anchorManager.saveAnchor(anchor);
      }
    }
  }

  Future<Vector3> _getCurrentPosition() async {
    // Get current AR camera position
    return Vector3.zero(); // Placeholder
  }

  Future<Quaternion> _getCurrentOrientation() async {
    // Get current AR camera orientation
    return Quaternion.identity(); // Placeholder
  }

  String _generateUniqueId() {
    return '${_stateManager.userId}-${DateTime.now().millisecondsSinceEpoch}';
  }

  void dispose() {
    _participantController.close();
    _anchorController.close();
    _interactionController.close();
    _networkService.dispose();
  }
}

class SharedAnchor extends SpatialAnchor {
  final String creatorId;
  final Map<String, dynamic> metadata;

  SharedAnchor({
    required String id,
    required Vector3 position,
    required Quaternion orientation,
    required this.creatorId,
    required DateTime timestamp,
    required this.metadata,
  }) : super(
    id: id,
    position: position,
    orientation: orientation,
    timestamp: timestamp,
  );

  SharedAnchor copyWith({
    Vector3? position,
    Quaternion? orientation,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) {
    return SharedAnchor(
      id: id,
      position: position ?? this.position,
      orientation: orientation ?? this.orientation,
      creatorId: creatorId,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'creatorId': creatorId,
    'metadata': metadata,
  };
}

class ARParticipant {
  final String userId;
  final Vector3 position;
  final Quaternion orientation;
  final DateTime lastUpdate;
  final Map<String, dynamic>? metadata;

  ARParticipant({
    required this.userId,
    required this.position,
    required this.orientation,
    required this.lastUpdate,
    this.metadata,
  });
}

class UserPresence {
  final String userId;
  final Vector3 position;
  final Quaternion orientation;
  final DateTime timestamp;

  UserPresence({
    required this.userId,
    required this.position,
    required this.orientation,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'position': {
      'x': position.x,
      'y': position.y,
      'z': position.z,
    },
    'orientation': {
      'x': orientation.x,
      'y': orientation.y,
      'z': orientation.z,
      'w': orientation.w,
    },
    'timestamp': timestamp.toIso8601String(),
  };
}

class ARInteraction {
  final String userId;
  final String type;
  final Vector3 position;
  final Quaternion orientation;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  ARInteraction({
    required this.userId,
    required this.type,
    required this.position,
    required this.orientation,
    required this.data,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'type': type,
    'position': {
      'x': position.x,
      'y': position.y,
      'z': position.z,
    },
    'orientation': {
      'x': orientation.x,
      'y': orientation.y,
      'z': orientation.z,
      'w': orientation.w,
    },
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

enum ConsistencyModel {
  strongWithLocks,
  eventualWithCRDT,
  causalWithVectorClocks,
}