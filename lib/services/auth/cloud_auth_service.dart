import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudAuthSession {
  const CloudAuthSession({
    required this.accessToken,
    this.email,
    this.emailConfirmed = false,
  });

  final String accessToken;
  final String? email;
  final bool emailConfirmed;
}

abstract interface class CloudAuthService {
  bool get isConfigured;
  CloudAuthSession? get currentSession;
  Stream<CloudAuthSession?> get authStateChanges;

  Future<CloudAuthSession?> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  });

  Future<CloudAuthSession?> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    String? captchaToken,
  });

  Future<bool> signInWithGoogle({String? redirectTo});

  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
    String? captchaToken,
  });

  Future<void> signOut();
}

class DisabledCloudAuthService implements CloudAuthService {
  const DisabledCloudAuthService();

  @override
  bool get isConfigured => false;

  @override
  CloudAuthSession? get currentSession => null;

  @override
  Stream<CloudAuthSession?> get authStateChanges => const Stream.empty();

  @override
  Future<CloudAuthSession?> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) async => null;

  @override
  Future<CloudAuthSession?> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    String? captchaToken,
  }) async => null;

  @override
  Future<bool> signInWithGoogle({String? redirectTo}) async => false;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
    String? captchaToken,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class SupabaseCloudAuthService implements CloudAuthService {
  SupabaseCloudAuthService(this._client);

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  @override
  CloudAuthSession? get currentSession =>
      _fromSupabaseSession(_client.auth.currentSession);

  @override
  Stream<CloudAuthSession?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((data) {
        return _fromSupabaseSession(data.session);
      });

  @override
  Future<CloudAuthSession?> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
    return _fromSupabaseSession(response.session);
  }

  @override
  Future<CloudAuthSession?> signUp({
    required String email,
    required String password,
    String? emailRedirectTo,
    String? captchaToken,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
      captchaToken: captchaToken,
    );
    return _fromSupabaseSession(response.session);
  }

  @override
  Future<bool> signInWithGoogle({String? redirectTo}) {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      queryParams: const {'prompt': 'select_account'},
    );
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
    String? captchaToken,
  }) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
      captchaToken: captchaToken,
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  static CloudAuthSession? _fromSupabaseSession(Session? session) {
    if (session == null) return null;
    return CloudAuthSession(
      accessToken: session.accessToken,
      email: session.user.email,
      emailConfirmed: session.user.emailConfirmedAt != null,
    );
  }
}
