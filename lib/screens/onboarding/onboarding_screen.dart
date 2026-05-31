import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/theme_provider.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/onboarding_glass_card.dart';
import '../auth/cloud_auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final FocusNode _page1FocusNode = FocusNode(debugLabel: 'ob-page-1');
  final FocusNode _page2FocusNode = FocusNode(debugLabel: 'ob-page-2');
  final FocusNode _page3FocusNode = FocusNode(debugLabel: 'ob-page-3');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _page1FocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _page1FocusNode.dispose();
    _page2FocusNode.dispose();
    _page3FocusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _skipOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_run_shown', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const CloudAuthScreen(isFirstRun: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final tp = context.watch<ThemeProvider>();
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: tp.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle ambient gradient — static, no animation, no blur
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

          // Main Pages
          PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
              if (page == 0) _page1FocusNode.requestFocus();
              if (page == 1) _page2FocusNode.requestFocus();
              if (page == 2) _page3FocusNode.requestFocus();
            },
            children: [
              _buildPage1(context, isLandscape, tp, l),
              _buildPage2(context, isLandscape, tp, l),
              _buildPage3(context, isLandscape, tp, l),
            ],
          ),

          // Top Header
          Positioned(
            top: 40,
            left: 32,
            right: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tp.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: tp.colors.isLight
                              ? Colors.black12
                              : Colors.white12,
                        ),
                      ),
                      child: Icon(
                        Icons.bolt,
                        color: tp.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'JUJO.STREAM',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: tp.colors.isLight ? Colors.black87 : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
                if (_currentPage < 2)
                  TextButton(
                    onPressed: _skipOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: tp.colors.isLight
                          ? Colors.black54
                          : Colors.white70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      l.skip,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Navigation Controls
          Positioned(
            bottom: 40,
            left: 32,
            right: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Page Indicator Dots
                Row(
                  children: List.generate(
                    3,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 8),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? tp.accent
                            : (tp.colors.isLight
                                ? Colors.black26
                                : Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                // Action Buttons
                Row(
                  children: [
                    if (_currentPage > 0)
                      IconButton(
                        onPressed: _prevPage,
                        icon: Icon(
                          Icons.arrow_back_ios_new,
                          color: tp.colors.isLight
                              ? Colors.black54
                              : Colors.white70,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: tp.surface,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    const SizedBox(width: 12),
                    if (_currentPage < 2)
                      ElevatedButton.icon(
                        focusNode: _currentPage == 0
                            ? _page1FocusNode
                            : _page2FocusNode,
                        onPressed: _nextPage,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tp.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        focusNode: _page3FocusNode,
                        onPressed: _skipOnboarding,
                        icon: const Icon(Icons.cloud_done),
                        label: const Text('Continue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tp.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Slide 1: Welcome & Streaming Quality (Bento Grid)
  Widget _buildPage1(
    BuildContext context,
    bool isLandscape,
    ThemeProvider tp,
    AppLocalizations l,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildIntroCard(tp, l),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento1(tp, l),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildIntroCard(tp, l),
                ),
                const SizedBox(height: 20),
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento1(tp, l),
                ),
              ],
            ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  // Slide 2: Gamepad-First Control (Bento Grid)
  Widget _buildPage2(
    BuildContext context,
    bool isLandscape,
    ThemeProvider tp,
    AppLocalizations l,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento2Left(tp, l),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: _buildFeatureBento2Right(tp, l),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento2Left(tp, l),
                ),
                const SizedBox(height: 20),
                Expanded(
                  flex: 3,
                  child: _buildFeatureBento2Right(tp, l),
                ),
              ],
            ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  // Slide 3: Jujo Cloud Sync (Bento Grid)
  Widget _buildPage3(
    BuildContext context,
    bool isLandscape,
    ThemeProvider tp,
    AppLocalizations l,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildCloudIntroCard(tp, l),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildCloudBentoRight(tp, l),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildCloudIntroCard(tp, l),
                ),
                const SizedBox(height: 20),
                Expanded(
                  flex: 2,
                  child: _buildCloudBentoRight(tp, l),
                ),
              ],
            ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  // Helper widgets for Slide 1
  Widget _buildIntroCard(ThemeProvider tp, AppLocalizations l) {
    final isLight = tp.colors.isLight;
    return OnboardingSolidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _badge(
            label: 'LOW LATENCY EXPERIENCE',
            color: tp.accent,
            isLight: isLight,
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.08, duration: 400.ms),
          const SizedBox(height: 24),
          Text(
            'Take your games anywhere.',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 80.ms)
              .slideY(begin: 0.12, duration: 500.ms),
          const SizedBox(height: 16),
          Text(
            'JUJO Stream lets you broadcast your PC library directly to your devices with cinematic quality, HDR support, and real-time sync.',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 160.ms)
              .slideY(begin: 0.06, duration: 500.ms),
        ],
      ),
    );
  }

  Widget _buildFeatureBento1(ThemeProvider tp, AppLocalizations l) {
    return Column(
      children: [
        Expanded(
          child: OnboardingSolidCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tp.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.flash_on, color: tp.accent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Ultra Low Latency',
                        style: TextStyle(
                          color: tp.colors.isLight ? Colors.black87 : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Optimized for WebRTC with zero-lag gameplay.',
                        style: TextStyle(
                          color: tp.colors.isLight ? Colors.black45 : Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 550.ms, delay: 100.ms).slideY(
            begin: 0.10,
            duration: 550.ms,
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: OnboardingSolidCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tp.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.high_quality,
                    color: tp.accentLight,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'HDR & 4K Support',
                        style: TextStyle(
                          color: tp.colors.isLight ? Colors.black87 : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Absolute clarity for modern displays.',
                        style: TextStyle(
                          color: tp.colors.isLight ? Colors.black45 : Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 550.ms, delay: 200.ms).slideY(
            begin: 0.10,
            duration: 550.ms,
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }

  // Helper widgets for Slide 2
  Widget _buildFeatureBento2Left(ThemeProvider tp, AppLocalizations l) {
    final isLight = tp.colors.isLight;
    return OnboardingSolidCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gamepad, color: tp.accent, size: 64),
          const SizedBox(height: 24),
          Text(
            'Gamepad-First',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Native spatial navigation optimized for physical controllers.',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideY(
      begin: 0.10,
      duration: 500.ms,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildFeatureBento2Right(ThemeProvider tp, AppLocalizations l) {
    final isLight = tp.colors.isLight;
    return OnboardingSolidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Absolute Control & Mapping',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _bentoItem(
            icon: Icons.alt_route,
            title: 'Fluid D-pad Navigation',
            desc: 'Smart focus and automatic retention in windows and menus without breaking flow.',
            accentColor: tp.accent,
            isLight: isLight,
          ),
          const SizedBox(height: 12),
          _bentoItem(
            icon: Icons.settings_input_component,
            title: 'Custom Mapping',
            desc: 'Automatic A/B/X/Y button swap and native support for Nintendo, PlayStation and Xbox.',
            accentColor: tp.accentLight,
            isLight: isLight,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 550.ms, delay: 200.ms).slideY(
      begin: 0.10,
      duration: 550.ms,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _bentoItem({
    required IconData icon,
    required String title,
    required String desc,
    required Color accentColor,
    required bool isLight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accentColor, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isLight ? Colors.black87 : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  color: isLight ? Colors.black45 : Colors.white54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widgets for Slide 3
  Widget _buildCloudIntroCard(ThemeProvider tp, AppLocalizations l) {
    final isLight = tp.colors.isLight;
    return OnboardingSolidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _badge(
            label: 'AUTOMATIC SYNC',
            color: tp.accentLight,
            isLight: isLight,
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.08, duration: 400.ms),
          const SizedBox(height: 24),
          Text(
            'Sync your servers.',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 80.ms)
              .slideY(begin: 0.12, duration: 500.ms),
          const SizedBox(height: 16),
          Text(
            'Connect to Jujo Cloud to securely back up and sync your computers, states, and preferences automatically in seconds. All protected with military-grade encryption.',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 160.ms)
              .slideY(begin: 0.06, duration: 500.ms),
        ],
      ),
    );
  }

  Widget _buildCloudBentoRight(ThemeProvider tp, AppLocalizations l) {
    final isLight = tp.colors.isLight;
    return Column(
      children: [
        Expanded(
          child: OnboardingSolidCard(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_sync, color: tp.accentLight, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Cloud Sync',
                  style: TextStyle(
                    color: isLight ? Colors.black87 : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Automatically save your server list.',
                  style: TextStyle(
                    color: isLight ? Colors.black45 : Colors.white54,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 550.ms, delay: 100.ms).slideY(
            begin: 0.10,
            duration: 550.ms,
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: OnboardingSolidCard(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.security, color: tp.accent, size: 36),
                const SizedBox(height: 12),
                Text(
                  '2FA Security',
                  style: TextStyle(
                    color: isLight ? Colors.black87 : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Protected login via Two-Factor Authentication.',
                  style: TextStyle(
                    color: isLight ? Colors.black45 : Colors.white54,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 550.ms, delay: 200.ms).slideY(
            begin: 0.10,
            duration: 550.ms,
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }

  Widget _badge({
    required String label,
    required Color color,
    required bool isLight,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
