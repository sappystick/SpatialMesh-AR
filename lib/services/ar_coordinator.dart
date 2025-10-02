import 'dart:async';
import 'package:vector_math/vector_math_64.dart';

class ARCoordinator {
  final ARService _arService;
  final SpatialService _spatialService;
  final MeshNetworkService _meshService;
  
  bool _isInitialized = false;
  StreamController<ARCoordinatorUpdate>? _updateController;
  
  ARCoordinator({
    required ARService arService,
    required SpatialService spatialService,
    required MeshNetworkService meshService,
  })  : _arService = arService,
        _spatialService = spatialService,
        _meshService = meshService;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize services
      await _arService.initialize();
      await _spatialService.initialize();
      await _meshService.initialize();
      
      // Set up update stream
      _updateController = StreamController<ARCoordinatorUpdate>.broadcast();
      
      // Subscribe to service updates
      _arService.updates?.listen(_handleARUpdate);
      _spatialService.updates.listen(_handleSpatialUpdate);
      _meshService.updates.listen(_handleMeshUpdate);
      
      _isInitialized = true;
      
    } catch (e) {
      print('AR Coordinator initialization error: $e');
      rethrow;
    }
  }
  
  Stream<ARCoordinatorUpdate>? get updates => _updateController?.stream;
  
  void _handleARUpdate(ARUpdate update) async {
    try {
      // Process anchor updates
      for (final anchor in update.anchors) {
        // Update spatial mapping
        await _spatialService.updateSpatialAnchor(
          anchor.id,
          position: anchor.position,
          metadata: anchor.metadata,
        );
        
        // Broadcast anchor update to mesh network
        await _meshService.broadcastAnchorUpdate(
          anchorId: anchor.id,
          position: anchor.position,
          metadata: anchor.metadata,
        );
      }
      
      // Notify coordinator listeners
      _updateController?.add(ARCoordinatorUpdate(
        trackingState: update.trackingState,
        anchors: update.anchors,
        worldScale: update.worldScale,
        meshPeers: await _meshService.getConnectedPeers(),
      ));
      
    } catch (e) {
      print('Error handling AR update: $e');
    }
  }
  
  void _handleSpatialUpdate(SpatialUpdate update) async {
    try {
      // Process spatial changes
      for (final change in update.changes) {
        switch (change.type) {
          case SpatialChangeType.anchorAdded:
            // Create AR anchor for new spatial anchor
            await _arService.createAnchor(
              change.position,
              cloudId: change.id,
              metadata: change.metadata,
            );
            break;
            
          case SpatialChangeType.anchorUpdated:
            // Update AR anchor with spatial changes
            await _arService.updateAnchor(
              change.id,
              change.position,
              metadata: change.metadata,
            );
            break;
            
          case SpatialChangeType.anchorRemoved:
            // Remove AR anchor
            await _arService.removeAnchor(change.id);
            break;
        }
      }
      
      // Broadcast spatial update to mesh
      await _meshService.broadcastSpatialUpdate(update);
      
    } catch (e) {
      print('Error handling spatial update: $e');
    }
  }
  
  void _handleMeshUpdate(MeshNetworkUpdate update) async {
    try {
      switch (update.type) {
        case MeshUpdateType.peerJoined:
          // Share current spatial state with new peer
          final spatialState = await _spatialService.getCurrentState();
          await _meshService.sendSpatialState(
            update.peerId,
            spatialState,
          );
          break;
          
        case MeshUpdateType.spatialUpdate:
          // Process spatial update from mesh
          await _spatialService.processMeshUpdate(
            update.peerId,
            update.spatialUpdate,
          );
          break;
          
        case MeshUpdateType.anchorUpdate:
          // Update local anchor from mesh
          await _arService.updateAnchor(
            update.anchorId,
            update.position,
            metadata: update.metadata,
          );
          break;
      }
      
    } catch (e) {
      print('Error handling mesh update: $e');
    }
  }
  
  Future<void> createSharedAnchor(
    Vector3 position,
    Map<String, dynamic> metadata,
  ) async {
    if (!_isInitialized) throw StateError('AR Coordinator not initialized');
    
    try {
      // Create anchor in AR system
      final anchor = await _arService.createAnchor(
        position,
        metadata: metadata,
      );
      
      if (anchor != null) {
        // Create spatial mapping
        await _spatialService.createSpatialAnchor(
          anchor.id,
          position: position,
          metadata: metadata,
        );
        
        // Broadcast to mesh network
        await _meshService.broadcastNewAnchor(
          anchorId: anchor.id,
          position: position,
          metadata: metadata,
        );
      }
      
    } catch (e) {
      print('Error creating shared anchor: $e');
      rethrow;
    }
  }
  
  Future<void> updateSharedAnchor(
    String anchorId,
    Vector3 newPosition, {
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) throw StateError('AR Coordinator not initialized');
    
    try {
      // Update AR anchor
      final success = await _arService.updateAnchor(
        anchorId,
        newPosition,
        metadata: metadata,
      );
      
      if (success) {
        // Update spatial mapping
        await _spatialService.updateSpatialAnchor(
          anchorId,
          position: newPosition,
          metadata: metadata,
        );
        
        // Broadcast update to mesh
        await _meshService.broadcastAnchorUpdate(
          anchorId: anchorId,
          position: newPosition,
          metadata: metadata,
        );
      }
      
    } catch (e) {
      print('Error updating shared anchor: $e');
      rethrow;
    }
  }
  
  Future<void> removeSharedAnchor(String anchorId) async {
    if (!_isInitialized) throw StateError('AR Coordinator not initialized');
    
    try {
      // Remove from AR system
      final success = await _arService.removeAnchor(anchorId);
      
      if (success) {
        // Remove spatial mapping
        await _spatialService.removeSpatialAnchor(anchorId);
        
        // Broadcast removal to mesh
        await _meshService.broadcastAnchorRemoval(anchorId);
      }
      
    } catch (e) {
      print('Error removing shared anchor: $e');
      rethrow;
    }
  }
  
  Future<void> processFrame(CameraFrame frame) async {
    if (!_isInitialized) return;
    
    try {
      // Update AR processing
      await _arService.updateFrame(frame);
      
      // Update spatial understanding
      await _spatialService.processFrame(frame);
      
    } catch (e) {
      print('Error processing frame: $e');
    }
  }
  
  Future<void> dispose() async {
    await _arService.dispose();
    await _spatialService.dispose();
    await _meshService.dispose();
    await _updateController?.close();
  }
}

class ARCoordinatorUpdate {
  final TrackingState trackingState;
  final List<Anchor> anchors;
  final double worldScale;
  final List<String> meshPeers;
  
  ARCoordinatorUpdate({
    required this.trackingState,
    required this.anchors,
    required this.worldScale,
    required this.meshPeers,
  });
}

class SpatialUpdate {
  final List<SpatialChange> changes;
  
  SpatialUpdate({required this.changes});
}

class SpatialChange {
  final String id;
  final SpatialChangeType type;
  final Vector3 position;
  final Map<String, dynamic>? metadata;
  
  SpatialChange({
    required this.id,
    required this.type,
    required this.position,
    this.metadata,
  });
}

enum SpatialChangeType {
  anchorAdded,
  anchorUpdated,
  anchorRemoved,
}

class MeshNetworkUpdate {
  final MeshUpdateType type;
  final String peerId;
  final String? anchorId;
  final Vector3? position;
  final Map<String, dynamic>? metadata;
  final SpatialUpdate? spatialUpdate;
  
  MeshNetworkUpdate({
    required this.type,
    required this.peerId,
    this.anchorId,
    this.position,
    this.metadata,
    this.spatialUpdate,
  });
}

enum MeshUpdateType {
  peerJoined,
  peerLeft,
  spatialUpdate,
  anchorUpdate,
}