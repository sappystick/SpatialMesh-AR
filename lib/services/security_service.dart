import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:injectable/injectable.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/app_config.dart';
import '../services/analytics_service.dart';
import '../services/blockchain_service.dart';

@singleton
class SecurityService {
  static const KEY_SIZE = 32; // 256 bits
  static const ITERATIONS = 100000;
  static const SALT_SIZE = 32;
  static const IV_SIZE = 12;
  static const AUTH_TAG_SIZE = 16;
  static const REFRESH_INTERVAL = Duration(hours: 24);
  
  // Core components
  final _secureStorage = FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  final _random = Random.secure();
  
  // Cryptographic components
  late final KeyDerivator _keyDerivator;
  late final BlockCipher _aesCipher;
  late final GCMBlockCipher _gcmCipher;
  
  // Fraud detection
  final Map<String, List<double>> _transactionPatterns = {};
  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lastAttempts = {};
  
  // Key management
  String? _masterKeyHash;
  Map<String, String> _keyCache = {};
  Timer? _keyRotationTimer;
  
  // Dependencies
  final AnalyticsService _analytics;
  final BlockchainService _blockchain;
  
  // State
  bool _isInitialized = false;
  
  SecurityService(this._analytics, this._blockchain);
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize cryptographic components
      _keyDerivator = PBKDF2KeyDerivator(SHA256Digest())
        ..init(
          Pbkdf2Parameters(
            Uint8List(SALT_SIZE),
            ITERATIONS,
            KEY_SIZE,
          ),
        );
      
      _aesCipher = AESEngine();
      _gcmCipher = GCMBlockCipher(_aesCipher);
      
      // Check biometric availability
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final biometricTypes = await _localAuth.getAvailableBiometrics();
      
      _analytics.trackEvent('security_initialized', {
        'biometrics_available': canCheckBiometrics,
        'biometric_types': biometricTypes.map((t) => t.toString()).toList(),
      });
      
      // Start key rotation timer
      _startKeyRotation();
      
      _isInitialized = true;
    } catch (e) {
      _analytics.trackEvent('security_init_error', {'error': e.toString()});
      rethrow;
    }
  }
  
  Future<bool> setupMasterKey(String password) async {
    try {
      // Generate salt
      final salt = _generateRandomBytes(SALT_SIZE);
      
      // Derive master key
      final masterKey = await _deriveKey(password, salt);
      
      // Generate master key hash
      _masterKeyHash = await _computeHash(masterKey);
      
      // Store salt and hash
      await _secureStorage.write(
        key: 'master_key_salt',
        value: base64.encode(salt),
      );
      await _secureStorage.write(
        key: 'master_key_hash',
        value: _masterKeyHash,
      );
      
      _analytics.trackEvent('master_key_setup', {'success': true});
      return true;
    } catch (e) {
      _analytics.trackEvent('master_key_setup_error', {'error': e.toString()});
      return false;
    }
  }
  
  Future<bool> verifyMasterKey(String password) async {
    try {
      // Get stored salt
      final saltStr = await _secureStorage.read(key: 'master_key_salt');
      if (saltStr == null) return false;
      
      final salt = base64.decode(saltStr);
      
      // Derive key and compute hash
      final key = await _deriveKey(password, salt);
      final hash = await _computeHash(key);
      
      // Compare with stored hash
      final storedHash = await _secureStorage.read(key: 'master_key_hash');
      return hash == storedHash;
    } catch (e) {
      _analytics.trackEvent('master_key_verify_error', {'error': e.toString()});
      return false;
    }
  }
  
  Future<String> encryptData(String data, {String? key}) async {
    if (!_isInitialized) throw Exception('Security service not initialized');
    
    try {
      final dataKey = key ?? await _getDerivedKey();
      final iv = _generateRandomBytes(IV_SIZE);
      
      // Initialize GCM cipher
      final params = ParametersWithIV(
        KeyParameter(base64.decode(dataKey)),
        iv,
      );
      _gcmCipher.init(true, params);
      
      // Encrypt data
      final plaintext = utf8.encode(data);
      final ciphertext = _gcmCipher.process(Uint8List.fromList(plaintext));
      
      // Combine IV and ciphertext
      final combined = Uint8List(IV_SIZE + ciphertext.length)
        ..setAll(0, iv)
        ..setAll(IV_SIZE, ciphertext);
      
      return base64.encode(combined);
    } catch (e) {
      _analytics.trackEvent('encryption_error', {'error': e.toString()});
      rethrow;
    }
  }
  
  Future<String> decryptData(String encryptedData, {String? key}) async {
    if (!_isInitialized) throw Exception('Security service not initialized');
    
    try {
      final combined = base64.decode(encryptedData);
      final iv = combined.sublist(0, IV_SIZE);
      final ciphertext = combined.sublist(IV_SIZE);
      
      final dataKey = key ?? await _getDerivedKey();
      
      // Initialize GCM cipher
      final params = ParametersWithIV(
        KeyParameter(base64.decode(dataKey)),
        iv,
      );
      _gcmCipher.init(false, params);
      
      // Decrypt data
      final plaintext = _gcmCipher.process(ciphertext);
      return utf8.decode(plaintext);
    } catch (e) {
      _analytics.trackEvent('decryption_error', {'error': e.toString()});
      rethrow;
    }
  }
  
  Future<bool> authenticateUser() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access secure features',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      
      _analytics.trackEvent('user_authentication', {
        'success': authenticated,
        'method': 'biometric',
      });
      
      return authenticated;
    } catch (e) {
      _analytics.trackEvent('authentication_error', {'error': e.toString()});
      return false;
    }
  }
  
  Future<bool> detectFraud(
    String userId,
    String action,
    Map<String, dynamic> data,
  ) async {
    try {
      // Check rate limiting
      if (_isRateLimited(userId, action)) {
        _analytics.trackEvent('fraud_detected', {
          'reason': 'rate_limit',
          'user_id': userId,
          'action': action,
        });
        return true;
      }
      
      // Check transaction patterns
      if (action == 'transaction') {
        final amount = data['amount'] as double;
        final isSuspicious = await _analyzeTransactionPattern(userId, amount);
        if (isSuspicious) {
          _analytics.trackEvent('fraud_detected', {
            'reason': 'suspicious_pattern',
            'user_id': userId,
            'action': action,
          });
          return true;
        }
      }
      
      // Verify blockchain transaction
      if (action == 'withdraw') {
        final txHash = data['transaction_hash'] as String;
        final isValid = await _blockchain.verifyTransaction(txHash);
        if (!isValid) {
          _analytics.trackEvent('fraud_detected', {
            'reason': 'invalid_transaction',
            'user_id': userId,
            'action': action,
          });
          return true;
        }
      }
      
      return false;
    } catch (e) {
      _analytics.trackEvent('fraud_detection_error', {'error': e.toString()});
      return true;
    }
  }
  
  bool _isRateLimited(String userId, String action) {
    final now = DateTime.now();
    final key = '$userId:$action';
    
    // Check last attempt time
    final lastAttempt = _lastAttempts[key];
    if (lastAttempt != null) {
      final timeDiff = now.difference(lastAttempt);
      
      // If too many failed attempts, require cooldown
      if (_failedAttempts[key] ?? 0 >= 5) {
        if (timeDiff < Duration(minutes: 15)) {
          return true;
        } else {
          // Reset failed attempts after cooldown
          _failedAttempts[key] = 0;
        }
      }
      
      // Basic rate limiting
      if (timeDiff < Duration(seconds: 1)) {
        _failedAttempts[key] = (_failedAttempts[key] ?? 0) + 1;
        return true;
      }
    }
    
    _lastAttempts[key] = now;
    return false;
  }
  
  Future<bool> _analyzeTransactionPattern(
    String userId,
    double amount,
  ) async {
    final patterns = _transactionPatterns[userId] ?? [];
    
    // Add new amount to patterns
    patterns.add(amount);
    if (patterns.length > 100) patterns.removeAt(0);
    _transactionPatterns[userId] = patterns;
    
    if (patterns.length < 5) return false;
    
    // Calculate statistics
    final mean = patterns.reduce((a, b) => a + b) / patterns.length;
    final stdDev = sqrt(
      patterns.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
          patterns.length,
    );
    
    // Check if amount is statistically anomalous
    final zScore = (amount - mean).abs() / stdDev;
    return zScore > 3.0; // Three standard deviations
  }
  
  void _startKeyRotation() {
    _keyRotationTimer = Timer.periodic(REFRESH_INTERVAL, (_) async {
      try {
        // Generate new keys
        final newKeys = <String, String>{};
        
        for (final keyId in _keyCache.keys) {
          final newKey = base64.encode(_generateRandomBytes(KEY_SIZE));
          newKeys[keyId] = newKey;
          
          // Re-encrypt data with new key
          await _rotateKey(keyId, _keyCache[keyId]!, newKey);
        }
        
        // Update key cache
        _keyCache = newKeys;
        
        _analytics.trackEvent('key_rotation_complete', {
          'keys_rotated': newKeys.length,
        });
      } catch (e) {
        _analytics.trackEvent('key_rotation_error', {'error': e.toString()});
      }
    });
  }
  
  Future<void> _rotateKey(
    String keyId,
    String oldKey,
    String newKey,
  ) async {
    // Implementation depends on how encrypted data is stored
    // This is a placeholder for the actual implementation
  }
  
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
  
  Future<String> _deriveKey(String password, Uint8List salt) async {
    final params = Pbkdf2Parameters(salt, ITERATIONS, KEY_SIZE);
    _keyDerivator.init(params);
    
    final key = _keyDerivator.process(Uint8List.fromList(utf8.encode(password)));
    return base64.encode(key);
  }
  
  Future<String> _computeHash(String input) async {
    final digest = SHA512Digest();
    final hash = digest.process(Uint8List.fromList(utf8.encode(input)));
    return base64.encode(hash);
  }
  
  Future<String> _getDerivedKey() async {
    if (_masterKeyHash == null) {
      throw Exception('Master key not set');
    }
    
    final keyId = DateTime.now().millisecondsSinceEpoch.toString();
    if (!_keyCache.containsKey(keyId)) {
      _keyCache[keyId] = base64.encode(_generateRandomBytes(KEY_SIZE));
    }
    
    return _keyCache[keyId]!;
  }
  
  @override
  void dispose() {
    _keyRotationTimer?.cancel();
    _keyCache.clear();
    _transactionPatterns.clear();
    _failedAttempts.clear();
    _lastAttempts.clear();
    _isInitialized = false;
  }
}