import 'package:flutter/material.dart';
import 'package:ar_core/ar_core.dart';
import 'package:vector_math/vector_math_64.dart';
import '../services/mesh_generation_service.dart';
import '../core/app_theme.dart';

class ARMeshView extends StatefulWidget {
  final void Function(String meshId)? onMeshGenerated;
  final void Function(Vector3 position)? onPositionSelected;

  const ARMeshView({
    Key? key,
    this.onMeshGenerated,
    this.onPositionSelected,
  }) : super(key: key);

  @override
  State<ARMeshView> createState() => _ARMeshViewState();
}

class _ARMeshViewState extends State<ARMeshView> with WidgetsBindingObserver {
  late final MeshGenerationService _meshService;
  late final ARViewController _arViewController;
  
  bool _isProcessing = false;
  bool _showPointCloud = true;
  bool _showWireframe = false;
  double _confidence = 0.85;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAR();
  }

  Future<void> _setupAR() async {
    _meshService = MeshGenerationService();
    await _meshService.initialize();

    _meshService.pointCloudStream.listen(_updatePointCloud);
    _meshService.meshStream.listen(_updateMesh);
  }

  void _updatePointCloud(List<Vector3> points) {
    if (!mounted) return;
    _arViewController.updatePointCloud(points);
  }

  void _updateMesh(Mesh mesh) {
    if (!mounted) return;
    _arViewController.updateMesh(
      mesh,
      showWireframe: _showWireframe,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ARView(
          onViewCreated: (ARViewController controller) {
            _arViewController = controller;
          },
          onPlaneDetected: _handlePlaneDetection,
          onTap: _handleTap,
        ),
        _buildControls(),
        if (_isProcessing) _buildProcessingIndicator(),
      ],
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildControlCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildToggleButton(
                    icon: Icons.cloud_outlined,
                    label: 'Point Cloud',
                    value: _showPointCloud,
                    onChanged: _togglePointCloud,
                  ),
                  SizedBox(height: 8),
                  _buildToggleButton(
                    icon: Icons.grid_on,
                    label: 'Wireframe',
                    value: _showWireframe,
                    onChanged: _toggleWireframe,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Confidence: ${(_confidence * 100).toInt()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                  Slider(
                    value: _confidence,
                    min: 0.5,
                    max: 1.0,
                    divisions: 10,
                    label: '${(_confidence * 100).toInt()}%',
                    onChanged: _updateConfidence,
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            _buildControlCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    icon: Icons.refresh,
                    label: 'Reset',
                    onPressed: _resetMesh,
                  ),
                  SizedBox(height: 8),
                  _buildActionButton(
                    icon: Icons.save,
                    label: 'Save Mesh',
                    onPressed: _saveMesh,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({required Widget child}) {
    return Card(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: child,
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8.0,
          vertical: 4.0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.5),
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: value
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        minimumSize: Size(120, 40),
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Processing Mesh...',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _togglePointCloud(bool value) {
    setState(() {
      _showPointCloud = value;
      _arViewController.setPointCloudVisible(value);
    });
  }

  void _toggleWireframe(bool value) {
    setState(() {
      _showWireframe = value;
      _arViewController.setWireframeVisible(value);
    });
  }

  void _updateConfidence(double value) {
    setState(() {
      _confidence = value;
      // Update confidence in mesh service
    });
  }

  Future<void> _resetMesh() async {
    setState(() => _isProcessing = true);
    try {
      await _meshService.clearMesh();
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveMesh() async {
    setState(() => _isProcessing = true);
    try {
      final meshId = DateTime.now().millisecondsSinceEpoch.toString();
      await _meshService.saveMesh(meshId);
      widget.onMeshGenerated?.call(meshId);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _handlePlaneDetection(ARPlane plane) {
    // Handle detected planes for mesh alignment
  }

  void _handleTap(ARHitTestResult hitTestResult) {
    widget.onPositionSelected?.call(hitTestResult.worldTransform.getTranslation());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _arViewController.pause();
        break;
      case AppLifecycleState.resumed:
        _arViewController.resume();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _meshService.dispose();
    _arViewController.dispose();
    super.dispose();
  }
}