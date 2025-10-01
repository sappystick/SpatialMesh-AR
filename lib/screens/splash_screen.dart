import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../core/app_config.dart';
import '../core/service_locator.dart';
import 'home_screen.dart';
import 'auth_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  String _initializationStatus = 'Initializing SpatialMesh AR...';
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }
  
  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeInOut),
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));
    
    _animationController.forward();
  }
  
  Future<void> _initializeApp() async {
    try {
      // Phase 1: Check services
      setState(() {
        _initializationStatus = 'Checking AWS services...';
      });
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Phase 2: Initialize core services
      setState(() {
        _initializationStatus = 'Initializing AR engine...';
      });
      
      // Verify all services are working
      final awsService = getIt<AWSService>();
      if (!awsService.isInitialized) {
        throw Exception('AWS Service not initialized');
      }
      
      await Future.delayed(const Duration(milliseconds: 800));
      
      setState(() {
        _initializationStatus = 'Starting mesh network...';
      });
      await Future.delayed(const Duration(milliseconds: 600));
      
      setState(() {
        _initializationStatus = 'Loading spatial intelligence...';
      });
      await Future.delayed(const Duration(milliseconds: 700));
      
      setState(() {
        _initializationStatus = 'Connecting to network...';
      });
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Phase 3: Check authentication
      setState(() {
        _initializationStatus = 'Verifying authentication...';
      });
      
      final isSignedIn = await _checkAuthStatus();
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        if (isSignedIn) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializationStatus = 'Initialization failed: ${e.toString()}';
        });
        
        // Show error dialog after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _showErrorDialog(e.toString());
          }
        });
      }
    }
  }
  
  Future<bool> _checkAuthStatus() async {
    try {
      final result = await Amplify.Auth.fetchAuthSession();
      return result.isSignedIn;
    } catch (e) {
      return false;
    }
  }
  
  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initialization Error'),
        content: Text('Failed to initialize SpatialMesh AR:\n\n$error\n\nPlease check your configuration and try again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _initializeApp(); // Retry
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6750A4),
              Color(0xFF7C4DFF),
              Color(0xFF3F51B5),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // AR Icon with glow effect
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.view_in_ar,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // App name with style
                    Text(
                      AppConfig.appName,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Tagline
                    Text(
                      'Infrastructure-Free Spatial Computing',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Earn \$58-180 Daily Through AR Collaboration',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.greenAccent.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    
                    const SizedBox(height: 50),
                    
                    // Loading indicator
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 3,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Status text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _initializationStatus,
                        key: ValueKey<String>(_initializationStatus),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Version info
                    Text(
                      'Version ${AppConfig.appVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}