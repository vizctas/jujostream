import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../providers/auth_provider.dart';
import '../../providers/cloud_mfa_provider.dart';
import '../onboarding/widgets/onboarding_glass_card.dart';
import '../onboarding/widgets/onboarding_glow.dart';

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

  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);

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
    _scrollOffset.dispose();
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
        // Trigger MFA checks
        final mfa = context.read<CloudMfaProvider>();
        await mfa.refresh();
        if (mfa.status == CloudMfaStatus.setupRequired) {
          await mfa.startTotpSetup();
        }
      } else {
        setState(() {
          _error = auth.cloudError ?? 'Fallo al iniciar sesión';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: $e';
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
          _info = 'Cuenta creada. Confirma tu correo para continuar.';
          _awaitingConfirmation = true;
        });
        _startConfirmationPolling();
      } else {
        setState(() {
          _error = auth.cloudError ?? 'Fallo al registrar la cuenta';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: $e';
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
        _info = 'Correo de confirmación reenviado. Revisa tu buzón.';
      });
    } catch (e) {
      setState(() {
        _error = 'Error al reenviar: $e';
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
      // Sync cloud computers
      unawaited(context.read<AuthProvider>().pullFromCloud());
      if (mounted) {
        // Proceed to PcViewScreen
        Navigator.of(context).pushReplacementNamed('/');
      }
    } else {
      _mfaCodeController.clear();
      _mfaFocus.requestFocus();
    }
  }

  Future<void> _cancelMfa() async {
    // If they cancel or click out, we MUST sign out to clear session
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


    // If MFA is blocked/gate required, we show the 2FA UI
    final showMfaPanel = mfa.status == CloudMfaStatus.setupRequired || 
                          mfa.status == CloudMfaStatus.verifyRequired ||
                          mfa.status == CloudMfaStatus.loading && mfa.blocksCloudUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        fit: StackFit.expand,
        children: [
          OnboardingGlow(scrollOffset: _scrollOffset),
          
          Positioned.fill(
            child: Opacity(
              opacity: 0.012,
              child: Image.network(
                'https://images.unsplash.com/photo-1541701494587-cb58502866ab?auto=format&fit=crop&w=400&q=80',
                fit: BoxFit.cover,
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: showMfaPanel 
                    ? _buildMfaLayout(context, mfa)
                    : _buildAuthLayout(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthLayout(BuildContext context) {
    return OnboardingGlassCard(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.cloud,
              size: 44,
              color: Color(0xFF818CF8),
            ).animate().scale(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 16),
            Text(
              _isSignUp ? 'Crear Cuenta Jujo Cloud' : 'Iniciar Sesión Jujo Cloud',
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
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Correo Electrónico', Icons.mail_outline),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'El correo es requerido';
                if (!email.contains('@')) return 'Ingresa un correo válido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              style: const TextStyle(color: Colors.white),
              obscureText: _obscurePassword,
              decoration: _inputDecoration('Contraseña', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleSubmit(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'La contraseña es requerida';
                if (value.length < 6) return 'Debe tener al menos 6 caracteres';
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
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
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
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.mark_email_unread_outlined, color: Color(0xFF818CF8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _info!,
                            style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (_awaitingConfirmation) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Esperando confirmación...',
                                style: TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : _resendEmail,
                            child: const Text('Reenviar', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
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
                backgroundColor: _isSignUp ? const Color(0xFF7C3AED) : const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _isSignUp ? 'Registrarse' : 'Iniciar Sesión',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: Text(
                _isSignUp
                    ? '¿Ya tienes una cuenta? Inicia sesión'
                    : '¿Necesitas sincronización? Regístrate',
              ),
            ),
            
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      // Proceed without Jujo Cloud as local mode
                      Navigator.of(context).pushReplacementNamed('/');
                    },
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text('Continuar en modo Local-only'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMfaLayout(BuildContext context, CloudMfaProvider mfa) {
    final isSetup = mfa.status == CloudMfaStatus.setupRequired;

    return OnboardingGlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.security,
            size: 40,
            color: Color(0xFF34D399),
          ).animate().shake(),
          const SizedBox(height: 16),
          Text(
            isSetup ? 'Configurar 2FA Requerido' : 'Verificación 2FA Requerida',
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
                ? 'Escanea el código QR con Google Authenticator o Authy para registrar tu cuenta, y escribe el código de 6 dígitos.'
                : 'Ingresa el código de 6 dígitos generado por tu aplicación de autenticación.',
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
                'Código secreto: ${mfa.enrollmentSecret ?? ""}',
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
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 6),
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: _inputDecoration('Código de 6 dígitos', Icons.onetwothree_outlined).copyWith(
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
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                mfa.error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
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
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading 
                      ? null 
                      : () => _handleMfaVerify(_mfaCodeController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34D399),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Text('Verificar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String labelText, IconData icon) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.02),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    );
  }
}
