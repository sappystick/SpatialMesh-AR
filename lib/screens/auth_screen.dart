import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../core/app_theme.dart';
import '../services/analytics_service.dart';
import '../core/service_locator.dart';
import 'home_screen.dart';

enum AuthMode { signIn, signUp, resetPassword }

final authModeProvider = StateProvider<AuthMode>((ref) => AuthMode.signIn);
final isLoadingProvider = StateProvider<bool>((ref) => false);
final isAuthenticatingProvider = StateProvider<bool>((ref) => false);

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  bool _isPasswordVisible = false;
  String? _errorMessage;
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkBiometrics();
  }
  
  void _setupAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeIn,
    ));
    
    _slideController.forward();
  }
  
  Future<void> _checkBiometrics() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final hasbiometrics = canCheckBiometrics && await _localAuth.isDeviceSupported();
      
      if (hasbiometrics) {
        await _authenticateWithBiometrics();
      }
    } catch (e) {
      print('Biometric check failed: $e');
    }
  }
  
  Future<void> _authenticateWithBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to sign in',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      
      if (authenticated) {
        // TODO: Implement biometric sign-in logic
      }
    } catch (e) {
      print('Biometric authentication failed: $e');
    }
  }
  
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _errorMessage = null);
    ref.read(isLoadingProvider.notifier).state = true;
    
    try {
      final mode = ref.read(authModeProvider);
      
      switch (mode) {
        case AuthMode.signIn:
          await _signIn();
          break;
        case AuthMode.signUp:
          await _signUp();
          break;
        case AuthMode.resetPassword:
          await _resetPassword();
          break;
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      ref.read(isLoadingProvider.notifier).state = false;
    }
  }
  
  Future<void> _signIn() async {
    try {
      final result = await Amplify.Auth.signIn(
        username: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (result.isSignedIn) {
        final analyticsService = getIt<AnalyticsService>();
        await analyticsService.trackEvent('user_signed_in', {
          'method': 'email',
        });
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }
  
  Future<void> _signUp() async {
    try {
      final userAttributes = <CognitoUserAttributeKey, String>{
        CognitoUserAttributeKey.email: _emailController.text.trim(),
      };
      
      final result = await Amplify.Auth.signUp(
        username: _emailController.text.trim(),
        password: _passwordController.text,
        options: CognitoSignUpOptions(userAttributes: userAttributes),
      );
      
      if (result.isSignUpComplete) {
        ref.read(authModeProvider.notifier).state = AuthMode.signIn;
        _showVerificationDialog();
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }
  
  Future<void> _resetPassword() async {
    try {
      await Amplify.Auth.resetPassword(
        username: _emailController.text.trim(),
      );
      
      if (mounted) {
        _showVerificationDialog(isPasswordReset: true);
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }
  
  Future<void> _confirmResetPassword(String code) async {
    try {
      await Amplify.Auth.confirmResetPassword(
        username: _emailController.text.trim(),
        newPassword: _passwordController.text,
        confirmationCode: code,
      );
      
      if (mounted) {
        ref.read(authModeProvider.notifier).state = AuthMode.signIn;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successful')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }
  
  Future<void> _confirmSignUp(String code) async {
    try {
      await Amplify.Auth.confirmSignUp(
        username: _emailController.text.trim(),
        confirmationCode: code,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verification successful')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }
  
  void _showVerificationDialog({bool isPasswordReset = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isPasswordReset ? 'Reset Password' : 'Verify Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isPasswordReset
                  ? 'Enter the verification code sent to your email to reset your password.'
                  : 'Enter the verification code sent to your email to complete registration.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _verificationCodeController,
              decoration: const InputDecoration(
                labelText: 'Verification Code',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _verificationCodeController.clear();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (isPasswordReset) {
                await _confirmResetPassword(_verificationCodeController.text);
              } else {
                await _confirmSignUp(_verificationCodeController.text);
              }
              if (mounted) Navigator.of(context).pop();
              _verificationCodeController.clear();
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _verificationCodeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(authModeProvider);
    final isLoading = ref.watch(isLoadingProvider);
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.primaryGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.view_in_ar,
                              size: 64,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              mode == AuthMode.signIn
                                  ? 'Welcome Back'
                                  : mode == AuthMode.signUp
                                      ? 'Create Account'
                                      : 'Reset Password',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 24),
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: const Icon(Icons.email_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!value.contains('@')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            if (mode != AuthMode.resetPassword) ...[
                              TextFormField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isPasswordVisible = !_isPasswordVisible;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                obscureText: !_isPasswordVisible,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  if (mode == AuthMode.signUp && value.length < 8) {
                                    return 'Password must be at least 8 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (mode == AuthMode.signUp)
                              TextFormField(
                                controller: _confirmPasswordController,
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(),
                                      )
                                    : Text(
                                        mode == AuthMode.signIn
                                            ? 'Sign In'
                                            : mode == AuthMode.signUp
                                                ? 'Sign Up'
                                                : 'Reset Password',
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (mode == AuthMode.signIn) ...[
                              TextButton(
                                onPressed: () {
                                  ref.read(authModeProvider.notifier).state =
                                      AuthMode.resetPassword;
                                },
                                child: const Text('Forgot Password?'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      'Or sign in with',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _SocialButton(
                                    icon: Icons.g_mobiledata,
                                    label: 'Google',
                                    onPressed: () {
                                      // TODO: Implement Google sign-in
                                    },
                                  ),
                                  _SocialButton(
                                    icon: MdiIcons.apple,
                                    label: 'Apple',
                                    onPressed: () {
                                      // TODO: Implement Apple sign-in
                                    },
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                ref.read(authModeProvider.notifier).state =
                                    mode == AuthMode.signIn
                                        ? AuthMode.signUp
                                        : AuthMode.signIn;
                              },
                              child: Text(
                                mode == AuthMode.signIn
                                    ? 'Don\'t have an account? Sign Up'
                                    : 'Already have an account? Sign In',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
