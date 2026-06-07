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

  final List<FocusNode> _focusNodes = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'ob-page-$i'),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _pageGradients(tp)[_currentPage],
              ),
            ),
          ),
          PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
              _focusNodes[page].requestFocus();
            },
            children: [
              _buildHeroPage(tp, l, isLandscape),
              _buildGlancePage(
                tp: tp,
                icon: Icons.flash_on,
                title: 'Ultra Low Latency',
                subtitle: 'Zero-lag gameplay optimized for WebRTC with real-time responsiveness.',
                index: 1,
              ),
              _buildGlancePage(
                tp: tp,
                icon: Icons.gamepad,
                title: 'Gamepad First',
                subtitle: 'Native spatial navigation designed for physical controllers.',
                index: 2,
              ),
              _buildGlancePage(
                tp: tp,
                icon: Icons.cloud_sync,
                title: 'Jujo Cloud Sync',
                subtitle: 'Securely back up your servers and preferences.',
                index: 3,
              ),
            ],
          ),
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
                        color: tp.colors.isLight
                            ? Colors.black87
                            : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
                if (_currentPage < 3)
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
          Positioned(
            bottom: 40,
            left: 32,
            right: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(
                    4,
                    (index) => _buildPageDot(tp, index),
                  ),
                ),
                _buildActionButton(tp, l),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<List<Color>> _pageGradients(ThemeProvider tp) {
    final bg = tp.background;
    final accent = tp.accent;
    final accentLight = tp.accentLight;
    return [
      [bg, bg],
      [bg, accent.withValues(alpha: 0.04)],
      [bg, accentLight.withValues(alpha: 0.04)],
      [bg, accentLight.withValues(alpha: 0.06)],
    ];
  }

  Widget _buildPageDot(ThemeProvider tp, int index) {
    final isActive = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: isActive ? 24 : 8,
      decoration: BoxDecoration(
        color: isActive
            ? tp.accent
            : (tp.colors.isLight ? Colors.black26 : Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildActionButton(ThemeProvider tp, AppLocalizations l) {
    final isLast = _currentPage == 3;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.95, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: ElevatedButton.icon(
            focusNode: _focusNodes[_currentPage],
            onPressed: isLast ? _skipOnboarding : _nextPage,
            icon: Icon(isLast ? Icons.cloud_done : Icons.arrow_forward),
            label: Text(isLast ? 'Get Started' : 'Continue'),
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
          ),
        );
      },
    );
  }

  Widget _buildHeroPage(ThemeProvider tp, AppLocalizations l, bool isLandscape) {
    final isLight = tp.colors.isLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: tp.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: tp.accent.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'LOW LATENCY GAMING',
              style: TextStyle(
                color: tp.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
              .slideY(
                begin: 0.08,
                duration: 400.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 32),
          Text(
            isLandscape
                ? 'Stream your PC games.'
                : 'Stream your\nPC games.',
            style: TextStyle(
              color: isLight ? Colors.black87 : Colors.white,
              fontSize: isLandscape ? 36 : 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 80.ms, curve: Curves.easeOutCubic)
              .slideY(
                begin: 0.12,
                duration: 500.ms,
                delay: 80.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 16),
          Text(
            'Play your entire PC library on any device with near-zero latency.',
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 16,
              height: 1.5,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 160.ms, curve: Curves.easeOutCubic)
              .slideY(
                begin: 0.06,
                duration: 500.ms,
                delay: 160.ms,
                curve: Curves.easeOutCubic,
              ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _previewItem(tp, Icons.flash_on, 'Low Latency'),
              _previewItem(tp, Icons.high_quality, '4K HDR'),
              _previewItem(tp, Icons.gamepad, 'Gamepad'),
              _previewItem(tp, Icons.cloud_sync, 'Cloud'),
            ],
          )
              .animate()
              .fadeIn(duration: 400.ms, delay: 280.ms)
              .slideY(begin: 0.08, duration: 400.ms, delay: 280.ms),
        ],
      ),
    );
  }

  Widget _previewItem(ThemeProvider tp, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tp.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: tp.accent, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: tp.colors.isLight ? Colors.black54 : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildGlancePage({
    required ThemeProvider tp,
    required IconData icon,
    required String title,
    required String subtitle,
    required int index,
  }) {
    final isLight = tp.colors.isLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: Center(
        child: OnboardingSolidCard(
          backgroundColor: tp.surface,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: tp.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, color: tp.accent, size: 48),
              )
                  .animate()
                  .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
                  .slideY(
                    begin: 0.10,
                    duration: 400.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 32),
              Text(
                title,
                style: TextStyle(
                  color: isLight ? Colors.black87 : Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 80.ms, curve: Curves.easeOutCubic)
                  .slideY(
                    begin: 0.08,
                    duration: 500.ms,
                    delay: 80.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    color: isLight ? Colors.black54 : Colors.white70,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 160.ms, curve: Curves.easeOutCubic)
                  .slideY(
                    begin: 0.06,
                    duration: 500.ms,
                    delay: 160.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
