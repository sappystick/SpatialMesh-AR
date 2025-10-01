import 'package:injectable/injectable.dart';
import 'package:webrtc_interface/webrtc_interface.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'dart:convert';

import '../core/app_config.dart';
import '../models/mesh_session.dart';
import 'aws_service.dart';
import 'analytics_service.dart';
import '../core/service_locator.dart';

@singleton
class MeshNetworkService {
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, MeshSession> _sessions = {};
  
  // Advanced mesh networking
  late MeshNetworkProtocol _meshProtocol;
  late QoSManager _qosManager;
  
  bool _isInitialized = false;
  Function(String deviceId, Map<String, dynamic> data)? onDataReceived;
  Function(String deviceId)? onPeerConnected;
  Function(String deviceId)? onPeerDisconnected;
  
  bool get isInitialized => _isInitialized;
  List<String> get connectedPeers => _peers.keys.toList();
  int get peerCount => _peers.length;
  
  Future<void> initialize() async {
    try {
      // Initialize mesh protocol with IEEE 802.11s standards
      _meshProtocol = MeshNetworkProtocol(
        maxHops: 5,
        enableSelfHealing: true,
        routingProtocol: RoutingProtocol.OLSR,
        maxNodes: AppConfig.maxMeshNodes,
      );
      
      _qosManager = QoSManager(
        priorityLevels: ['critical', 'high', 'normal', 'low'],
        bandwidthManagement: true,
        adaptiveRouting: true,
      );
      
      // WebRTC configuration with STUN servers
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
        ],
        'iceCandidatePoolSize': 10,
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
      };
      
      _isInitialized = true;
      safePrint('✅ Mesh Network Service initialized successfully');
      
      // Start peer discovery
      await startPeerDiscovery();
      
    } catch (e) {
      safePrint('❌ Mesh Network Service initialization failed: $e');
      rethrow;
    }
  }
  
  Future<void> startPeerDiscovery() async {
    if (!_isInitialized) {
      throw StateError('Mesh Network Service not initialized');
    }
    
    try {
      // Use Nearby Connections for local peer discovery
      await Nearby().startAdvertising(
        'SpatialMesh',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: 'com.spatialmesh.ar.mesh',
      );
      
      await Nearby().startDiscovery(
        'SpatialMesh',
        Strategy.P2P_CLUSTER,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: 'com.spatialmesh.ar.mesh',
      );
      
      safePrint('🔍 Peer discovery started');
    } catch (e) {
      safePrint('❌ Peer discovery failed: $e');
    }
  }
  
  Future<MeshSession> createSession(String sessionId, List<String> participants) async {
    final session = MeshSession(
      id: sessionId,
      participants: participants,
      createdAt: DateTime.now(),
      status: 'active',
      spatialData: {},
    );
    
    _sessions[sessionId] = session;
    
    // Store session in AWS DynamoDB
    final awsService = getIt<AWSService>();
    // TODO: Create session in DynamoDB via API
    
    return session;
  }
  
  Future<void> broadcastSpatialData(Map<String, dynamic> data) async {
    final packet = SpatialDataPacket(
      id: _generateUniqueId(),
      type: data['type'] ?? 'generic',
      data: data,
      timestamp: DateTime.now(),
      priority: data['priority'] ?? 'normal',
    );
    
    // Use QoS manager for optimized delivery
    final optimizedRoute = await _meshProtocol.calculateOptimalRoute(
      packet.destination ?? 'broadcast',
      packet.priority,
    );
    
    for (final peerId in optimizedRoute) {
      final channel = _dataChannels[peerId];
      if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        await _qosManager.sendWithQoS(channel!, packet, packet.priority);
      }
    }
  }
  
  void _onConnectionInitiated(String id, ConnectionInfo info) {
    safePrint('🔗 Connection initiated with: $id');
  }
  
  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      onPeerConnected?.call(id);
      _setupPeerConnection(id);
    } else {
      onPeerDisconnected?.call(id);
    }
  }
  
  void _onDisconnected(String id) {
    _peers.remove(id);
    _dataChannels.remove(id);
    onPeerDisconnected?.call(id);
    safePrint('🔌 Peer disconnected: $id');
  }
  
  void _onEndpointFound(String id, String name, String serviceId) {
    safePrint('📍 Endpoint found: $id - $name');
    Nearby().requestConnection(
      'SpatialMesh',
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }
  
  void _onEndpointLost(String id) {
    safePrint('📋 Endpoint lost: $id');
  }
  
  Future<void> _setupPeerConnection(String peerId) async {
    // Setup WebRTC peer connection for high-bandwidth data
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    
    final peerConnection = await createPeerConnection(configuration);
    _peers[peerId] = peerConnection;
    
    // Create data channel
    final dataChannel = await peerConnection.createDataChannel(
      'spatial_data',
      RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 3,
    );
    
    _dataChannels[peerId] = dataChannel;
    
    dataChannel.onMessage = (message) {
      try {
        final data = json.decode(message.text);
        onDataReceived?.call(peerId, data);
      } catch (e) {
        safePrint('❌ Failed to parse mesh message: $e');
      }
    };
  }
  
  String _generateUniqueId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }
  
  Future<void> dispose() async {
    await Nearby().stopAllEndpoints();
    
    for (final connection in _peers.values) {
      await connection.close();
    }
    
    _peers.clear();
    _dataChannels.clear();
    _sessions.clear();
    
    safePrint('🔌 Mesh network service disposed');
  }
}

class MeshNetworkProtocol {
  final int maxHops;
  final bool enableSelfHealing;
  final RoutingProtocol routingProtocol;
  final int maxNodes;
  
  MeshNetworkProtocol({
    required this.maxHops,
    required this.enableSelfHealing,
    required this.routingProtocol,
    required this.maxNodes,
  });
  
  Future<List<String>> calculateOptimalRoute(String destination, String priority) async {
    // Implement OLSR routing algorithm
    return []; // Placeholder
  }
}

class QoSManager {
  final List<String> priorityLevels;
  final bool bandwidthManagement;
  final bool adaptiveRouting;
  
  QoSManager({
    required this.priorityLevels,
    required this.bandwidthManagement,
    required this.adaptiveRouting,
  });
  
  Future<void> sendWithQoS(RTCDataChannel channel, SpatialDataPacket packet, String priority) async {
    // Implement QoS-aware message sending
    final message = json.encode(packet.toJson());
    await channel.send(RTCDataChannelMessage(message));
  }
}

class SpatialDataPacket {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String priority;
  final String? destination;
  
  SpatialDataPacket({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    required this.priority,
    this.destination,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'priority': priority,
    'destination': destination,
  };
}

enum RoutingProtocol { OLSR, AODV, BATMAN }
enum Status { CONNECTED, DISCONNECTED, ERROR }