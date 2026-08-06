import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../providers/auth_provider.dart';
import '../../providers/cloud_mfa_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/input/gamepad_navigation_service.dart';
import '../../services/tv/tv_focus_helpers.dart';

class CloudAuthScreen extends StatefulWidget {
  final bool isFirstRun;
  final bool popOnSuccess;
  const CloudAuthScreen({
    super.key,
    this.isFirstRun = false,
    this.popOnSuccess = false,
  });

  @override
  State<CloudAuthScreen> createState() => _CloudAuthScreenState();
}

class _CloudAuthScreenState extends State<CloudAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaCodeController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _mfaCodeFocusNode = FocusNode();

  bool _isLoading = false;
  bool _syncingServers = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;
  bool _awaitingConfirmation = false;

  Timer? _confirmationTimer;
  String? _error;
  String? _info;

  late final CloudMfaProvider _mfaProvider;
  bool _wasMfaPanelShown = false;

  @override
  void initState() {
    super.initState();
    GamepadNavigationService.setActive(false);
    _mfaProvider = context.read<CloudMfaProvider>();
    _mfaProvider.addListener(_onMfaStateChange);

    // Keep the inner text fields focusable for typing, but remove them from
    // directional traversal so the TvFocusable wrapper is the DPAD target.
    _emailFocusNode.skipTraversal = true;
    _passwordFocusNode.skipTraversal = true;
    _mfaCodeFocusNode.skipTraversal = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onMfaStateChange();
    });
  }

  void _onMfaStateChange() {
    if (!mounted) return;
    final status = _mfaProvider.status;
    final showMfaPanel =
        status == CloudMfaStatus.setupRequired ||
        status == CloudMfaStatus.verifyRequired ||
        (status == CloudMfaStatus.loading && _mfaProvider.blocksCloudUser);

    if (showMfaPanel && !_wasMfaPanelShown) {
      _wasMfaPanelShown = true;
      FocusScope.of(context).unfocus();
    } else if (!showMfaPanel && _wasMfaPanelShown) {
      _wasMfaPanelShown = false;
    }
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _mfaCodeFocusNode.dispose();
    _mfaProvider.removeListener(_onMfaStateChange);
    GamepadNavigationService.setActive(true);
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

    if (success) {
      // Await the cloud pull BEFORE navigating — navigating first made cloud
      // servers appear only after an app restart, because the main screen
      // rendered with stale local data while the pull was still in flight.
      setState(() => _syncingServers = true);
      try {
        await context.read<AuthProvider>().pullFromCloud().timeout(
          const Duration(seconds: 8),
        );
      } catch (_) {
        // Timeout or network error — proceed anyway; polling and resume
        // retries will catch up. Never trap the user on the login screen.
      }
      if (!mounted) return;
      if (widget.popOnSuccess) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } else {
      setState(() => _isLoading = false);
      _mfaCodeController.clear();
    }
  }

  Future<void> _cancelMfa() async {
    _confirmationTimer?.cancel();
    final auth = context.read<AuthProvider>();
    await auth.signOutFromCloud();
    if (!mounted) return;
    context.read<CloudMfaProvider>().reset();
    setState(() {
      _mfaCodeController.clear();
      _isLoading = false;
    });
    if (widget.popOnSuccess) {
      Navigator.of(context).pop(false);
    }
  }

  // Native IME helpers. Gamepad select focuses the real field, touch uses the
  // same TextFormField path, so the device keyboard stays native.
  void _focusNativeInput(FocusNode focusNode) {
    focusNode.requestFocus();
    // Show the keyboard only after the field's input connection has attached.
    // Showing it in the same tick raced the attach on TV: the IME appeared
    // with no connection, so the remote's keys never reached it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  bool get _typingInField {
    final focused = FocusManager.instance.primaryFocus;
    return focused == _emailFocusNode ||
        focused == _passwordFocusNode ||
        focused == _mfaCodeFocusNode;
  }

  void _continueLocalOnly() {
    FocusScope.of(context).unfocus();
    if (!widget.isFirstRun && (Navigator.maybeOf(context)?.canPop() ?? false)) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacementNamed('/');
  }

  Widget _orderedAuthFocus({
    required double order,
    required Widget child,
    VoidCallback? onSelect,
    bool autofocus = false,
    bool excludeChildFocus = false,
    bool interceptArrowKeys = false,
    double borderRadius = 16,
  }) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: TvFocusable(
        autofocus: autofocus,
        excludeChildFocus: excludeChildFocus,
        onSelect: onSelect,
        borderRadius: borderRadius,
        focusColor: Colors.white.withValues(alpha: 0.18),
        focusFillColor: Colors.white.withValues(alpha: 0.08),
        focusBorderWidth: 1.2,
        focusScale: 1.0,
        child:
            interceptArrowKeys
                ? Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    final key = event.logicalKey;
                    // While an inner field is being edited, key events bubble
                    // from it up through this ancestor. Stealing up/down here
                    // yanked focus off the field, closed the IME connection,
                    // and left the on-screen keyboard visible but deaf — the
                    // remote could never reach it. Arrows belong to the IME
                    // while typing.
                    if (_typingInField) {
                      return KeyEventResult.ignored;
                    }
                    if (key == LogicalKeyboardKey.arrowUp) {
                      node.nearestScope?.focusInDirection(
                        TraversalDirection.up,
                      );
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowDown) {
                      node.nearestScope?.focusInDirection(
                        TraversalDirection.down,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: child,
                )
                : child,
      ),
    );
  }

  KeyEventResult _handleAuthScreenKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      final focused = FocusManager.instance.primaryFocus;
      if (focused == _emailFocusNode ||
          focused == _passwordFocusNode ||
          focused == _mfaCodeFocusNode) {
        focused?.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        return KeyEventResult.handled;
      }
      final mfa = context.read<CloudMfaProvider>();
      final showMfaPanel =
          mfa.status == CloudMfaStatus.setupRequired ||
          mfa.status == CloudMfaStatus.verifyRequired ||
          (mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser);
      if (showMfaPanel) {
        _cancelMfa();
        return KeyEventResult.handled;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mfa = context.watch<CloudMfaProvider>();
    final tp = context.watch<ThemeProvider>();

    final showMfaPanel =
        mfa.status == CloudMfaStatus.setupRequired ||
        mfa.status == CloudMfaStatus.verifyRequired ||
        (mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser);

    return Focus(
      onKeyEvent: _handleAuthScreenKey,
      child: Scaffold(
        backgroundColor: tp.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Static ambient gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tp.background, tp.surface],
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
      ),
    );
  }

  Widget _buildAuthLayout(BuildContext context, ThemeProvider tp) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.01),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: Form(
            key: _formKey,
            child: FocusTraversalGroup(
              policy: _WrapOrderedTraversalPolicy(),
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
                    _isSignUp
                        ? 'Create Jujo Cloud Account'
                        : 'Sign in to Jujo Cloud',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Email field
                  _orderedAuthFocus(
                    order: 0,
                    autofocus: true,
                    interceptArrowKeys: true,
                    onSelect: () => _focusNativeInput(_emailFocusNode),
                    child: TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Email',
                        Icons.mail_outline,
                        tp,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) =>
                          _focusNativeInput(_passwordFocusNode),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Email is required';
                        if (!email.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  _orderedAuthFocus(
                    order: 1,
                    interceptArrowKeys: true,
                    onSelect: () => _focusNativeInput(_passwordFocusNode),
                    child: TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      style: const TextStyle(color: Colors.white),
                      obscureText: _obscurePassword,
                      decoration:
                          _inputDecoration(
                            'Password',
                            Icons.lock_outline,
                            tp,
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Colors.white54,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => _handleSubmit(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        if (value.length < 6) {
                          return 'Must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
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
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 18,
                          ),
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
                              Icon(
                                Icons.mark_email_unread_outlined,
                                color: tp.accentLight,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _info!,
                                  style: TextStyle(
                                    color: tp.accentLight,
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
                                        color: tp.accentLight,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Waiting for confirmation...',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                _orderedAuthFocus(
                                  order: 1.5,
                                  onSelect: _isLoading ? null : _resendEmail,
                                  child: TextButton(
                                    onPressed: _isLoading ? null : _resendEmail,
                                    child: Text(
                                      'Resend',
                                      style: TextStyle(
                                        color: tp.accentLight,
                                        fontSize: 12,
                                      ),
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

                  _orderedAuthFocus(
                    order: 2,
                    onSelect: _isLoading ? null : _handleSubmit,
                    child: ElevatedButton(
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
                  ),
                  const SizedBox(height: 16),

                  _orderedAuthFocus(
                    order: 3,
                    onSelect: _isLoading
                        ? null
                        : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                            _info = null;
                          }),
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                              _info = null;
                            }),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : 'Need sync? Create an account',
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  _orderedAuthFocus(
                    order: 4,
                    onSelect: _continueLocalOnly,
                    child: TextButton(
                      onPressed: _continueLocalOnly,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Continue in Local-only mode'),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.01),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: FocusTraversalGroup(
            policy: _WrapOrderedTraversalPolicy(),
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
                  style: const TextStyle(
                    color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white70,
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                _orderedAuthFocus(
                  order: 0,
                  autofocus: true,
                  interceptArrowKeys: true,
                  onSelect: () => _focusNativeInput(_mfaCodeFocusNode),
                  child: TextFormField(
                    controller: _mfaCodeController,
                    focusNode: _mfaCodeFocusNode,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: _inputDecoration(
                      '6-digit code',
                      Icons.onetwothree_outlined,
                      tp,
                    ).copyWith(counterText: ''),
                    onChanged: (code) {
                      if (code.length == 6 && !_isLoading) {
                        FocusScope.of(context).unfocus();
                        _handleMfaVerify(code);
                      }
                    },
                    onFieldSubmitted: (code) {
                      if (code.length == 6 && !_isLoading) {
                        _handleMfaVerify(code);
                      }
                    },
                  ),
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
                      child: _orderedAuthFocus(
                        order: 1,
                        onSelect: _isLoading ? null : _cancelMfa,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _cancelMfa,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _orderedAuthFocus(
                        order: 2,
                        onSelect: _isLoading
                            ? null
                            : () => _handleMfaVerify(_mfaCodeController.text),
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () => _handleMfaVerify(_mfaCodeController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tp.accent,
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
                    ),
                  ],
                ),
                if (_syncingServers) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tp.accentLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Syncing your servers…',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
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
      labelStyle: TextStyle(color: Colors.white54, fontSize: 14),
      prefixIcon: Icon(icon, color: isLight ? Colors.black38 : Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isLight
              ? Colors.black12
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      filled: true,
      fillColor: isLight
          ? Colors.black.withValues(alpha: 0.02)
          : Colors.white.withValues(alpha: 0.02),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    );
  }
}

/// Focus traversal policy that wraps around — pressing DPad past the last
/// item loops to the first, and vice-versa. Prevents focus loss on TV/gamepad.
class _WrapOrderedTraversalPolicy extends OrderedTraversalPolicy {
  /// Collects every focus node in [scope] that is wrapped by a
  /// [FocusTraversalOrder], sorted by [NumericFocusOrder].
  List<FocusNode> _orderedNodes(FocusScopeNode scope) {
    final nodes = <FocusNode>[];
    for (final node in scope.traversalDescendants) {
      final context = node.context;
      if (context == null) continue;
      final order = FocusTraversalOrder.maybeOf(context);
      if (order is NumericFocusOrder) {
        nodes.add(node);
      }
    }
    nodes.sort((a, b) {
      final orderA = FocusTraversalOrder.of(a.context!) as NumericFocusOrder;
      final orderB = FocusTraversalOrder.of(b.context!) as NumericFocusOrder;
      return orderA.order.compareTo(orderB.order);
    });
    return nodes;
  }

  /// Finds the ordered wrapper node that owns [node] (or [node] itself).
  int? _indexOfNode(List<FocusNode> nodes, FocusNode node) {
    for (var i = 0; i < nodes.length; i++) {
      final candidate = nodes[i];
      if (candidate == node || candidate.descendants.contains(node)) {
        return i;
      }
    }
    return null;
  }

  @override
  bool next(FocusNode currentNode) {
    if (!super.next(currentNode)) {
      final scope = currentNode.nearestScope;
      if (scope != null) {
        findFirstFocus(scope, ignoreCurrentFocus: true)?.requestFocus();
      }
    }
    return true;
  }

  @override
  bool previous(FocusNode currentNode) {
    if (!super.previous(currentNode)) {
      final scope = currentNode.nearestScope;
      if (scope != null) {
        findLastFocus(scope, ignoreCurrentFocus: true).requestFocus();
      }
    }
    return true;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);

    final nodes = _orderedNodes(scope);
    if (nodes.length < 2) {
      return super.inDirection(currentNode, direction);
    }

    final currentIndex = _indexOfNode(nodes, currentNode);
    if (currentIndex == null) {
      return super.inDirection(currentNode, direction);
    }

    final nextIndex = switch (direction) {
      TraversalDirection.up || TraversalDirection.left =>
        (currentIndex - 1 + nodes.length) % nodes.length,
      TraversalDirection.down || TraversalDirection.right =>
        (currentIndex + 1) % nodes.length,
    };

    nodes[nextIndex].requestFocus();
    return true;
  }
}
