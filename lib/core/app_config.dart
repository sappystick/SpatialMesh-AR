class AppConfig {
  static const String appName = 'SpatialMesh AR';
  static const String appVersion = '0.1.0';
  static const String buildNumber = '1';
  
  // Environment Configuration
  static const bool isProduction = bool.fromEnvironment('PRODUCTION', defaultValue: false);
  static const bool enableDebugMode = !isProduction;
  
  // AWS Configuration  
  static const String awsRegion = 'us-west-2';
  static const String s3BucketName = String.fromEnvironment('S3_BUCKET_NAME', defaultValue: 'spatialmesh-ar-storage');
  
  // AR Configuration
  static int get maxConcurrentUsers => isProduction ? 1000 : 5;
  static bool get enableCloudAnchors => isProduction;
  static const double arTrackingAccuracyThreshold = 0.95;
  static const int maxSpatialAnchors = 1000;
  
  // Mesh Network Configuration
  static int get maxMeshNodes => isProduction ? 100 : 8;
  static const int meshDiscoveryTimeoutMs = 10000;
  static const int maxPeerConnections = 16;
  
  // Monetization Configuration
  static const double platformCommissionRate = 0.06;
  static const int minimumPayoutCents = 100; // $1.00
  
  // AI/ML Configuration
  static bool get enableAdvancedAI => isProduction;
  static const double mlModelAccuracyThreshold = 0.90;
  
  // Performance Configuration
  static const int maxCacheSize = 100 * 1024 * 1024; // 100MB
  static const int networkTimeoutSeconds = 30;
  static const int maxRetryAttempts = 3;
  
  // Revenue Targets
  static const Map<String, double> earningRates = {
    'spatial_anchor': 0.05,
    'mesh_participation': 0.02,
    'ai_processing': 0.08,
    'collaboration': 0.03,
    'content_creation': 0.10,
  };
}