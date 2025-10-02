import 'package:vector_math/vector_math_64.dart';
import 'dart:async';
import 'dart:collection';
import 'quantum_state_vector.dart';

class QuantumInspiredStateSync {
  final Map<String, QuantumStateVector> _nodeStates = {};
  final Map<String, Map<String, double>> _entanglementGraph = {};
  final Queue<StateUpdate> _updateQueue = Queue();
  
  Timer? _processingTimer;
  bool _isProcessing = false;
  
  static const int _maxQubits = 10;
  static const double _entanglementThreshold = 0.8;
  
  final void Function(String nodeId, Map<String, dynamic> state)? onStateUpdate;
  
  QuantumInspiredStateSync({this.onStateUpdate}) {
    _startProcessing();
  }
  
  void registerNode(String nodeId, {
    Map<String, dynamic>? initialState,
    List<String>? connectedNodes,
  }) {
    // Initialize quantum state for node
    final stateVector = QuantumStateVector(_maxQubits);
    _nodeStates[nodeId] = stateVector;
    
    // Initialize entanglement connections
    _entanglementGraph[nodeId] = {};
    if (connectedNodes != null) {
      for (final connectedId in connectedNodes) {
        _entanglementGraph[nodeId]![connectedId] = 0.0;
      }
    }
    
    // Apply initial state if provided
    if (initialState != null) {
      _applyStateUpdate(nodeId, initialState);
    }
  }
  
  void unregisterNode(String nodeId) {
    _nodeStates.remove(nodeId);
    _entanglementGraph.remove(nodeId);
    
    // Remove references from other nodes
    for (final connections in _entanglementGraph.values) {
      connections.remove(nodeId);
    }
  }
  
  void updateNodeState(String nodeId, Map<String, dynamic> newState) {
    if (!_nodeStates.containsKey(nodeId)) {
      throw ArgumentError('Node $nodeId not registered');
    }
    
    _updateQueue.add(StateUpdate(
      nodeId: nodeId,
      state: newState,
      timestamp: DateTime.now(),
    ));
  }
  
  void _startProcessing() {
    _processingTimer = Timer.periodic(
      const Duration(milliseconds: 16), // 60Hz
      (_) => _processUpdates(),
    );
  }
  
  Future<void> _processUpdates() async {
    if (_isProcessing || _updateQueue.isEmpty) return;
    
    _isProcessing = true;
    
    try {
      final update = _updateQueue.removeFirst();
      await _applyStateUpdate(update.nodeId, update.state);
    } finally {
      _isProcessing = false;
    }
  }
  
  Future<void> _applyStateUpdate(
    String nodeId,
    Map<String, dynamic> newState,
  ) async {
    // Convert state to quantum representation
    final stateVector = _nodeStates[nodeId]!;
    _encodeStateToQuantum(stateVector, newState);
    
    // Process entanglement effects
    await _propagateEntanglement(nodeId);
    
    // Measure and update connected nodes
    await _measureAndUpdateNodes(nodeId);
  }
  
  void _encodeStateToQuantum(
    QuantumStateVector stateVector,
    Map<String, dynamic> classicalState,
  ) {
    // Apply quantum gates based on classical state
    final position = classicalState['position'] as Vector3;
    final rotation = classicalState['rotation'] as Vector3;
    
    // Encode position
    _applyPositionEncoding(stateVector, position);
    
    // Encode rotation
    _applyRotationEncoding(stateVector, rotation);
    
    // Encode additional state parameters
    if (classicalState.containsKey('velocity')) {
      _applyVelocityEncoding(stateVector, classicalState['velocity'] as Vector3);
    }
  }
  
  void _applyPositionEncoding(QuantumStateVector state, Vector3 position) {
    // Convert position to quantum gates
    final xGate = _createPositionGate(position.x);
    final yGate = _createPositionGate(position.y);
    final zGate = _createPositionGate(position.z);
    
    // Apply gates to specific qubits
    state.applyGate(xGate, [0, 1]);
    state.applyGate(yGate, [2, 3]);
    state.applyGate(zGate, [4, 5]);
  }
  
  void _applyRotationEncoding(QuantumStateVector state, Vector3 rotation) {
    // Convert rotation angles to quantum gates
    final pitchGate = _createRotationGate(rotation.x);
    final yawGate = _createRotationGate(rotation.y);
    final rollGate = _createRotationGate(rotation.z);
    
    // Apply gates to specific qubits
    state.applyGate(pitchGate, [6]);
    state.applyGate(yawGate, [7]);
    state.applyGate(rollGate, [8]);
  }
  
  void _applyVelocityEncoding(QuantumStateVector state, Vector3 velocity) {
    // Convert velocity to quantum phase shifts
    final speedGate = _createVelocityGate(velocity.length);
    final directionGate = _createDirectionGate(velocity);
    
    // Apply gates to specific qubits
    state.applyGate(speedGate, [9]);
    state.applyGate(directionGate, [0, 1, 2]);
  }
  
  List<List<Complex>> _createPositionGate(double value) {
    // Create a 4x4 quantum gate for position encoding
    final theta = value * math.pi;
    return [
      [Complex(math.cos(theta), 0), Complex(-math.sin(theta), 0),
       Complex(0, 0), Complex(0, 0)],
      [Complex(math.sin(theta), 0), Complex(math.cos(theta), 0),
       Complex(0, 0), Complex(0, 0)],
      [Complex(0, 0), Complex(0, 0),
       Complex(math.cos(theta), 0), Complex(-math.sin(theta), 0)],
      [Complex(0, 0), Complex(0, 0),
       Complex(math.sin(theta), 0), Complex(math.cos(theta), 0)],
    ];
  }
  
  List<List<Complex>> _createRotationGate(double angle) {
    // Create a 2x2 quantum gate for rotation encoding
    final theta = angle / 2;
    return [
      [Complex(math.cos(theta), 0), Complex(0, -math.sin(theta))],
      [Complex(0, math.sin(theta)), Complex(math.cos(theta), 0)],
    ];
  }
  
  List<List<Complex>> _createVelocityGate(double speed) {
    // Create a 2x2 quantum gate for velocity magnitude
    final phase = speed * math.pi / 10; // Normalize to reasonable range
    return [
      [Complex(1, 0), Complex(0, 0)],
      [Complex(0, 0), Complex(math.cos(phase), math.sin(phase))],
    ];
  }
  
  List<List<Complex>> _createDirectionGate(Vector3 direction) {
    // Create an 8x8 quantum gate for velocity direction
    final normalized = direction.normalized();
    final theta = math.acos(normalized.z);
    final phi = math.atan2(normalized.y, normalized.x);
    
    // Create a complex rotation matrix
    final gate = List.generate(
      8,
      (i) => List.generate(
        8,
        (j) => Complex(0, 0),
      ),
    );
    
    // Fill in rotation elements
    gate[0][0] = Complex(math.cos(theta/2), 0);
    gate[0][1] = Complex(-math.sin(theta/2) * math.cos(phi), 
                        -math.sin(theta/2) * math.sin(phi));
    gate[1][0] = Complex(math.sin(theta/2) * math.cos(phi),
                        math.sin(theta/2) * math.sin(phi));
    gate[1][1] = Complex(math.cos(theta/2), 0);
    
    return gate;
  }
  
  Future<void> _propagateEntanglement(String sourceNodeId) async {
    final sourceState = _nodeStates[sourceNodeId]!;
    final connections = _entanglementGraph[sourceNodeId]!;
    
    for (final entry in connections.entries) {
      final targetNodeId = entry.key;
      final entanglementStrength = entry.value;
      
      if (entanglementStrength >= _entanglementThreshold) {
        final targetState = _nodeStates[targetNodeId]!;
        
        // Create entangled state
        final entangledState = sourceState.clone();
        entangledState.entangle(targetState);
        
        // Update target node
        _nodeStates[targetNodeId] = entangledState;
        
        // Increase entanglement strength
        _entanglementGraph[sourceNodeId]![targetNodeId] = 
            (entanglementStrength + 0.1).clamp(0.0, 1.0);
      }
    }
  }
  
  Future<void> _measureAndUpdateNodes(String sourceNodeId) async {
    final affectedNodes = _findAffectedNodes(sourceNodeId);
    
    for (final nodeId in affectedNodes) {
      if (nodeId == sourceNodeId) continue;
      
      final state = _nodeStates[nodeId]!;
      final measurement = state.measure();
      
      // Convert quantum measurement to classical state
      final classicalState = _decodeQuantumState(measurement);
      
      // Notify listeners
      onStateUpdate?.call(nodeId, classicalState);
    }
  }
  
  Set<String> _findAffectedNodes(String sourceNodeId) {
    final affected = <String>{sourceNodeId};
    final queue = Queue<String>()..add(sourceNodeId);
    
    while (queue.isNotEmpty) {
      final nodeId = queue.removeFirst();
      final connections = _entanglementGraph[nodeId]!;
      
      for (final entry in connections.entries) {
        final targetId = entry.key;
        final strength = entry.value;
        
        if (strength >= _entanglementThreshold && !affected.contains(targetId)) {
          affected.add(targetId);
          queue.add(targetId);
        }
      }
    }
    
    return affected;
  }
  
  Map<String, dynamic> _decodeQuantumState(Map<String, dynamic> measurement) {
    final state = measurement['state'] as int;
    
    // Extract position (qubits 0-5)
    final position = Vector3(
      _decodePosition(state, 0),
      _decodePosition(state, 2),
      _decodePosition(state, 4),
    );
    
    // Extract rotation (qubits 6-8)
    final rotation = Vector3(
      _decodeRotation(state, 6),
      _decodeRotation(state, 7),
      _decodeRotation(state, 8),
    );
    
    // Extract velocity if encoded (qubit 9)
    final hasVelocity = (state >> 9) & 1 == 1;
    final velocity = hasVelocity ? _decodeVelocity(state) : null;
    
    return {
      'position': position,
      'rotation': rotation,
      if (velocity != null) 'velocity': velocity,
      'confidence': measurement['probability'],
    };
  }
  
  double _decodePosition(int state, int startQubit) {
    final bits = (state >> startQubit) & 3; // Get 2 qubits
    return (bits / 3) * 2 - 1; // Map to [-1, 1]
  }
  
  double _decodeRotation(int state, int qubit) {
    return ((state >> qubit) & 1) * math.pi; // Map to [0, π]
  }
  
  Vector3? _decodeVelocity(int state) {
    if ((state >> 9) & 1 == 0) return null;
    
    // Decode speed and direction from quantum state
    final speedBits = (state >> 10) & 7;
    final speed = speedBits / 7; // Normalize to [0, 1]
    
    // Calculate direction vector
    final theta = ((state >> 13) & 3) * math.pi / 2;
    final phi = ((state >> 15) & 3) * math.pi / 2;
    
    return Vector3(
      speed * math.sin(theta) * math.cos(phi),
      speed * math.sin(theta) * math.sin(phi),
      speed * math.cos(theta),
    );
  }
  
  void dispose() {
    _processingTimer?.cancel();
    _nodeStates.clear();
    _entanglementGraph.clear();
    _updateQueue.clear();
  }
}

class StateUpdate {
  final String nodeId;
  final Map<String, dynamic> state;
  final DateTime timestamp;
  
  StateUpdate({
    required this.nodeId,
    required this.state,
    required this.timestamp,
  });
}