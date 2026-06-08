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

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;
  bool _awaitingConfirmation = false;
  bool _editingEmail = false;
  bool _editingPassword = false;
  bool _editingMfa = false;
  Timer? _confirmationTimer;
  String? _error;
  String? _info;

  final FocusNode _emailFocus = FocusNode(debugLabel: 'auth-email');
  final FocusNode _passwordFocus = FocusNode(debugLabel: 'auth-password');
  final FocusNode _submitFocus = FocusNode(debugLabel: 'auth-submit');
  final FocusNode _mfaFocus = FocusNode(debugLabel: 'auth-mfa');
  final FocusNode _mfaCancelFocus = FocusNode(debugLabel: 'auth-mfa-cancel');
  final FocusNode _mfaVerifyFocus = FocusNode(debugLabel: 'auth-mfa-verify');
  final FocusNode _toggleModeFocus = FocusNode(debugLabel: 'auth-toggle-mode');
  final FocusNode _localModeFocus = FocusNode(debugLabel: 'auth-local-mode');

  late final CloudMfaProvider _mfaProvider;
  bool _wasMfaPanelShown = false;

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    _submitFocus.addListener(_onFocusChange);
    _mfaFocus.addListener(_onFocusChange);
    _mfaCancelFocus.addListener(_onFocusChange);
    _mfaVerifyFocus.addListener(_onFocusChange);
    _toggleModeFocus.addListener(_onFocusChange);
    _localModeFocus.addListener(_onFocusChange);

    _emailFocus.onKeyEvent = _handleTextFieldKey;
    _passwordFocus.onKeyEvent = _handleTextFieldKey;
    _mfaFocus.onKeyEvent = _handleTextFieldKey;

    _mfaProvider = context.read<CloudMfaProvider>();
    _mfaProvider.addListener(_onMfaStateChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onMfaStateChange();
      if (!_wasMfaPanelShown) {
        _emailFocus.requestFocus();
      }
    });
  }

  void _onMfaStateChange() {
    if (!mounted) return;
    final status = _mfaProvider.status;
    final showMfaPanel = status == CloudMfaStatus.setupRequired ||
        status == CloudMfaStatus.verifyRequired ||
        (status == CloudMfaStatus.loading && _mfaProvider.blocksCloudUser);

    if (showMfaPanel && !_wasMfaPanelShown) {
      _wasMfaPanelShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mfaFocus.requestFocus();
        }
      });
    } else if (!showMfaPanel && _wasMfaPanelShown) {
      _wasMfaPanelShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _emailFocus.requestFocus();
        }
      });
    }
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        if (!_emailFocus.hasFocus) _editingEmail = false;
        if (!_passwordFocus.hasFocus) _editingPassword = false;
        if (!_mfaFocus.hasFocus) _editingMfa = false;
      });
    }
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    _mfaProvider.removeListener(_onMfaStateChange);
    _emailFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _submitFocus.removeListener(_onFocusChange);
    _mfaFocus.removeListener(_onFocusChange);
    _mfaCancelFocus.removeListener(_onFocusChange);
    _mfaVerifyFocus.removeListener(_onFocusChange);
    _toggleModeFocus.removeListener(_onFocusChange);
    _localModeFocus.removeListener(_onFocusChange);
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    _mfaFocus.dispose();
    _mfaCancelFocus.dispose();
    _mfaVerifyFocus.dispose();
    _toggleModeFocus.dispose();
    _localModeFocus.dispose();
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
        if (widget.popOnSuccess) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    } else {
      _mfaCodeController.clear();
      _mfaFocus.requestFocus();
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
      _editingMfa = false;
      _isLoading = false;
    });
    if (widget.popOnSuccess) {
      Navigator.of(context).pop(false);
    } else {
      _emailFocus.requestFocus();
    }
  }

  // ── Keyboard helpers (scoped to this screen only) ───────────────────────────
  void _dismissKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _handleBackspace(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.isCollapsed) {
      if (selection.baseOffset > 0) {
        final newText = text.substring(0, selection.baseOffset - 1) +
            text.substring(selection.baseOffset);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: selection.baseOffset - 1,
          ),
        );
      }
    } else {
      final newText = text.substring(0, selection.start) +
          text.substring(selection.end);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }

  KeyEventResult _handleTextFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isEmail = node == _emailFocus;
    final isPassword = node == _passwordFocus;
    final isMfa = node == _mfaFocus;

    final isEditing = (isEmail && _editingEmail) ||
        (isPassword && _editingPassword) ||
        (isMfa && _editingMfa);

    final controller = isEmail
        ? _emailController
        : (isPassword ? _passwordController : _mfaCodeController);

    if (isEditing) {
      if (key == LogicalKeyboardKey.gameButtonB ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        setState(() {
          if (isEmail) _editingEmail = false;
          if (isPassword) _editingPassword = false;
          if (isMfa) _editingMfa = false;
        });
        _dismissKeyboard();
        node.requestFocus();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.gameButtonX) {
        _handleBackspace(controller);
        if (isMfa) {
          final code = controller.text;
          if (code.length == 6) {
            _handleMfaVerify(code);
          }
        }
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    } else {
      if (key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        setState(() {
          if (isEmail) _editingEmail = true;
          if (isPassword) _editingPassword = true;
          if (isMfa) _editingMfa = true;
        });
        node.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowDown) {
        node.focusInDirection(TraversalDirection.down);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowUp) {
        node.focusInDirection(TraversalDirection.up);
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleGamepadKeyInAuthScreen(FocusNode _, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;

    final key = ev.logicalKey;
    final isEditing = _editingEmail || _editingPassword || _editingMfa;

    if (isEditing) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      final mfa = context.read<CloudMfaProvider>();
      final showMfaPanel = mfa.status == CloudMfaStatus.setupRequired ||
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

    final showMfaPanel = mfa.status == CloudMfaStatus.setupRequired ||
        mfa.status == CloudMfaStatus.verifyRequired ||
        (mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser);

    // Wrap the entire screen in a Focus with onKeyEvent so we can intercept
    // gamepad events BEFORE they bubble to system handlers.
    return Focus(
      onKeyEvent: _handleGamepadKeyInAuthScreen,
      child: Scaffold(
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                 TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  readOnly: !_editingEmail,
                  showCursor: true,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                  decoration: _inputDecoration('Email', Icons.mail_outline, tp, _emailFocus.hasFocus, _editingEmail),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onTap: () {
                    setState(() {
                      _editingEmail = true;
                    });
                    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                  },
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
                  readOnly: !_editingPassword,
                  showCursor: true,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration('Password', Icons.lock_outline, tp, _passwordFocus.hasFocus, _editingPassword)
                      .copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleSubmit(),
                  onTap: () {
                    setState(() {
                      _editingPassword = true;
                    });
                    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                  },
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
                                color: tp.accentLight, size: 18),
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
                              TextButton(
                                onPressed: _isLoading ? null : _resendEmail,
                                child: Text(
                                  'Resend',
                                  style: TextStyle(
                                    color: tp.accentLight,
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
                    backgroundColor: _submitFocus.hasFocus ? tp.accentLight : tp.accent,
                    foregroundColor: Colors.white,
                    side: _submitFocus.hasFocus
                        ? const BorderSide(color: Colors.white, width: 2)
                        : BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _submitFocus.hasFocus ? 8 : 0,
                    shadowColor: tp.accent.withValues(alpha: 0.5),
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
                  focusNode: _toggleModeFocus,
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                            _info = null;
                          }),
                  style: TextButton.styleFrom(
                    foregroundColor: _toggleModeFocus.hasFocus
                        ? tp.accentLight
                        : Colors.white70,
                    backgroundColor: _toggleModeFocus.hasFocus
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _toggleModeFocus.hasFocus
                            ? tp.accentLight.withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : 'Need sync? Create an account',
                  ),
                ),

                const SizedBox(height: 8),
                TextButton(
                  focusNode: _localModeFocus,
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.of(context).pushReplacementNamed('/');
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: _localModeFocus.hasFocus
                        ? tp.accentLight
                        : Colors.white38,
                    backgroundColor: _localModeFocus.hasFocus
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _localModeFocus.hasFocus
                            ? tp.accentLight.withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Continue in Local-only mode'),
                ),
              ],
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

              TextFormField(
                controller: _mfaCodeController,
                focusNode: _mfaFocus,
                readOnly: !_editingMfa,
                showCursor: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: _inputDecoration('6-digit code', Icons.onetwothree_outlined, tp, _mfaFocus.hasFocus, _editingMfa)
                    .copyWith(
                  counterText: '',
                ),
                onTap: () {
                  setState(() {
                    _editingMfa = true;
                  });
                  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                },
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
                      focusNode: _mfaCancelFocus,
                      onPressed: _isLoading ? null : _cancelMfa,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _mfaCancelFocus.hasFocus
                            ? tp.accentLight
                            : Colors.white70,
                        backgroundColor: _mfaCancelFocus.hasFocus
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.transparent,
                        side: BorderSide(
                          color: _mfaCancelFocus.hasFocus
                              ? tp.accentLight
                              : Colors.white.withValues(alpha: 0.2),
                          width: _mfaCancelFocus.hasFocus ? 2 : 1,
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
                      focusNode: _mfaVerifyFocus,
                      onPressed: _isLoading
                          ? null
                          : () => _handleMfaVerify(_mfaCodeController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _mfaVerifyFocus.hasFocus
                            ? tp.accent
                            : tp.accentLight,
                        foregroundColor: Colors.white,
                        side: _mfaVerifyFocus.hasFocus
                            ? const BorderSide(color: Colors.white, width: 2)
                            : BorderSide.none,
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
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String labelText,
    IconData icon,
    ThemeProvider tp,
    bool hasFocus,
    bool isEditing,
  ) {
    final isLight = tp.colors.isLight;
    final displayLabel = hasFocus && !isEditing ? '$labelText (Press Ⓐ to edit)' : labelText;
    return InputDecoration(
      labelText: displayLabel,
      labelStyle: TextStyle(
        color: hasFocus
            ? tp.accentLight
            : (isLight ? Colors.black45 : Colors.white54),
        fontSize: 14,
        fontWeight: hasFocus ? FontWeight.w600 : FontWeight.normal,
      ),
      prefixIcon: Icon(
        icon,
        color: hasFocus ? tp.accentLight : (isLight ? Colors.black38 : Colors.white38),
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
          width: 2.5,
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
          width: 2.5,
        ),
      ),
      filled: true,
      fillColor: hasFocus
          ? tp.accent.withValues(alpha: 0.08)
          : (isLight
              ? Colors.black.withValues(alpha: 0.02)
              : Colors.white.withValues(alpha: 0.02)),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    );
  }
}
