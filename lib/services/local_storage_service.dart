import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/spatial_anchor.dart';
import '../models/user_earnings.dart';
import '../models/mesh_session.dart';

class LocalStorageService {
  static const _version = '1.0.0';
  static const _encryptionKey = 'your_encryption_key_here';
  
  late final Directory _baseDir;
  late final Directory _cacheDir;
  late final StorageEncryption _encryption;
  late final StorageCompression _compression;
  late final StorageMigration _migration;
  
  final _changeController = StreamController<StorageChange>.broadcast();
  Stream<StorageChange> get changes => _changeController.stream;

  // Storage paths
  late final String _anchorsPath;
  late final String _sessionsPath;
  late final String _userDataPath;
  late final String _cachePath;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Get application storage directories
    final appDir = await getApplicationDocumentsDirectory();
    final tempDir = await getTemporaryDirectory();
    
    // Set up storage paths
    _baseDir = Directory('${appDir.path}/spatialMesh');
    _cacheDir = Directory('${tempDir.path}/spatialMesh');
    
    _anchorsPath = '${_baseDir.path}/anchors';
    _sessionsPath = '${_baseDir.path}/sessions';
    _userDataPath = '${_baseDir.path}/userData';
    _cachePath = _cacheDir.path;

    // Initialize components
    _encryption = StorageEncryption(_encryptionKey);
    _compression = StorageCompression();
    _migration = StorageMigration(_version);

    // Create directories if they don't exist
    await Future.wait([
      _createDirectory(_anchorsPath),
      _createDirectory(_sessionsPath),
      _createDirectory(_userDataPath),
      _createDirectory(_cachePath),
    ]);

    // Check for and perform migrations
    await _migration.checkAndMigrate(_baseDir);
    
    _isInitialized = true;
  }

  Future<void> _createDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  // Spatial Anchors
  Future<void> saveAnchor(SharedAnchor anchor) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_anchorsPath/${anchor.id}.json';
      final json = jsonEncode(anchor.toJson());
      
      // Compress and encrypt data
      final compressed = await _compression.compress(json);
      final encrypted = await _encryption.encrypt(compressed);
      
      // Save to file
      await File(path).writeAsBytes(encrypted);
      
      _notifyChange(StorageChangeType.anchorSaved, anchor.id);
    } catch (e) {
      print('Error saving anchor: $e');
      rethrow;
    }
  }

  Future<SharedAnchor?> loadAnchor(String anchorId) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_anchorsPath/$anchorId.json';
      final file = File(path);
      
      if (!await file.exists()) return null;
      
      // Read and decrypt data
      final encrypted = await file.readAsBytes();
      final compressed = await _encryption.decrypt(encrypted);
      final json = await _compression.decompress(compressed);
      
      return SharedAnchor.fromJson(jsonDecode(json));
    } catch (e) {
      print('Error loading anchor: $e');
      return null;
    }
  }

  Future<List<SharedAnchor>> loadAllAnchors() async {
    if (!_isInitialized) await initialize();

    try {
      final anchors = <SharedAnchor>[];
      final dir = Directory(_anchorsPath);
      
      await for (final file in dir.list()) {
        if (file.path.endsWith('.json')) {
          final anchorId = file.path.split('/').last.replaceAll('.json', '');
          final anchor = await loadAnchor(anchorId);
          if (anchor != null) {
            anchors.add(anchor);
          }
        }
      }
      
      return anchors;
    } catch (e) {
      print('Error loading all anchors: $e');
      return [];
    }
  }

  // Mesh Sessions
  Future<void> saveSession(MeshSession session) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_sessionsPath/${session.id}.json';
      final json = jsonEncode(session.toJson());
      
      // Compress and encrypt data
      final compressed = await _compression.compress(json);
      final encrypted = await _encryption.encrypt(compressed);
      
      // Save to file
      await File(path).writeAsBytes(encrypted);
      
      _notifyChange(StorageChangeType.sessionSaved, session.id);
    } catch (e) {
      print('Error saving session: $e');
      rethrow;
    }
  }

  Future<MeshSession?> loadSession(String sessionId) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_sessionsPath/$sessionId.json';
      final file = File(path);
      
      if (!await file.exists()) return null;
      
      // Read and decrypt data
      final encrypted = await file.readAsBytes();
      final compressed = await _encryption.decrypt(encrypted);
      final json = await _compression.decompress(compressed);
      
      return MeshSession.fromJson(jsonDecode(json));
    } catch (e) {
      print('Error loading session: $e');
      return null;
    }
  }

  // User Data
  Future<void> saveUserData(String userId, Map<String, dynamic> data) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_userDataPath/$userId.json';
      final json = jsonEncode(data);
      
      // Compress and encrypt data
      final compressed = await _compression.compress(json);
      final encrypted = await _encryption.encrypt(compressed);
      
      // Save to file
      await File(path).writeAsBytes(encrypted);
      
      _notifyChange(StorageChangeType.userDataSaved, userId);
    } catch (e) {
      print('Error saving user data: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadUserData(String userId) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_userDataPath/$userId.json';
      final file = File(path);
      
      if (!await file.exists()) return null;
      
      // Read and decrypt data
      final encrypted = await file.readAsBytes();
      final compressed = await _encryption.decrypt(encrypted);
      final json = await _compression.decompress(compressed);
      
      return jsonDecode(json);
    } catch (e) {
      print('Error loading user data: $e');
      return null;
    }
  }

  // Cache Management
  Future<void> cacheData(String key, List<int> data) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_cachePath/${_hashKey(key)}';
      await File(path).writeAsBytes(data);
    } catch (e) {
      print('Error caching data: $e');
    }
  }

  Future<List<int>?> getCachedData(String key) async {
    if (!_isInitialized) await initialize();

    try {
      final path = '$_cachePath/${_hashKey(key)}';
      final file = File(path);
      
      if (!await file.exists()) return null;
      
      return await file.readAsBytes();
    } catch (e) {
      print('Error getting cached data: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();

    try {
      final dir = Directory(_cachePath);
      await dir.delete(recursive: true);
      await dir.create();
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  // Storage Management
  Future<int> getStorageSize() async {
    if (!_isInitialized) await initialize();

    try {
      int totalSize = 0;
      
      totalSize += await _calculateDirectorySize(_anchorsPath);
      totalSize += await _calculateDirectorySize(_sessionsPath);
      totalSize += await _calculateDirectorySize(_userDataPath);
      
      return totalSize;
    } catch (e) {
      print('Error calculating storage size: $e');
      return 0;
    }
  }

  Future<int> _calculateDirectorySize(String path) async {
    int size = 0;
    final dir = Directory(path);
    
    await for (final file in dir.list(recursive: true)) {
      if (file is File) {
        size += await file.length();
      }
    }
    
    return size;
  }

  String _hashKey(String key) {
    final bytes = utf8.encode(key);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _notifyChange(StorageChangeType type, String id) {
    _changeController.add(StorageChange(type: type, id: id));
  }

  Future<void> dispose() async {
    await _changeController.close();
  }
}

class StorageEncryption {
  final String key;
  
  StorageEncryption(this.key);
  
  Future<List<int>> encrypt(List<int> data) async {
    // Implement encryption
    return data;
  }
  
  Future<List<int>> decrypt(List<int> data) async {
    // Implement decryption
    return data;
  }
}

class StorageCompression {
  Future<List<int>> compress(String data) async {
    return utf8.encode(data);
  }
  
  Future<String> decompress(List<int> data) async {
    return utf8.decode(data);
  }
}

class StorageMigration {
  final String currentVersion;
  
  StorageMigration(this.currentVersion);
  
  Future<void> checkAndMigrate(Directory baseDir) async {
    // Implement version checking and data migration
  }
}

class StorageChange {
  final StorageChangeType type;
  final String id;
  
  StorageChange({
    required this.type,
    required this.id,
  });
}

enum StorageChangeType {
  anchorSaved,
  sessionSaved,
  userDataSaved,
}