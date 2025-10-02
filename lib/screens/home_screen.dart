import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_theme.dart';
import '../services/ar_service.dart';
import '../services/mesh_network_service.dart';
import '../services/analytics_service.dart';
import '../services/monetization_service.dart';
import '../services/blockchain_service.dart';
import '../widgets/anchor_details_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/ar_view.dart';
import '../providers/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final _arViewController = ARViewController();
  late final AnalyticsService _analytics;
  late final MeshNetworkService _meshService;
  late final MonetizationService _monetizationService;
  late final BlockchainService _blockchainService;
  bool _hasPermissions = false;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _analytics = ref.read(analyticsProvider);
    _meshService = ref.read(meshNetworkProvider);
    _monetizationService = ref.read(monetizationProvider);
    _blockchainService = ref.read(blockchainProvider);
    _initializeServices();
  }
  
  Future<void> _initializeServices() async {
    if (_isInitialized) return;
    
    try {
      // Check and request permissions
      final permissions = await _checkPermissions();
      if (!permissions) {
        _showPermissionDeniedDialog();
        return;
      }
      
      // Initialize AR view controller
      await _arViewController.initialize();
      
      // Start mesh network discovery
      await _meshService.startDiscovery();
      
      // Initialize blockchain connection
      await _blockchainService.ensureConnection();
      
      _isInitialized = true;
      _analytics.trackEvent('home_screen_initialized', {
        'has_permissions': _hasPermissions,
        'mesh_peers': _meshService.connectedPeers.length,
      });
    } catch (e) {
      _analytics.trackEvent('home_screen_init_error', {'error': e.toString()});
      _showErrorDialog('Initialization Error', e.toString());
    }
  }
  
  Future<bool> _checkPermissions() async {
    final camera = await Permission.camera.request();
    final location = await Permission.location.request();
    final bluetooth = await Permission.bluetoothScan.request();
    
    _hasPermissions = camera.isGranted && location.isGranted && bluetooth.isGranted;
    return _hasPermissions;
  }
  
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Permissions Required'),
        content: Text(
          'SpatialMesh AR needs camera, location, and Bluetooth permissions to function. '
          'Please grant these permissions in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => openAppSettings(),
            child: Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => context.go('/welcome'),
            child: Text('Exit'),
          ),
        ],
      ),
    );
  }
  
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // AR View
            Positioned.fill(
              child: ARView(
                controller: _arViewController,
                onAnchorTapped: _handleAnchorTap,
                onPlaneDetected: _handlePlaneDetection,
              ),
            ),
            
            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(theme),
            ),
            
            // Mesh Network Status
            Positioned(
              top: kToolbarHeight + 8,
              right: 16,
              child: _buildMeshStatus(theme),
            ),
            
            // Earnings Display
            if (!isLandscape) _buildEarningsDisplay(theme),
            
            // Action Buttons
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _buildActionButtons(theme),
            ),
            
            // Loading Indicator
            if (!_isInitialized)
              Container(
                color: Colors.black54,
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTopBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface.withOpacity(0.9),
            theme.colorScheme.surface.withOpacity(0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.menu),
            onPressed: () => _openSettings(),
          ),
          Text(
            'SpatialMesh AR',
            style: theme.textTheme.titleLarge,
          ),
          IconButton(
            icon: Icon(Icons.account_circle),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMeshStatus(ThemeData theme) {
    return Consumer(
      builder: (context, ref, _) {
        final meshState = ref.watch(meshStateProvider);
        final peers = meshState.connectedPeers;
        
        return Card(
          elevation: AppTheme.elevationLow,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.device_hub,
                  color: peers.isEmpty
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                SizedBox(width: 8),
                Text(
                  '${peers.length} Peers',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildEarningsDisplay(ThemeData theme) {
    return Positioned(
      top: kToolbarHeight + 8,
      left: 16,
      child: Consumer(
        builder: (context, ref, _) {
          final earnings = ref.watch(earningsProvider);
          
          return Card(
            elevation: AppTheme.elevationLow,
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppTheme.earningsGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Earnings',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '\$${earnings.totalEarnings.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FloatingActionButton(
          heroTag: 'scan',
          onPressed: _scanForAnchors,
          child: Icon(Icons.search),
          tooltip: 'Scan for Anchors',
        ),
        FloatingActionButton.large(
          heroTag: 'create',
          onPressed: _createAnchor,
          child: Icon(Icons.add),
          tooltip: 'Create Anchor',
        ),
        FloatingActionButton(
          heroTag: 'list',
          onPressed: () => context.push('/anchors'),
          child: Icon(Icons.list),
          tooltip: 'View Anchors',
        ),
      ],
    );
  }
  
  Future<void> _handleAnchorTap(String anchorId) async {
    _analytics.trackEvent('anchor_tapped', {'anchor_id': anchorId});
    
    final anchor = await _arViewController.getAnchorDetails(anchorId);
    if (anchor == null) return;
    
    showModalBottomSheet(
      context: context,
      builder: (context) => AnchorDetailsSheet(anchor: anchor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }
  
  Future<void> _handlePlaneDetection(Plane plane) async {
    _analytics.trackEvent('plane_detected', {
      'center': [plane.center.x, plane.center.y, plane.center.z],
      'extent': [plane.extentX, plane.extentZ],
    });
  }
  
  Future<void> _scanForAnchors() async {
    try {
      final anchors = await _arViewController.scanForAnchors();
      _analytics.trackEvent('anchor_scan', {
        'anchors_found': anchors.length,
      });
    } catch (e) {
      _analytics.trackEvent('anchor_scan_error', {'error': e.toString()});
      _showErrorDialog('Scan Error', 'Failed to scan for anchors: ${e.toString()}');
    }
  }
  
  Future<void> _createAnchor() async {
    try {
      final position = await _arViewController.getCurrentPosition();
      if (position == null) {
        _showErrorDialog('Creation Error', 'Unable to determine position');
        return;
      }
      
      final anchor = await _arViewController.createAnchor(position);
      _analytics.trackEvent('anchor_created', {
        'anchor_id': anchor.id,
        'position': [position.x, position.y, position.z],
      });
      
      // Start monetization for the new anchor
      await _monetizationService.startMonetization(anchor.id);
      
    } catch (e) {
      _analytics.trackEvent('anchor_creation_error', {'error': e.toString()});
      _showErrorDialog('Creation Error', 'Failed to create anchor: ${e.toString()}');
    }
  }
  
  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SettingsSheet(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    );
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _arViewController.resume();
        _meshService.startDiscovery();
        break;
      case AppLifecycleState.paused:
        _arViewController.pause();
        _meshService.stopDiscovery();
        break;
      default:
        break;
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arViewController.dispose();
    super.dispose();
  }
}
