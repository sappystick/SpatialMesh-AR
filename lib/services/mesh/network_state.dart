import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

class NetworkState {
  static const STATE_FILE = 'mesh_network_state.json';
  static const STATE_BACKUP = 'mesh_network_state.backup.json';
  static const MAX_HISTORY = 100;
  
  final bool enablePersistence;
  final String localPeerId;
  final Map<String, PeerState> _peerStates = {};
  final List<StateChange> _stateHistory = [];
  
  Timer? _persistTimer;
  DateTime? _lastPersist;
  bool _isDirty = false;
  
  NetworkState({
    required this.enablePersistence,
  }) : localPeerId = const Uuid().v4();
  
  Future<void> initialize() async {
    if (enablePersistence) {
      // Restore state from disk
      await _restoreState();
      
      // Start periodic state persistence
      _persistTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _persistState(),
      );
    }
  }
  
  Future<void> _restoreState() async {
    try {
      final file = await _getStateFile();
      final backupFile = await _getBackupFile();
      
      if (await file.exists()) {
        // Try loading main state file
        try {
          await _loadFromFile(file);
          return;
        } catch (e) {
          print('Error loading state file: $e');
        }
      }
      
      if (await backupFile.exists()) {
        // Try loading backup file
        try {
          await _loadFromFile(backupFile);
          // Restore main file from backup
          await backupFile.copy(file.path);
        } catch (e) {
          print('Error loading backup state file: $e');
        }
      }
      
    } catch (e) {
      print('Error restoring network state: $e');
    }
  }
  
  Future<void> _loadFromFile(File file) async {
    final contents = await file.readAsString();
    final json = jsonDecode(contents);
    
    // Validate state file integrity
    if (!_validateStateFile(json)) {
      throw StateError('Invalid state file');
    }
    
    // Clear current state
    _peerStates.clear();
    _stateHistory.clear();
    
    // Restore peer states
    final peers = json['peers'] as Map<String, dynamic>;
    for (final entry in peers.entries) {
      _peerStates[entry.key] = PeerState.fromJson(entry.value);
    }
    
    // Restore state history
    final history = json['history'] as List;
    for (final change in history) {
      _stateHistory.add(StateChange.fromJson(change));
    }
  }
  
  bool _validateStateFile(Map<String, dynamic> json) {
    try {
      // Check required fields
      if (!json.containsKey('peers') ||
          !json.containsKey('history') ||
          !json.containsKey('checksum')) {
        return false;
      }
      
      // Verify checksum
      final checksum = json['checksum'];
      final computedChecksum = _computeStateChecksum(
        json['peers'],
        json['history'],
      );
      
      return checksum == computedChecksum;
    } catch (e) {
      print('State validation error: $e');
      return false;
    }
  }
  
  String _computeStateChecksum(
    Map<String, dynamic> peers,
    List<dynamic> history,
  ) {
    final data = json.encode({
      'peers': peers,
      'history': history,
    });
    
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  Future<File> _getStateFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$STATE_FILE');
  }
  
  Future<File> _getBackupFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$STATE_BACKUP');
  }
  
  Future<void> _persistState() async {
    if (!enablePersistence || !_isDirty) return;
    
    try {
      final file = await _getStateFile();
      final backupFile = await _getBackupFile();
      
      // Create state snapshot
      final stateJson = {
        'peers': _peerStates.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
        'history': _stateHistory.map((e) => e.toJson()).toList(),
      };
      
      // Add checksum
      final checksum = _computeStateChecksum(
        stateJson['peers']!,
        stateJson['history']!,
      );
      stateJson['checksum'] = checksum;
      
      // Write to temporary file first
      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(json.encode(stateJson));
      
      // Backup current state file if it exists
      if (await file.exists()) {
        await file.copy(backupFile.path);
      }
      
      // Replace state file with temporary file
      await tempFile.rename(file.path);
      
      _isDirty = false;
      _lastPersist = DateTime.now();
      
    } catch (e) {
      print('Error persisting network state: $e');
    }
  }
  
  Future<void> addPeer(PeerInfo peer) async {
    _peerStates[peer.id] = PeerState(
      info: peer,
      lastSeen: DateTime.now(),
      status: PeerStatus.active,
    );
    
    _addStateChange(StateChangeType.peerAdded, peer.id);
  }
  
  Future<void> updatePeer(
    String peerId,
    PeerStatus status,
  ) async {
    final state = _peerStates[peerId];
    if (state != null) {
      _peerStates[peerId] = state.copyWith(
        status: status,
        lastSeen: DateTime.now(),
      );
      
      _addStateChange(StateChangeType.peerUpdated, peerId);
    }
  }
  
  Future<void> removePeer(String peerId) async {
    _peerStates.remove(peerId);
    _addStateChange(StateChangeType.peerRemoved, peerId);
  }
  
  void _addStateChange(StateChangeType type, String peerId) {
    _stateHistory.add(StateChange(
      type: type,
      peerId: peerId,
      timestamp: DateTime.now(),
    ));
    
    // Trim history if needed
    if (_stateHistory.length > MAX_HISTORY) {
      _stateHistory.removeRange(0, _stateHistory.length - MAX_HISTORY);
    }
    
    _isDirty = true;
  }
  
  Future<NetworkStateSnapshot> loadState() async {
    return NetworkStateSnapshot(
      peers: _peerStates.values
          .where((state) => state.status == PeerStatus.active)
          .map((state) => state.info)
          .toList(),
    );
  }
  
  Future<void> mergeState(
    String peerId,
    Map<String, dynamic> state,
  ) async {
    try {
      // Validate state data
      if (!_validatePeerState(state)) return;
      
      final peerStates = state['peers'] as Map<String, dynamic>;
      
      // Merge peer states
      for (final entry in peerStates.entries) {
        final peerState = PeerState.fromJson(entry.value);
        
        // Only update if peer state is newer
        final existingState = _peerStates[entry.key];
        if (existingState == null ||
            peerState.lastSeen.isAfter(existingState.lastSeen)) {
          _peerStates[entry.key] = peerState;
          _addStateChange(StateChangeType.peerUpdated, entry.key);
        }
      }
      
    } catch (e) {
      print('Error merging network state: $e');
    }
  }
  
  bool _validatePeerState(Map<String, dynamic> state) {
    try {
      if (!state.containsKey('peers')) return false;
      
      final peers = state['peers'] as Map<String, dynamic>;
      for (final peer in peers.values) {
        if (!_validatePeerStateEntry(peer)) return false;
      }
      
      return true;
    } catch (e) {
      print('Peer state validation error: $e');
      return false;
    }
  }
  
  bool _validatePeerStateEntry(dynamic entry) {
    if (entry is! Map<String, dynamic>) return false;
    
    return entry.containsKey('info') &&
           entry.containsKey('lastSeen') &&
           entry.containsKey('status');
  }
  
  Future<void> dispose() async {
    _persistTimer?.cancel();
    
    if (enablePersistence && _isDirty) {
      await _persistState();
    }
  }
}

class PeerState {
  final PeerInfo info;
  final DateTime lastSeen;
  final PeerStatus status;
  
  PeerState({
    required this.info,
    required this.lastSeen,
    required this.status,
  });
  
  PeerState copyWith({
    PeerInfo? info,
    DateTime? lastSeen,
    PeerStatus? status,
  }) {
    return PeerState(
      info: info ?? this.info,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
    );
  }
  
  factory PeerState.fromJson(Map<String, dynamic> json) {
    return PeerState(
      info: PeerInfo(
        id: json['info']['id'],
        publicKey: json['info']['publicKey'],
        capabilities: json['info']['capabilities'],
        signature: json['info']['signature'],
      ),
      lastSeen: DateTime.parse(json['lastSeen']),
      status: PeerStatus.values[json['status']],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'info': {
      'id': info.id,
      'publicKey': info.publicKey,
      'capabilities': info.capabilities,
      'signature': info.signature,
    },
    'lastSeen': lastSeen.toIso8601String(),
    'status': status.index,
  };
}

class StateChange {
  final StateChangeType type;
  final String peerId;
  final DateTime timestamp;
  
  StateChange({
    required this.type,
    required this.peerId,
    required this.timestamp,
  });
  
  factory StateChange.fromJson(Map<String, dynamic> json) {
    return StateChange(
      type: StateChangeType.values[json['type']],
      peerId: json['peerId'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'type': type.index,
    'peerId': peerId,
    'timestamp': timestamp.toIso8601String(),
  };
}

class NetworkStateSnapshot {
  final List<PeerInfo> peers;
  
  NetworkStateSnapshot({required this.peers});
}

enum PeerStatus {
  active,
  inactive,
  disconnected,
}

enum StateChangeType {
  peerAdded,
  peerUpdated,
  peerRemoved,
}