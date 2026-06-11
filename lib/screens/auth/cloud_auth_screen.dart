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

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;
  bool _awaitingConfirmation = false;
  // Wrapper nodes: the gamepad navigation stops (focus ring).
  final _emailFocus = FocusNode(debugLabel: 'authEmail');
  final _passwordFocus = FocusNode(debugLabel: 'authPassword');
  final _submitFocus = FocusNode(debugLabel: 'authSubmit');
  final _mfaCodeFocus = FocusNode(debugLabel: 'mfaCode');

  // Inner edit nodes: focused only while typing with the native IME.
  // skipTraversal keeps them out of D-pad traversal.
  final _emailEditFocus = FocusNode(
    debugLabel: 'authEmailEdit',
    skipTraversal: true,
  );
  final _passwordEditFocus = FocusNode(
    debugLabel: 'authPasswordEdit',
    skipTraversal: true,
  );
  final _mfaEditFocus = FocusNode(
    debugLabel: 'mfaCodeEdit',
    skipTraversal: true,
  );

  Timer? _confirmationTimer;
  String? _error;
  String? _info;

  late final CloudMfaProvider _mfaProvider;
  bool _wasMfaPanelShown = false;

  @override
  void initState() {
    super.initState();
    _mfaProvider = context.read<CloudMfaProvider>();
    _mfaProvider.addListener(_onMfaStateChange);
    _mfaCodeController.addListener(_onMfaCodeChanged);
    GamepadNavigationService.setAuxButtonHandler(_handleAuxButton);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onMfaStateChange();
      if (!mounted) return;
      if (_wasMfaPanelShown) {
        _mfaCodeFocus.requestFocus();
      } else {
        _emailFocus.requestFocus();
      }
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
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (_handsOffMfaToGate) return; // gate instance owns MFA focus
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mfaCodeFocus.requestFocus();
      });
    } else if (!showMfaPanel && _wasMfaPanelShown) {
      _wasMfaPanelShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emailFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.removeListener(_onMfaCodeChanged);
    _mfaCodeController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    _mfaCodeFocus.dispose();
    _emailEditFocus.dispose();
    _passwordEditFocus.dispose();
    _mfaEditFocus.dispose();
    _mfaProvider.removeListener(_onMfaStateChange);
    GamepadNavigationService.clearAuxButtonHandler(_handleAuxButton);
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
        _popIfMfaGateTakesOver(mfa);
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
        if (mounted) _popIfMfaGateTakesOver(mfa);
      }
    });
  }

  /// Once a cloud session exists and MFA blocks it, the app root replaces the
  /// home widget with its own CloudAuthScreen (main.dart). If this instance
  /// was pushed on top, two live instances fight over focus and the hidden
  /// one wins — so hand off to the gate by popping this route.
  bool get _handsOffMfaToGate =>
      !widget.popOnSuccess &&
      !widget.isFirstRun &&
      (Navigator.maybeOf(context)?.canPop() ?? false);

  void _popIfMfaGateTakesOver(CloudMfaProvider mfa) {
    if (!mfa.blocksCloudUser) return;
    if (!_handsOffMfaToGate) return;
    Navigator.of(context).pop();
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
    }
  }

  Future<void> _cancelMfa() async {
    _confirmationTimer?.cancel();
    final auth = context.read<AuthProvider>();
    await auth.signOutFromCloud();
    if (!mounted) return;
    context.read<CloudMfaProvider>().reset();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _mfaCodeController.clear();
      _isLoading = false;
    });
    if (widget.popOnSuccess) {
      Navigator.of(context).pop(false);
    }
  }

  // ── Native IME editing helpers ───────────────────────────────────────────────
  bool get _isEditing =>
      _emailEditFocus.hasFocus ||
      _passwordEditFocus.hasFocus ||
      _mfaEditFocus.hasFocus;

  FocusNode? _activeEditFocus() {
    if (_emailEditFocus.hasFocus) return _emailEditFocus;
    if (_passwordEditFocus.hasFocus) return _passwordEditFocus;
    if (_mfaEditFocus.hasFocus) return _mfaEditFocus;
    return null;
  }

  FocusNode _wrapperFor(FocusNode editFocus) {
    if (editFocus == _emailEditFocus) return _emailFocus;
    if (editFocus == _passwordEditFocus) return _passwordFocus;
    return _mfaCodeFocus;
  }

  void _beginEdit(FocusNode editFocus) {
    editFocus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _stopEditing() {
    final edit = _activeEditFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (edit != null) _wrapperFor(edit).requestFocus();
  }

  void _onMfaCodeChanged() {
    if (!mounted || _isLoading) return;
    final digits = _mfaCodeController.text
        .replaceAll(RegExp(r'\D'), '')
        .split('')
        .take(6)
        .join();
    if (digits != _mfaCodeController.text) {
      _mfaCodeController.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
      return;
    }
    if (_mfaEditFocus.hasFocus && _mfaCodeController.text.length == 6) {
      _stopEditing();
      _handleMfaVerify(_mfaCodeController.text);
    }
  }

  // Programmatic edits can hit an invalid selection (baseOffset -1) before the
  // field ever had a caret.
  TextSelection _validSelection(TextEditingController controller) {
    final selection = controller.selection;
    return selection.isValid
        ? selection
        : TextSelection.collapsed(offset: controller.text.length);
  }

  void _backspaceController(TextEditingController controller) {
    final text = controller.text;
    final selection = _validSelection(controller);
    if (selection.isCollapsed) {
      if (selection.baseOffset > 0) {
        final newText =
            text.substring(0, selection.baseOffset - 1) +
            text.substring(selection.baseOffset);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.baseOffset - 1),
        );
      }
    } else {
      final newText =
          text.substring(0, selection.start) + text.substring(selection.end);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }

  bool get _showingMfaPanel {
    final mfa = context.read<CloudMfaProvider>();
    return mfa.status == CloudMfaStatus.setupRequired ||
        mfa.status == CloudMfaStatus.verifyRequired ||
        (mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser);
  }

  // ── Aux gamepad buttons (X/Y/LB/RB/Start) ────────────────────────────────
  // Fed by real KeyEvents on Android (_handleAuthScreenKey) and by nav-channel
  // strings on Windows (GamepadNavigationService.setAuxButtonHandler).
  void _handleAuxButton(String button) {
    if (!mounted || _isLoading) return;
    switch (button) {
      case 'x': // backspace
        final focused = _focusedFieldController();
        if (focused != null) _backspaceController(focused);
      case 'y': // password visibility
        if (_passwordFocus.hasFocus || _passwordEditFocus.hasFocus) {
          setState(() => _obscurePassword = !_obscurePassword);
        }
      case 'lb':
        _cycleField(-1);
      case 'rb':
        _cycleField(1);
      case 'start':
        _handleStart();
    }
  }

  TextEditingController? _focusedFieldController() {
    if (_emailFocus.hasFocus || _emailEditFocus.hasFocus) {
      return _emailController;
    }
    if (_passwordFocus.hasFocus || _passwordEditFocus.hasFocus) {
      return _passwordController;
    }
    if (_mfaCodeFocus.hasFocus || _mfaEditFocus.hasFocus) {
      return _mfaCodeController;
    }
    return null;
  }

  void _continueLocalOnly() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!widget.isFirstRun && (Navigator.maybeOf(context)?.canPop() ?? false)) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacementNamed('/');
  }

  Widget _orderedAuthFocus({
    required double order,
    required Widget child,
    FocusNode? focusNode,
    bool autofocus = false,
    bool excludeChildFocus = false,
    VoidCallback? onSelect,
    double borderRadius = 16,
  }) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        excludeChildFocus: excludeChildFocus,
        onSelect: onSelect,
        borderRadius: borderRadius,
        focusColor: Colors.white.withValues(alpha: 0.18),
        focusFillColor: Colors.white.withValues(alpha: 0.08),
        focusBorderWidth: 1.2,
        focusScale: 1.0,
        child: child,
      ),
    );
  }

  void _cycleField(int dir) {
    if (_showingMfaPanel) return; // single field — D-pad covers the rest
    if (_isEditing) {
      // Jump straight to editing the other field; IME stays open.
      _beginEdit(
        _emailEditFocus.hasFocus ? _passwordEditFocus : _emailEditFocus,
      );
      return;
    }
    final order = [_emailFocus, _passwordFocus, _submitFocus];
    var index = order.indexWhere((node) => node.hasFocus);
    if (index < 0) index = 0;
    order[(index + dir + order.length) % order.length].requestFocus();
  }

  void _handleStart() {
    if (_isEditing) _stopEditing();
    if (_showingMfaPanel) {
      final code = _mfaCodeController.text;
      if (code.length == 6) {
        _handleMfaVerify(code);
      } else {
        _mfaCodeFocus.requestFocus();
      }
    } else {
      _handleSubmit();
    }
  }

  KeyEventResult _handleAuthScreenKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Android delivers gamepad buttons as real KeyEvents.
    String? aux;
    if (key == LogicalKeyboardKey.gameButtonX ||
        key == LogicalKeyboardKey.backspace) {
      aux = 'x';
    } else if (key == LogicalKeyboardKey.gameButtonY) {
      aux = 'y';
    } else if (key == LogicalKeyboardKey.gameButtonLeft1) {
      aux = 'lb';
    } else if (key == LogicalKeyboardKey.gameButtonRight1) {
      aux = 'rb';
    } else if (key == LogicalKeyboardKey.gameButtonStart) {
      aux = 'start';
    }
    if (aux != null) {
      _handleAuxButton(aux);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape) {
      if (_isEditing) {
        _stopEditing();
        return KeyEventResult.handled;
      }
      if (_showingMfaPanel) {
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
      // Key-event tap only: must never take focus itself, or directional
      // traversal lands on this full-screen node and the ring vanishes.
      canRequestFocus: false,
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
                      // The home-route gate owns the MFA panel; a pushed
                      // instance just shows a spinner while it pops itself.
                      ? (_handsOffMfaToGate
                            ? const Center(child: CircularProgressIndicator())
                            : _buildMfaLayout(context, mfa, tp))
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
              policy: OrderedTraversalPolicy(),
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
                    focusNode: _emailFocus,
                    // Applies whenever the auth layout (re)mounts — initial open
                    // and return from the MFA panel — without racing the focus
                    // cleanup of the unmounted layout's nodes.
                    autofocus: true,
                    onSelect: () => _beginEdit(_emailEditFocus),
                    child: TextFormField(
                      controller: _emailController,
                      focusNode: _emailEditFocus,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        'Email',
                        Icons.mail_outline,
                        tp,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      onFieldSubmitted: (_) => _beginEdit(_passwordEditFocus),
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
                    focusNode: _passwordFocus,
                    onSelect: () => _beginEdit(_passwordEditFocus),
                    child: TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordEditFocus,
                      style: const TextStyle(color: Colors.white),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => _stopEditing(),
                      decoration:
                          _inputDecoration(
                            'Password',
                            Icons.lock_outline,
                            tp,
                          ).copyWith(
                            suffixIcon: ExcludeFocus(
                              child: IconButton(
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
                          ),
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
                                TvFocusable(
                                  excludeChildFocus: true,
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
                    focusNode: _submitFocus,
                    excludeChildFocus: true,
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
                    excludeChildFocus: true,
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
                    excludeChildFocus: true,
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
            policy: OrderedTraversalPolicy(),
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
                    // Plain Text: SelectableText is a focusable EditableText that
                    // traps D-pad focus (arrows move its caret, not traversal).
                    child: Text(
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
                  focusNode: _mfaCodeFocus,
                  autofocus: true,
                  onSelect: () => _beginEdit(_mfaEditFocus),
                  child: _OtpCodeInput(
                    controller: _mfaCodeController,
                    editFocusNode: _mfaEditFocus,
                    theme: tp,
                    onSubmitted: _stopEditing,
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
                        excludeChildFocus: true,
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
                        excludeChildFocus: true,
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

class _OtpCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode editFocusNode;
  final ThemeProvider theme;
  final VoidCallback onSubmitted;

  const _OtpCodeInput({
    required this.controller,
    required this.editFocusNode,
    required this.theme,
    required this.onSubmitted,
  });

  @override
  State<_OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<_OtpCodeInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.editFocusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.editFocusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final isEditing = widget.editFocusNode.hasFocus;
    final activeIndex = text.length.clamp(0, 5);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 1,
          height: 1,
          child: Opacity(
            opacity: 0.01,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.editFocusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => widget.onSubmitted(),
              enableSuggestions: false,
              autocorrect: false,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            final filled = index < text.length;
            final active = isEditing && index == activeIndex;
            return Expanded(
              child: Container(
                height: 54,
                margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.10),
                    width: active ? 1.2 : 1,
                  ),
                ),
                child: Text(
                  filled ? text[index] : '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
