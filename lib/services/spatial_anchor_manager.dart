import 'dart:async';
import 'package:vector_math/vector_math_64.dart';
import '../models/spatial_anchor.dart';
import '../services/collaborative_ar_service.dart';
import '../services/aws_service.dart';

class SpatialAnchorManager {
  final bool cloudPersistence;
  final bool localPersistence;
  final Duration syncInterval;

  final Map<String, SharedAnchor> _localAnchors = {};
  final _cloudSync = CloudAnchorSync();
  final _localStorage = LocalAnchorStorage();
  Timer? _syncTimer;

  SpatialAnchorManager({
    required this.cloudPersistence,
    required this.localPersistence,
    required this.syncInterval,
  }) {
    _initialize();
  }

  Future<void> _initialize() async {
    if (localPersistence) {
      await _loadLocalAnchors();
    }

    if (cloudPersistence) {
      await _loadCloudAnchors();
      _startCloudSync();
    }
  }

  Future<void> saveAnchor(SharedAnchor anchor) async {
    // Save to memory
    _localAnchors[anchor.id] = anchor;

    // Save to local storage if enabled
    if (localPersistence) {
      await _localStorage.saveAnchor(anchor);
    }

    // Save to cloud if enabled
    if (cloudPersistence) {
      await _cloudSync.uploadAnchor(anchor);
    }
  }

  Future<SharedAnchor?> getAnchor(String anchorId) async {
    return _localAnchors[anchorId];
  }

  Future<List<SharedAnchor>> getAnchors() async {
    return _localAnchors.values.toList();
  }

  Future<bool> isValidAnchor(SpatialAnchor anchor) async {
    // Validate anchor format
    if (!_isValidAnchorFormat(anchor)) {
      return false;
    }

    // Check if anchor already exists
    final existingAnchor = await getAnchor(anchor.id);
    if (existingAnchor != null) {
      // If anchor exists, validate update
      return _isValidAnchorUpdate(existingAnchor, anchor);
    }

    return true;
  }

  bool _isValidAnchorFormat(SpatialAnchor anchor) {
    // Check required fields
    if (anchor.id.isEmpty) return false;
    if (anchor.position == null) return false;
    if (anchor.orientation == null) return false;
    if (anchor.timestamp == null) return false;

    // Validate position values
    if (anchor.position.x.isNaN || 
        anchor.position.y.isNaN || 
        anchor.position.z.isNaN) {
      return false;
    }

    // Validate orientation values
    if (anchor.orientation.x.isNaN || 
        anchor.orientation.y.isNaN || 
        anchor.orientation.z.isNaN || 
        anchor.orientation.w.isNaN) {
      return false;
    }

    return true;
  }

  bool _isValidAnchorUpdate(SharedAnchor existing, SpatialAnchor update) {
    // Check if update is newer than existing
    if (update.timestamp.isBefore(existing.timestamp)) {
      return false;
    }

    // Check if position change is within reasonable bounds
    final positionDelta = update.position - existing.position;
    if (positionDelta.length > 10.0) { // 10 meters max change
      return false;
    }

    // Check if orientation change is within reasonable bounds
    final orientationDelta = update.orientation * existing.orientation.inverted();
    final angleChange = 2.0 * acos(orientationDelta.w.abs());
    if (angleChange > pi) { // Max 180 degree change
      return false;
    }

    return true;
  }

  Future<void> _loadLocalAnchors() async {
    final anchors = await _localStorage.loadAnchors();
    for (final anchor in anchors) {
      _localAnchors[anchor.id] = anchor;
    }
  }

  Future<void> _loadCloudAnchors() async {
    final anchors = await _cloudSync.downloadAnchors();
    for (final anchor in anchors) {
      _localAnchors[anchor.id] = anchor;
    }
  }

  void _startCloudSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncInterval, (_) {
      _syncWithCloud();
    });
  }

  Future<void> _syncWithCloud() async {
    try {
      // Get latest cloud anchors
      final cloudAnchors = await _cloudSync.downloadAnchors();
      
      // Merge with local anchors
      for (final cloudAnchor in cloudAnchors) {
        final localAnchor = _localAnchors[cloudAnchor.id];
        
        if (localAnchor == null || 
            cloudAnchor.timestamp.isAfter(localAnchor.timestamp)) {
          _localAnchors[cloudAnchor.id] = cloudAnchor;
          
          if (localPersistence) {
            await _localStorage.saveAnchor(cloudAnchor);
          }
        }
      }
      
      // Upload local changes
      for (final localAnchor in _localAnchors.values) {
        final cloudAnchor = cloudAnchors.firstWhere(
          (a) => a.id == localAnchor.id,
          orElse: () => null as SharedAnchor,
        );
        
        if (cloudAnchor == null || 
            localAnchor.timestamp.isAfter(cloudAnchor.timestamp)) {
          await _cloudSync.uploadAnchor(localAnchor);
        }
      }
    } catch (e) {
      print('Cloud sync failed: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}

class CloudAnchorSync {
  final AwsService _awsService = AwsService();
  
  Future<List<SharedAnchor>> downloadAnchors() async {
    try {
      final response = await _awsService.getSpatialAnchors();
      return _parseCloudAnchors(response);
    } catch (e) {
      print('Failed to download cloud anchors: $e');
      return [];
    }
  }
  
  Future<void> uploadAnchor(SharedAnchor anchor) async {
    try {
      await _awsService.putSpatialAnchor(anchor);
    } catch (e) {
      print('Failed to upload anchor to cloud: $e');
    }
  }
  
  List<SharedAnchor> _parseCloudAnchors(dynamic response) {
    final anchors = <SharedAnchor>[];
    
    try {
      final List<dynamic> items = response['Items'];
      for (final item in items) {
        anchors.add(SharedAnchor(
          id: item['id'],
          position: Vector3(
            item['position']['x'],
            item['position']['y'],
            item['position']['z'],
          ),
          orientation: Quaternion(
            item['orientation']['x'],
            item['orientation']['y'],
            item['orientation']['z'],
            item['orientation']['w'],
          ),
          creatorId: item['creatorId'],
          timestamp: DateTime.parse(item['timestamp']),
          metadata: item['metadata'],
        ));
      }
    } catch (e) {
      print('Error parsing cloud anchors: $e');
    }
    
    return anchors;
  }
}

class LocalAnchorStorage {
  static const _storageKey = 'spatial_anchors';
  
  Future<void> saveAnchor(SharedAnchor anchor) async {
    try {
      final anchors = await loadAnchors();
      final index = anchors.indexWhere((a) => a.id == anchor.id);
      
      if (index >= 0) {
        anchors[index] = anchor;
      } else {
        anchors.add(anchor);
      }
      
      await _saveAnchors(anchors);
    } catch (e) {
      print('Failed to save anchor locally: $e');
    }
  }
  
  Future<List<SharedAnchor>> loadAnchors() async {
    try {
      // In a real implementation, this would load from local storage
      return [];
    } catch (e) {
      print('Failed to load local anchors: $e');
      return [];
    }
  }
  
  Future<void> _saveAnchors(List<SharedAnchor> anchors) async {
    // In a real implementation, this would save to local storage
  }
}