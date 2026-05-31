class SupabaseRuntimeConfig {
  const SupabaseRuntimeConfig({
    required this.url,
    required this.publishableKey,
    this.emailRedirectTo,
    this.oauthRedirectTo,
  });

  factory SupabaseRuntimeConfig.fromEnvironment() {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const nextPublicUrl = String.fromEnvironment('NEXT_PUBLIC_SUPABASE_URL');
    const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    const nextPublicKey = String.fromEnvironment(
      'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
    );
    const emailRedirectTo = String.fromEnvironment(
      'SUPABASE_EMAIL_REDIRECT_TO',
    );
    const oauthRedirectTo = String.fromEnvironment(
      'SUPABASE_OAUTH_REDIRECT_TO',
    );

    return SupabaseRuntimeConfig(
      url: supabaseUrl.isNotEmpty ? supabaseUrl : nextPublicUrl,
      publishableKey: supabaseKey.isNotEmpty ? supabaseKey : nextPublicKey,
      emailRedirectTo: emailRedirectTo.isNotEmpty ? emailRedirectTo : null,
      oauthRedirectTo: oauthRedirectTo.isNotEmpty ? oauthRedirectTo : null,
    );
  }

  final String url;
  final String publishableKey;
  final String? emailRedirectTo;
  final String? oauthRedirectTo;

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  void validateForInitialization() {
    if (!isConfigured) {
      throw StateError(
        'Supabase requires SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }
  }
}

abstract final class SupabaseConfig {
  static final current = SupabaseRuntimeConfig.fromEnvironment();
}
