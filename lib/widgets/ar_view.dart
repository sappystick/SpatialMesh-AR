import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ar_service.dart';
import '../services/analytics_service.dart';
import '../models/spatial_anchor.dart';
import '../core/app_theme.dart';

class ARView extends ConsumerStatefulWidget {
  final ARViewController controller;
  final Function(String) onAnchorTapped;
  final Function(Plane) onPlaneDetected;

  const ARView({
    Key? key,
    required this.controller,
    required this.onAnchorTapped,
    required this.onPlaneDetected,
  }) : super(key: key);

  @override
  ConsumerState<ARView> createState() => _ARViewState();
}

class _ARViewState extends ConsumerState<ARView> with WidgetsBindingObserver {
  bool _isARReady = false;
  bool _isProcessingTap = false;
  List<SpatialAnchor> _visibleAnchors = [];

  late final ARService _arService;
  late final AnalyticsService _analytics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arService = ref.read(arServiceProvider);
    _analytics = ref.read(analyticsProvider);
    _initializeAR();
  }

  Future<void> _initializeAR() async {
    try {
      await widget.controller.initialize();
      
      // Set up AR scene configurations
      await widget.controller.setConfiguration(
        planeFindingMode: PlaneFindingMode.horizontal,
        updateMode: UpdateMode.continuous,
        lightEstimationMode: LightEstimationMode.environmentalHDR,
      );
      
      // Set up AR callbacks
      widget.controller.onPlaneDetected = _handlePlaneDetected;
      widget.controller.onAnchorUpdated = _handleAnchorUpdated;
      widget.controller.onTrackingChanged = _handleTrackingChanged;
      
      setState(() => _isARReady = true);
      
      _analytics.trackEvent('ar_view_initialized', {
        'tracking_state': widget.controller.trackingState.toString(),
      });
    } catch (e) {
      _analytics.trackEvent('ar_view_init_error', {'error': e.toString()});
      print('❌ AR initialization failed: $e');
    }
  }

  void _handlePlaneDetected(Plane plane) {
    widget.onPlaneDetected(plane);
    
    _analytics.trackEvent('plane_detected', {
      'center': [plane.center.x, plane.center.y, plane.center.z],
      'extent': [plane.extentX, plane.extentZ],
    });
  }

  void _handleAnchorUpdated(
    String anchorId,
    Matrix4 transform,
    TrackingState trackingState,
  ) {
    final anchor = _visibleAnchors.firstWhere(
      (a) => a.id == anchorId,
      orElse: () => null,
    );

    if (anchor != null) {
      setState(() {
        anchor.transform = transform;
        anchor.trackingState = trackingState;
      });

      _analytics.trackEvent('anchor_updated', {
        'anchor_id': anchorId,
        'tracking_state': trackingState.toString(),
      });
    }
  }

  void _handleTrackingChanged(TrackingState state) {
    setState(() {
      // Update UI based on tracking state
    });

    _analytics.trackEvent('tracking_changed', {
      'state': state.toString(),
    });
  }

  void _handleTap(TapUpDetails details) async {
    if (!_isARReady || _isProcessingTap) return;

    try {
      setState(() => _isProcessingTap = true);

      final hitResult = await widget.controller.hitTest(
        details.globalPosition.dx,
        details.globalPosition.dy,
      );

      if (hitResult != null) {
        if (hitResult.type == HitType.anchor) {
          widget.onAnchorTapped(hitResult.anchor!.id);
        } else if (hitResult.type == HitType.plane) {
          // Visualize tap point for potential anchor creation
          await widget.controller.addSphere(
            position: hitResult.position!,
            radius: 0.02,
            color: AppTheme.arAnchorColor,
          );
        }
      }

      _analytics.trackEvent('ar_view_tapped', {
        'hit_type': hitResult?.type.toString() ?? 'none',
        'position': hitResult?.position?.toString(),
      });
    } catch (e) {
      _analytics.trackEvent('ar_view_tap_error', {'error': e.toString()});
    } finally {
      setState(() => _isProcessingTap = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isARReady) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        // AR View
        GestureDetector(
          onTapUp: _handleTap,
          child: ArCoreView(
            controller: widget.controller,
            enableTapRecognizer: true,
            enableUpdateListener: true,
            enablePlaneRenderer: true,
          ),
        ),

        // Tracking State Indicator
        if (widget.controller.trackingState != TrackingState.tracking)
          Container(
            color: Colors.black54,
            child: Center(
              child: Text(
                _getTrackingStateMessage(widget.controller.trackingState),
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // Debug Info (if enabled)
        if (_arService.debugMode)
          Positioned(
            top: 100,
            left: 16,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug Info:',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'FPS: ${widget.controller.fps.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Anchors: ${_visibleAnchors.length}',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _getTrackingStateMessage(TrackingState state) {
    switch (state) {
      case TrackingState.paused:
        return 'AR tracking paused.\nMove device slowly.';
      case TrackingState.stopped:
        return 'AR tracking stopped.\nInsufficient features.';
      case TrackingState.limited:
        return 'Limited tracking quality.\nCheck lighting and device movement.';
      default:
        return '';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resumeAR();
        break;
      case AppLifecycleState.paused:
        _pauseAR();
        break;
      default:
        break;
    }
  }

  Future<void> _resumeAR() async {
    try {
      await widget.controller.resume();
      _analytics.trackEvent('ar_view_resumed', {});
    } catch (e) {
      _analytics.trackEvent('ar_view_resume_error', {'error': e.toString()});
    }
  }

  Future<void> _pauseAR() async {
    try {
      await widget.controller.pause();
      _analytics.trackEvent('ar_view_paused', {});
    } catch (e) {
      _analytics.trackEvent('ar_view_pause_error', {'error': e.toString()});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}