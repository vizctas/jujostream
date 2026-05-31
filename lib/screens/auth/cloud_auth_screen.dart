import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../providers/auth_provider.dart';
import '../../providers/cloud_mfa_provider.dart';
import '../../providers/theme_provider.dart';
import '../onboarding/widgets/onboarding_glass_card.dart';

class CloudAuthScreen extends StatefulWidget {
  final bool isFirstRun;
  const CloudAuthScreen({super.key, this.isFirstRun = false});

  @override
  State<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends State<CloudAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;
  bool _awaitingConfirmation = false;
  Timer? _confirmationTimer;
  String? _error;
  String? _info;

  final FocusNode _emailFocus = FocusNode(debugLabel: 'auth-email');
  final FocusNode _passwordFocus = FocusNode(debugLabel: 'auth-password');
  final FocusNode _submitFocus = FocusNode(debugLabel: 'auth-submit');
  final FocusNode _mfaFocus = FocusNode(debugLabel: 'auth-mfa');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    _mfaFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isSignUp) {
      await _handleSignUp();
    } else {
      await _handleLogin();
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _info = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.loginWithCloud(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      if (success) {
        final mfa = context.read<CloudMfaProvider>();
        await mfa.refresh();
        if (mfa.status == CloudMfaStatus.setupRequired) {
          await mfa.startTotpSetup();
        }
      } else {
        setState(() {
          _error = auth.cloudError ?? 'Login failed';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _info = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final success = await auth.signUpWithCloud(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      if (success) {
        setState(() {
          _info = 'Account created. Please confirm your email to continue.';
          _awaitingConfirmation = true;
        });
        _startConfirmationPolling();
      } else {
        setState(() {
          _error = auth.cloudError ?? 'Registration failed';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startConfirmationPolling() {
    _confirmationTimer?.cancel();
    _confirmationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) {
        _confirmationTimer?.cancel();
        return;
      }

      final auth = context.read<AuthProvider>();
      final success = await auth.loginWithCloud(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        _confirmationTimer?.cancel();
        setState(() {
          _awaitingConfirmation = false;
          _info = null;
        });

        final mfa = context.read<CloudMfaProvider>();
        await mfa.refresh();
        if (mfa.status == CloudMfaStatus.setupRequired) {
          await mfa.startTotpSetup();
        }
      }
    });
  }

  Future<void> _resendEmail() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: _emailController.text.trim(),
      );
      setState(() {
        _info = 'Confirmation email resent. Check your inbox.';
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to resend: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleMfaVerify(String code) async {
    setState(() => _isLoading = true);
    final mfa = context.read<CloudMfaProvider>();
    final success = await mfa.verifyCode(code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      unawaited(context.read<AuthProvider>().pullFromCloud());
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } else {
      _mfaCodeController.clear();
      _mfaFocus.requestFocus();
    }
  }

  Future<void> _cancelMfa() async {
    final auth = context.read<AuthProvider>();
    await auth.signOutFromCloud();
    if (!mounted) return;
    context.read<CloudMfaProvider>().reset();
    setState(() {
      _mfaCodeController.clear();
    });
    _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mfa = context.watch<CloudMfaProvider>();
    final tp = context.watch<ThemeProvider>();

    final showMfaPanel = mfa.status == CloudMfaStatus.setupRequired ||
        mfa.status == CloudMfaStatus.verifyRequired ||
        (mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser);

    return Scaffold(
      backgroundColor: tp.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Static ambient gradient — solid, no blur, no animation
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tp.background,
                    tp.surface,
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: showMfaPanel
                    ? _buildMfaLayout(context, mfa, tp)
                    : _buildAuthLayout(context, tp),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthLayout(BuildContext context, ThemeProvider tp) {
    final isLight = tp.colors.isLight;
    return OnboardingSolidCard(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.cloud,
              size: 44,
              color: tp.accent,
            ).animate().scale(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 16),
            Text(
              _isSignUp ? 'Create Jujo Cloud Account' : 'Sign in to Jujo Cloud',
              style: TextStyle(
                color: isLight ? Colors.black87 : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              style: TextStyle(
                color: isLight ? Colors.black87 : Colors.white,
              ),
              decoration: _inputDecoration('Email', Icons.mail_outline, tp),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Email is required';
                if (!email.contains('@')) return 'Please enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              style: TextStyle(
                color: isLight ? Colors.black87 : Colors.white,
              ),
              obscureText: _obscurePassword,
              decoration: _inputDecoration('Password', Icons.lock_outline, tp)
                  .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: isLight ? Colors.black45 : Colors.white54,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleSubmit(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                if (value.length < 6) return 'Must be at least 6 characters';
                return null;
              },
            ),

            const SizedBox(height: 20),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_info != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tp.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: tp.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mark_email_unread_outlined,
                            color: tp.accent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _info!,
                            style: TextStyle(
                              color: tp.accent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_awaitingConfirmation) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tp.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Waiting for confirmation...',
                                style: TextStyle(
                                  color: isLight
                                      ? Colors.black45
                                      : Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : _resendEmail,
                            child: Text(
                              'Resend',
                              style: TextStyle(
                                color: tp.accent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            ElevatedButton(
              focusNode: _submitFocus,
              onPressed: _isLoading ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: tp.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isSignUp ? 'Sign Up' : 'Sign In',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _isSignUp = !_isSignUp;
                        _error = null;
                        _info = null;
                      }),
              style: TextButton.styleFrom(
                foregroundColor:
                    isLight ? Colors.black54 : Colors.white70,
              ),
              child: Text(
                _isSignUp
                    ? 'Already have an account? Sign in'
                    : 'Need sync? Create an account',
              ),
            ),

            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacementNamed('/');
                    },
              style: TextButton.styleFrom(
                foregroundColor:
                    isLight ? Colors.black38 : Colors.white38,
              ),
              child: const Text('Continue in Local-only mode'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMfaLayout(
    BuildContext context,
    CloudMfaProvider mfa,
    ThemeProvider tp,
  ) {
    final isSetup = mfa.status == CloudMfaStatus.setupRequired;
    final isLight = tp.colors.isLight;

    return OnboardingSolidCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.security,
            size: 40,
            color: tp.accentLight,
          ).animate().shake(),
          const SizedBox(height: 16),
          Text(
            isSetup ? '2FA Setup Required' : '2FA Verification Required',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isSetup
                ? 'Scan the QR code with Google Authenticator or Authy to register your account, then enter the 6-digit code.'
                : 'Enter the 6-digit code from your authenticator app.',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          if (isSetup && mfa.enrollmentUri != null) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  width: 180,
                  height: 180,
                  child: QrImageView(
                    data: mfa.enrollmentUri!,
                    version: QrVersions.auto,
                    size: 180.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                'Secret: ${mfa.enrollmentSecret ?? ""}',
                style: TextStyle(
                  color: isLight ? Colors.black45 : Colors.white54,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
          ],

          TextFormField(
            controller: _mfaCodeController,
            focusNode: _mfaFocus,
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 6,
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: _inputDecoration('6-digit code', Icons.onetwothree_outlined, tp)
                .copyWith(
              counterText: '',
            ),
            onChanged: (code) {
              if (code.length == 6) {
                _handleMfaVerify(code);
              }
            },
          ),

          const SizedBox(height: 16),
          if (mfa.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                mfa.error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
          ],

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _cancelMfa,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isLight ? Colors.black54 : Colors.white70,
                    side: BorderSide(
                      color: isLight
                          ? Colors.black26
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _handleMfaVerify(_mfaCodeController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tp.accentLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String labelText,
    IconData icon,
    ThemeProvider tp,
  ) {
    final isLight = tp.colors.isLight;
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(
        color: isLight ? Colors.black45 : Colors.white54,
        fontSize: 14,
      ),
      prefixIcon: Icon(
        icon,
        color: isLight ? Colors.black38 : Colors.white38,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isLight ? Colors.black12 : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: tp.accent,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.redAccent.withValues(alpha: 0.5),
        ),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(
          color: Colors.redAccent,
          width: 2,
        ),
      ),
      filled: true,
      fillColor: isLight
          ? Colors.black.withValues(alpha: 0.02)
          : Colors.white.withValues(alpha: 0.02),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    );
  }
}
