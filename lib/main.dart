import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_datastore/amplify_datastore.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

import 'core/app_config.dart';
import 'core/service_locator.dart';
import 'core/app_theme.dart';
import 'screens/splash_screen.dart';
import 'amplifyconfiguration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure Amplify
  await _configureAmplify();
  
  // Setup dependency injection
  await setupServiceLocator();
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const ProviderScope(child: SpatialMeshApp()));
}

Future<void> _configureAmplify() async {
  try {
    // Add Amplify plugins
    final auth = AmplifyAuthCognito();
    final api = AmplifyAPI();
    final dataStore = AmplifyDataStore();
    final storage = AmplifyStorageS3();
    
    await Amplify.addPlugins([auth, api, dataStore, storage]);
    
    // Configure Amplify
    await Amplify.configure(amplifyconfig);
    
    safePrint('✅ Amplify configured successfully');
  } catch (e) {
    safePrint('❌ Amplify configuration failed: $e');
    rethrow;
  }
}

class SpatialMeshApp extends ConsumerWidget {
  const SpatialMeshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child!,
        );
      },
    );
  }
}