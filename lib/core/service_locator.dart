import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../services/ar_service.dart';
import '../services/mesh_network_service.dart';
import '../services/permissions_service.dart';
import '../services/analytics_service.dart';
import '../services/monetization_service.dart';
import '../services/ai_service.dart';
import '../services/aws_service.dart';
import '../services/blockchain_service.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> setupServiceLocator() async {
  // Initialize AWS service first
  getIt.registerSingleton<AWSService>(AWSService());
  await getIt<AWSService>().initialize();
  
  // Register core services
  getIt.registerSingleton<PermissionsService>(PermissionsService());
  getIt.registerSingleton<AnalyticsService>(AnalyticsService());
  getIt.registerSingleton<MeshNetworkService>(MeshNetworkService());
  getIt.registerSingleton<ARService>(ARService());
  getIt.registerSingleton<MonetizationService>(MonetizationService());
  getIt.registerSingleton<AIService>(AIService());
  getIt.registerSingleton<BlockchainService>(BlockchainService());
  
  // Initialize services in dependency order
  await getIt<PermissionsService>().initialize();
  await getIt<AnalyticsService>().initialize();
  await getIt<MeshNetworkService>().initialize();
  await getIt<ARService>().initialize();
  await getIt<MonetizationService>().initialize();
  await getIt<AIService>().initialize();
  await getIt<BlockchainService>().initialize();
  
  print('✅ All services initialized successfully');
}