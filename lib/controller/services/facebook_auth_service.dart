import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:brevity/utils/logger.dart';
import 'package:brevity/models/user_model.dart';

class FacebookAuthService {
  static final FacebookAuthService _instance = FacebookAuthService._internal();
  factory FacebookAuthService() => _instance;
  FacebookAuthService._internal();

  // Secure storage instance
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    webOptions: WebOptions(
      dbName: 'BrevitySecureStorage',
      publicKey: 'BrevityPublicKey',
    ),
  );

  // Storage keys
  static const String _facebookTokenKey = 'facebook_access_token';
  static const String _facebookUserKey = 'facebook_user_data';
  static const String _facebookExpiryKey = 'facebook_token_expiry';

  AccessToken? _currentAccessToken;
  UserModel? _currentUser;
  final StreamController<UserModel?> _authStateController = 
      StreamController<UserModel?>.broadcast();

  // Auth state stream
  Stream<UserModel?> get authStateChanges => _authStateController.stream;

  // Current user getter
  UserModel? get currentUser => _currentUser;

  // Initialize the service
  Future<void> initialize() async {
    try {
      Log.i('[FacebookAuth] Initializing Facebook Auth Service');
      
      // Check if user was previously logged in
      await _checkStoredToken();
      
      Log.i('[FacebookAuth] Facebook Auth Service initialized successfully');
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to initialize Facebook Auth Service: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Login with Facebook
  Future<FacebookAuthResult> loginWithFacebook() async {
    try {
      Log.i('[FacebookAuth] Starting Facebook login');

      // Request login with required permissions
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile', 'user_friends'],
        loginBehavior: kIsWeb 
            ? LoginBehavior.dialogOnly 
            : LoginBehavior.nativeWithFallback,
      );

      return await _handleLoginResult(result);
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Login failed with error: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      return FacebookAuthResult.error('Login failed: ${e.toString()}');
    }
  }

  // Handle Facebook login result
  Future<FacebookAuthResult> _handleLoginResult(LoginResult result) async {
    switch (result.status) {
      case LoginStatus.success:
        Log.i('[FacebookAuth] Login successful');
        
        _currentAccessToken = result.accessToken;
        
        if (_currentAccessToken != null) {
          // Store token securely
          await _storeTokenSecurely(_currentAccessToken!);
          
          // Get user data
          final userData = await _getUserData();
          if (userData != null) {
            _currentUser = userData;
            await _storeUserDataSecurely(userData);
            _authStateController.add(userData);
            
            Log.i('[FacebookAuth] User data retrieved and stored');
            return FacebookAuthResult.success(userData);
          } else {
            return FacebookAuthResult.error('Failed to retrieve user data');
          }
        } else {
          return FacebookAuthResult.error('Access token is null');
        }

      case LoginStatus.cancelled:
        Log.w('[FacebookAuth] Login was cancelled by user');
        return FacebookAuthResult.cancelled();

      case LoginStatus.failed:
        Log.e('[FacebookAuth] Login failed: ${result.message}');
        return FacebookAuthResult.error(result.message ?? 'Login failed');

      case LoginStatus.operationInProgress:
        Log.w('[FacebookAuth] Login operation already in progress');
        return FacebookAuthResult.error('Login operation already in progress');
    }
  }

  // Get user data from Facebook
  Future<UserModel?> _getUserData() async {
    try {
      Log.d('[FacebookAuth] Fetching user data from Facebook');
      
      final userData = await FacebookAuth.instance.getUserData(
        fields: "name,email,picture.width(200),first_name,last_name",
      );

      Log.d('[FacebookAuth] User data received: ${userData.toString()}');

      return UserModel(
        uid: userData['id'] ?? '',
        displayName: userData['name'] ?? '',
        email: userData['email'] ?? '',
        profileImageUrl: userData['picture']?['data']?['url'] ?? '',
        emailVerified: true, // Facebook emails are verified
        createdAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to get user data: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      return null;
    }
  }

  // Store access token securely
  Future<void> _storeTokenSecurely(AccessToken token) async {
    try {
      await _secureStorage.write(key: _facebookTokenKey, value: token.token);
      
      // Store expiry date
      await _secureStorage.write(
        key: _facebookExpiryKey, 
        value: token.expires.millisecondsSinceEpoch.toString()
      );
      
      Log.d('[FacebookAuth] Token stored securely');
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to store token securely: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Store user data securely
  Future<void> _storeUserDataSecurely(UserModel user) async {
    try {
      final userJson = jsonEncode(user.toJson());
      await _secureStorage.write(key: _facebookUserKey, value: userJson);
      Log.d('[FacebookAuth] User data stored securely');
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to store user data securely: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Check stored token on app start
  Future<void> _checkStoredToken() async {
    try {
      final tokenString = await _secureStorage.read(key: _facebookTokenKey);
      final expiryString = await _secureStorage.read(key: _facebookExpiryKey);
      final userDataString = await _secureStorage.read(key: _facebookUserKey);

      if (tokenString != null) {
        // Check if token is expired
        if (expiryString != null) {
          final expiryDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expiryString));
          if (DateTime.now().isAfter(expiryDate)) {
            Log.w('[FacebookAuth] Stored token is expired, clearing storage');
            await _clearStoredData();
            return;
          }
        }

        // Validate token with Facebook
        final isValid = await _validateTokenWithFacebook();
        if (isValid && userDataString != null) {
          // Restore user session
          final userJson = jsonDecode(userDataString);
          _currentUser = UserModel.fromJson(userJson);
          _authStateController.add(_currentUser);
          Log.i('[FacebookAuth] User session restored from secure storage');
        } else {
          // Token invalid or user data missing, clear storage
          await _clearStoredData();
          Log.w('[FacebookAuth] Invalid token or missing user data, cleared storage');
        }
      }
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to check stored token: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      // Clear potentially corrupted data
      await _clearStoredData();
    }
  }

  // Validate token with Facebook
  Future<bool> _validateTokenWithFacebook() async {
    try {
      final accessToken = await FacebookAuth.instance.accessToken;
      return accessToken != null && accessToken.isExpired == false;
    } catch (e) {
      Log.e('[FacebookAuth] Token validation failed: $e');
      return false;
    }
  }

  // Logout from Facebook
  Future<void> logout() async {
    try {
      Log.i('[FacebookAuth] Starting Facebook logout');

      // Logout from Facebook
      await FacebookAuth.instance.logOut();

      // Clear stored data
      await _clearStoredData();

      // Reset local state
      _currentAccessToken = null;
      _currentUser = null;
      _authStateController.add(null);

      Log.i('[FacebookAuth] Facebook logout completed successfully');
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Logout failed: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      
      // Even if logout fails, clear local data
      await _clearStoredData();
      _currentAccessToken = null;
      _currentUser = null;
      _authStateController.add(null);
      
      rethrow;
    }
  }

  // Clear all stored data
  Future<void> _clearStoredData() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _facebookTokenKey),
        _secureStorage.delete(key: _facebookUserKey),
        _secureStorage.delete(key: _facebookExpiryKey),
      ]);
      Log.d('[FacebookAuth] Stored data cleared');
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to clear stored data: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
    }
  }

  // Check if user is logged in
  bool get isLoggedIn => _currentUser != null;

  // Get current access token
  Future<String?> getCurrentAccessToken() async {
    try {
      final accessToken = await FacebookAuth.instance.accessToken;
      return accessToken?.token;
    } catch (e) {
      Log.e('[FacebookAuth] Failed to get current access token: $e');
      return null;
    }
  }

  // Refresh access token if needed
  Future<bool> refreshTokenIfNeeded() async {
    try {
      final accessToken = await FacebookAuth.instance.accessToken;
      
      if (accessToken != null && accessToken.isExpired) {
        Log.i('[FacebookAuth] Token expired, attempting refresh');
        
        // Facebook SDK handles token refresh automatically
        // We just need to get a new token
        final newToken = await FacebookAuth.instance.accessToken;
        
        if (newToken != null && !newToken.isExpired) {
          await _storeTokenSecurely(newToken);
          Log.i('[FacebookAuth] Token refreshed successfully');
          return true;
        }
      }
      
      return false;
    } catch (e, stackTrace) {
      Log.e('[FacebookAuth] Failed to refresh token: $e');
      Log.e('[FacebookAuth] Stack trace: $stackTrace');
      return false;
    }
  }

  // Dispose resources
  void dispose() {
    _authStateController.close();
  }
}

// Facebook Auth Result class
class FacebookAuthResult {
  final bool isSuccess;
  final UserModel? user;
  final String? error;
  final bool isCancelled;

  const FacebookAuthResult._({
    required this.isSuccess,
    this.user,
    this.error,
    this.isCancelled = false,
  });

  factory FacebookAuthResult.success(UserModel user) => 
      FacebookAuthResult._(isSuccess: true, user: user);

  factory FacebookAuthResult.error(String error) => 
      FacebookAuthResult._(isSuccess: false, error: error);

  factory FacebookAuthResult.cancelled() => 
      FacebookAuthResult._(isSuccess: false, isCancelled: true);
}