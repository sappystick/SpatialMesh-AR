import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

enum AuthState {
  initial,
  authenticated,
  unauthenticated,
  error,
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.initial) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      state = session.isSignedIn ? AuthState.authenticated : AuthState.unauthenticated;
    } catch (e) {
      state = AuthState.error;
    }
  }

  Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
      state = AuthState.unauthenticated;
    } catch (e) {
      state = AuthState.error;
    }
  }

  Future<AuthUser?> getCurrentUser() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      return user;
    } catch (e) {
      return null;
    }
  }

  Future<Map<CognitoUserAttributeKey, String>> getUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return {
        for (var attribute in attributes)
          attribute.userAttributeKey: attribute.value,
      };
    } catch (e) {
      return {};
    }
  }

  Future<void> updateUserAttribute(
    CognitoUserAttributeKey key,
    String value,
  ) async {
    try {
      await Amplify.Auth.updateUserAttribute(
        userAttributeKey: key,
        value: value,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> verifyAttribute(
    CognitoUserAttributeKey attributeKey,
    String confirmationCode,
  ) async {
    try {
      final result = await Amplify.Auth.confirmUserAttribute(
        userAttributeKey: attributeKey,
        confirmationCode: confirmationCode,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    try {
      await Amplify.Auth.updatePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
    } catch (e) {
      rethrow;
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final userProvider = FutureProvider<AuthUser?>((ref) async {
  final authNotifier = ref.watch(authProvider.notifier);
  return await authNotifier.getCurrentUser();
});

final userAttributesProvider = FutureProvider<Map<CognitoUserAttributeKey, String>>((ref) async {
  final authNotifier = ref.watch(authProvider.notifier);
  return await authNotifier.getUserAttributes();
});