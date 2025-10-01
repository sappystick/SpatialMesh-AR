import 'package:injectable/injectable.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import '../core/app_config.dart';
import '../models/spatial_anchor.dart';
import '../models/user_earnings.dart';

@singleton
class AWSService {
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    try {
      // Amplify is already configured in main.dart
      _isInitialized = true;
      safePrint('✅ AWS Service initialized successfully');
    } catch (e) {
      safePrint('❌ AWS Service initialization failed: $e');
      rethrow;
    }
  }
  
  // DynamoDB Operations via API Gateway
  Future<String> createSpatialAnchor(SpatialAnchor anchor) async {
    try {
      const apiName = 'SpatialMeshAPI';
      const path = '/spatial';
      
      final request = RESTRequest(
        method: RESTMethod.post,
        path: path,
        apiName: apiName,
        body: HttpPayload.json(anchor.toJson()),
      );
      
      final response = await Amplify.API.post(request).response;
      final responseData = response.decodeBody();
      
      return responseData['contributionId'] as String;
    } catch (e) {
      safePrint('❌ Failed to create spatial anchor: $e');
      rethrow;
    }
  }
  
  Future<List<SpatialAnchor>> getSpatialAnchors(String userId) async {
    try {
      const apiName = 'SpatialMeshAPI';
      final path = '/spatial/$userId';
      
      final request = RESTRequest(
        method: RESTMethod.get,
        path: path,
        apiName: apiName,
      );
      
      final response = await Amplify.API.get(request).response;
      final responseData = response.decodeBody();
      
      return (responseData['anchors'] as List)
          .map((json) => SpatialAnchor.fromJson(json))
          .toList();
    } catch (e) {
      safePrint('❌ Failed to get spatial anchors: $e');
      return [];
    }
  }
  
  Future<UserEarnings> getUserEarnings(String userId) async {
    try {
      const apiName = 'SpatialMeshAPI';
      final path = '/earnings/$userId';
      
      final request = RESTRequest(
        method: RESTMethod.get,
        path: path,
        apiName: apiName,
      );
      
      final response = await Amplify.API.get(request).response;
      final responseData = response.decodeBody();
      
      return UserEarnings.fromJson(responseData);
    } catch (e) {
      safePrint('❌ Failed to get user earnings: $e');
      rethrow;
    }
  }
  
  // S3 Storage Operations
  Future<String> uploadARModel(String filePath, String fileName) async {
    try {
      final localFile = AWSFile.fromPath(filePath);
      
      final result = await Amplify.Storage.uploadFile(
        localFile: localFile,
        key: 'ar-models/$fileName',
        onProgress: (progress) {
          safePrint('Upload progress: ${progress.fractionCompleted}');
        },
      ).result;
      
      return result.uploadedItem.key;
    } catch (e) {
      safePrint('❌ Failed to upload AR model: $e');
      rethrow;
    }
  }
  
  Future<String> getSignedUrl(String key) async {
    try {
      final result = await Amplify.Storage.getUrl(
        key: key,
        options: const StorageGetUrlOptions(
          accessLevel: StorageAccessLevel.guest,
        ),
      ).result;
      
      return result.url.toString();
    } catch (e) {
      safePrint('❌ Failed to get signed URL: $e');
      rethrow;
    }
  }
  
  Future<void> updateUserEarnings(String userId, double earnings) async {
    try {
      const apiName = 'SpatialMeshAPI';
      const path = '/earnings';
      
      final request = RESTRequest(
        method: RESTMethod.put,
        path: path,
        apiName: apiName,
        body: HttpPayload.json({
          'userId': userId,
          'earnings': earnings,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      
      await Amplify.API.put(request).response;
    } catch (e) {
      safePrint('❌ Failed to update user earnings: $e');
      rethrow;
    }
  }
}