import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';
import '../services/spatial_understanding_service.dart';
import '../core/app_theme.dart';

class SpatialVisualizationView extends StatefulWidget {
  final void Function(DetectedObject object)? onObjectSelected;
  final void Function(SpatialPlane plane)? onPlaneSelected;
  final bool showDebugInfo;

  const SpatialVisualizationView({
    Key? key,
    this.onObjectSelected,
    this.onPlaneSelected,
    this.showDebugInfo = false,
  }) : super(key: key);

  @override
  State<SpatialVisualizationView> createState() => _SpatialVisualizationViewState();
}

class _SpatialVisualizationViewState extends State<SpatialVisualizationView> {
  late final SpatialUnderstandingService _spatialService;
  final ValueNotifier<List<DetectedObject>> _objects = ValueNotifier([]);
  final ValueNotifier<SceneUnderstanding?> _scene = ValueNotifier(null);
  final ValueNotifier<List<SpatialPlane>> _planes = ValueNotifier([]);

  @override
  void initState() {
    super.initState();
    _initializeSpatialService();
  }

  Future<void> _initializeSpatialService() async {
    _spatialService = SpatialUnderstandingService();
    await _spatialService.initialize();

    // Subscribe to updates
    _spatialService.objectStream.listen((objects) {
      _objects.value = objects;
    });

    _spatialService.sceneStream.listen((scene) {
      _scene.value = scene;
    });

    _spatialService.planeStream.listen((planes) {
      _planes.value = planes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main AR view from camera
        Positioned.fill(
          child: _buildARView(),
        ),
        
        // Object detection overlays
        ValueListenableBuilder<List<DetectedObject>>(
          valueListenable: _objects,
          builder: (context, objects, _) {
            return CustomPaint(
              painter: ObjectDetectionPainter(
                objects: objects,
                showDebugInfo: widget.showDebugInfo,
              ),
            );
          },
        ),

        // Plane visualization
        ValueListenableBuilder<List<SpatialPlane>>(
          valueListenable: _planes,
          builder: (context, planes, _) {
            return CustomPaint(
              painter: PlanePainter(
                planes: planes,
                showDebugInfo: widget.showDebugInfo,
              ),
            );
          },
        ),

        // Scene information overlay
        if (widget.showDebugInfo)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildSceneInfoOverlay(),
          ),

        // Object selection interface
        Positioned.fill(
          child: GestureDetector(
            onTapDown: _handleTap,
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildARView() {
    // This would be replaced with actual camera preview and AR rendering
    return Container(
      color: Colors.black,
      child: Center(
        child: Text(
          'AR View',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSceneInfoOverlay() {
    return ValueListenableBuilder<SceneUnderstanding?>(
      valueListenable: _scene,
      builder: (context, scene, _) {
        if (scene == null) return SizedBox.shrink();

        return Container(
          padding: EdgeInsets.all(16),
          color: Colors.black54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scene Context: ${scene.contextLabels.join(", ")}',
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'Confidence: ${(scene.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.white),
              ),
              if (scene.lighting != null) ...[
                SizedBox(height: 8),
                Text(
                  'Lighting: ${_formatLighting(scene.lighting!)}',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatLighting(LightingConditions lighting) {
    return 'Main Light: ${lighting.mainLightIntensity.toStringAsFixed(2)} lux, '
           'Ambient: ${lighting.ambientIntensity.toStringAsFixed(2)} lux';
  }

  void _handleTap(TapDownDetails details) {
    // Convert tap position to AR space coordinates
    final position = _convertToARSpace(details.localPosition);

    // Check for object selection
    final tappedObject = _findObjectAtPosition(position);
    if (tappedObject != null) {
      widget.onObjectSelected?.call(tappedObject);
      return;
    }

    // Check for plane selection
    final tappedPlane = _findPlaneAtPosition(position);
    if (tappedPlane != null) {
      widget.onPlaneSelected?.call(tappedPlane);
    }
  }

  Vector3 _convertToARSpace(Offset position) {
    // Convert screen coordinates to AR space
    // This would use actual AR SDK conversion
    return Vector3(position.dx, position.dy, 0);
  }

  DetectedObject? _findObjectAtPosition(Vector3 position) {
    // Find object containing the tap position
    return _objects.value.firstWhere(
      (obj) => _isPointInObject(position, obj),
      orElse: () => null as DetectedObject,
    );
  }

  bool _isPointInObject(Vector3 position, DetectedObject object) {
    return object.boundingBox.contains(Offset(position.x, position.y));
  }

  SpatialPlane? _findPlaneAtPosition(Vector3 position) {
    // Find nearest plane to tap position
    return _planes.value.firstWhere(
      (plane) => _isPointOnPlane(position, plane),
      orElse: () => null as SpatialPlane,
    );
  }

  bool _isPointOnPlane(Vector3 position, SpatialPlane plane) {
    // Calculate if point is on plane using plane equation
    final toPoint = position - plane.center;
    final distance = toPoint.dot(plane.normal).abs();
    return distance < 0.1; // 10cm threshold
  }

  @override
  void dispose() {
    _spatialService.dispose();
    super.dispose();
  }
}

class ObjectDetectionPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final bool showDebugInfo;

  ObjectDetectionPainter({
    required this.objects,
    required this.showDebugInfo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.green;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final object in objects) {
      // Draw bounding box
      canvas.drawRect(object.boundingBox, paint);

      if (showDebugInfo) {
        // Draw label
        textPainter.text = TextSpan(
          text: '${object.label} (${(object.confidence * 100).toStringAsFixed(1)}%)',
          style: TextStyle(
            color: Colors.white,
            backgroundColor: Colors.black54,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          object.boundingBox.topLeft + Offset(0, -20),
        );
      }
    }
  }

  @override
  bool shouldRepaint(ObjectDetectionPainter oldDelegate) {
    return objects != oldDelegate.objects;
  }
}

class PlanePainter extends CustomPainter {
  final List<SpatialPlane> planes;
  final bool showDebugInfo;

  PlanePainter({
    required this.planes,
    required this.showDebugInfo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blue.withOpacity(0.3);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.blue;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final plane in planes) {
      // Convert plane to screen space and draw
      final rect = Rect.fromCenter(
        center: Offset(plane.center.x, plane.center.y),
        width: plane.extent.x,
        height: plane.extent.y,
      );

      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);

      if (showDebugInfo && plane.semanticLabel != null) {
        textPainter.text = TextSpan(
          text: plane.semanticLabel,
          style: TextStyle(
            color: Colors.white,
            backgroundColor: Colors.black54,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          rect.topCenter + Offset(-textPainter.width / 2, -24),
        );
      }
    }
  }

  @override
  bool shouldRepaint(PlanePainter oldDelegate) {
    return planes != oldDelegate.planes;
  }
}