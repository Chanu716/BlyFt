import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:brevity/controller/services/facebook_auth_service.dart';
import 'package:brevity/utils/logger.dart';

class FacebookLoginButton extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final Function(String)? onLoginError;

  const FacebookLoginButton({
    super.key,
    this.onLoginSuccess,
    this.onLoginError,
  });

  @override
  State<FacebookLoginButton> createState() => _FacebookLoginButtonState();
}

class _FacebookLoginButtonState extends State<FacebookLoginButton> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleFacebookLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final facebookAuth = FacebookAuthService();
      final result = await facebookAuth.loginWithFacebook();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result.isSuccess && result.user != null) {
          Log.i('[FacebookLoginButton] Login successful for user: ${result.user!.displayName}');
          
          // Call success callback
          widget.onLoginSuccess?.call();
          
          // Navigate to home or main screen
          if (context.mounted) {
            context.go('/home');
          }
        } else if (result.isCancelled) {
          Log.i('[FacebookLoginButton] Login was cancelled by user');
          setState(() {
            _errorMessage = 'Login was cancelled';
          });
        } else {
          final errorMsg = result.error ?? 'Unknown error occurred';
          Log.e('[FacebookLoginButton] Login failed: $errorMsg');
          
          setState(() {
            _errorMessage = _getUserFriendlyErrorMessage(errorMsg);
          });
          
          widget.onLoginError?.call(errorMsg);
        }
      }
    } catch (e, stackTrace) {
      Log.e('[FacebookLoginButton] Unexpected error during login: $e');
      Log.e('[FacebookLoginButton] Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'An unexpected error occurred. Please try again.';
        });
        
        widget.onLoginError?.call(e.toString());
      }
    }
  }

  String _getUserFriendlyErrorMessage(String error) {
    if (error.toLowerCase().contains('network')) {
      return 'Network error. Please check your connection and try again.';
    } else if (error.toLowerCase().contains('permission')) {
      return 'Permission denied. Please allow access to continue.';
    } else if (error.toLowerCase().contains('token')) {
      return 'Authentication failed. Please try logging in again.';
    } else if (error.toLowerCase().contains('cancelled')) {
      return 'Login was cancelled.';
    } else if (error.toLowerCase().contains('denied')) {
      return 'Access was denied. Please try again.';
    } else {
      return 'Login failed. Please try again later.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Facebook Login Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleFacebookLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1877F2), // Facebook blue
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Signing in...'),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.facebook,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Continue with Facebook',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        
        // Error Message
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              border: Border.all(color: Colors.red[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red[700],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _errorMessage = null;
                    });
                  },
                  icon: Icon(
                    Icons.close,
                    color: Colors.red[700],
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                ),
              ],
            ),
          ),
        
        // Retry Button (shown only if there's an error)
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: _handleFacebookLogin,
              child: const Text('Try Again'),
            ),
          ),
      ],
    );
  }
}

// Facebook Auth Status Widget for checking login state
class FacebookAuthStatusWidget extends StatelessWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Function(String)? onError;

  const FacebookAuthStatusWidget({
    super.key,
    required this.child,
    this.loadingWidget,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FacebookAuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }
        
        if (snapshot.hasError) {
          final errorMsg = snapshot.error.toString();
          Log.e('[FacebookAuthStatus] Stream error: $errorMsg');
          onError?.call(errorMsg);
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Authentication Error',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please try logging in again',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          );
        }
        
        return child;
      },
    );
  }
}