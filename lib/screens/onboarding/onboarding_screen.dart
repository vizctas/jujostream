import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/onboarding_glow.dart';
import 'widgets/onboarding_glass_card.dart';
import '../auth/cloud_auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  int _currentPage = 0;

  final FocusNode _page1FocusNode = FocusNode(debugLabel: 'ob-page-1');
  final FocusNode _page2FocusNode = FocusNode(debugLabel: 'ob-page-2');
  final FocusNode _page3FocusNode = FocusNode(debugLabel: 'ob-page-3');

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.hasClients) {
        _scrollOffset.value = _pageController.offset;
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _page1FocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollOffset.dispose();
    _page1FocusNode.dispose();
    _page2FocusNode.dispose();
    _page3FocusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 650),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient Radial Background Glows
          OnboardingGlow(scrollOffset: _scrollOffset),
          
          // Noise/Static Layer for premium texture
          Positioned.fill(
            child: Opacity(
              opacity: 0.015,
              child: Image.network(
                'https://images.unsplash.com/photo-1541701494587-cb58502866ab?auto=format&fit=crop&w=400&q=80',
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Main Pages
          PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
              if (page == 0) _page1FocusNode.requestFocus();
              if (page == 1) _page2FocusNode.requestFocus();
              if (page == 2) _page3FocusNode.requestFocus();
            },
            children: [
              _buildPage1(context, isLandscape),
              _buildPage2(context, isLandscape),
              _buildPage3(context, isLandscape),
            ],
          ),

          // Top Header (Logo + Skip)
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
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Icon(
                        Icons.bolt,
                        color: Color(0xFF4F46E5),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'JUJO.STREAM',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        color: Colors.white,
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
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text(
                      'Saltar',
                      style: TextStyle(
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
                            ? const Color(0xFF4F46E5)
                            : Colors.white.withValues(alpha: 0.2),
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
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    const SizedBox(width: 12),
                    if (_currentPage < 2)
                      ElevatedButton.icon(
                        focusNode: _currentPage == 0 ? _page1FocusNode : _page2FocusNode,
                        onPressed: _nextPage,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continuar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        focusNode: _page3FocusNode,
                        onPressed: _skipOnboarding, // proceed to Cloud sync login
                        icon: const Icon(Icons.cloud_done),
                        label: const Text('Comenzar con Jujo Cloud'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 10,
                          shadowColor: const Color(0xFF7C3AED).withValues(alpha: 0.4),
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
  Widget _buildPage1(BuildContext context, bool isLandscape) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildIntroCard(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento1(),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildIntroCard(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento1(),
                ),
              ],
            ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  // Slide 2: Gamepad-First Control (Bento Grid)
  Widget _buildPage2(BuildContext context, bool isLandscape) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento2Left(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: _buildFeatureBento2Right(),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildFeatureBento2Left(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 3,
                  child: _buildFeatureBento2Right(),
                ),
              ],
            ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  // Slide 3: Jujo Cloud Sync (Bento Grid)
  Widget _buildPage3(BuildContext context, bool isLandscape) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 100, 32, 120),
      child: isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildCloudIntroCard(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildCloudBentoRight(),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildCloudIntroCard(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: _buildCloudBentoRight(),
                ),
              ],
            ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.05, end: 0, duration: 500.ms);
  }

  // Helper widgets for Slide 1
  Widget _buildIntroCard() {
    return OnboardingGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
            ),
            child: const Text(
              'EXPERIENCIA DE BAJA LATENCIA',
              style: TextStyle(
                color: Color(0xFF818CF8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Lleva tus juegos a cualquier parte.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'JUJO Stream te permite transmitir la biblioteca de tu PC directamente a tus dispositivos con calidad cinematográfica, soporte HDR y sincronización en tiempo real.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBento1() {
    return Column(
      children: [
        Expanded(
          child: OnboardingGlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.flash_on, color: Colors.cyanAccent, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Ultra baja latencia',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Optimizado para WebRTC para partidas sin retraso.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: OnboardingGlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.high_quality, color: Color(0xFF818CF8), size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Soporte HDR y 4K',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Nitidez absoluta para pantallas modernas.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper widgets for Slide 2
  Widget _buildFeatureBento2Left() {
    return OnboardingGlassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gamepad, color: Color(0xFF818CF8), size: 64),
          const SizedBox(height: 24),
          const Text(
            'Gamepad-First',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Navegación espacial nativa optimizada para mandos físicos.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBento2Right() {
    return OnboardingGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Control y Mapeo Absoluto',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _bentoItem(
            icon: Icons.alt_route,
            title: 'Navegación fluida por D-pad',
            desc: 'Foco inteligente y retención automática en ventanas y menús sin romper el flujo.',
          ),
          const SizedBox(height: 12),
          _bentoItem(
            icon: Icons.settings_input_component,
            title: 'Mapeo Personalizado',
            desc: 'Intercambio automático de botones A/B/X/Y y soporte nativo para Nintendo, PlayStation y Xbox.',
          ),
        ],
      ),
    );
  }

  Widget _bentoItem({required IconData icon, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4F46E5), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widgets for Slide 3
  Widget _buildCloudIntroCard() {
    return OnboardingGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
            ),
            child: const Text(
              'SINCRONIZACIÓN AUTOMÁTICA',
              style: TextStyle(
                color: Color(0xFFA78BFA),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sincroniza tus servidores.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Conéctate a Jujo Cloud para respaldar y sincronizar tus ordenadores, estados, y preferencias de forma segura y automatizada en segundos. Todo protegido con cifrado de grado militar.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudBentoRight() {
    return Column(
      children: [
        Expanded(
          child: OnboardingGlassCard(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_sync, color: Color(0xFFA78BFA), size: 36),
                const SizedBox(height: 12),
                const Text(
                  'Cloud Sync',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Guarda automáticamente tu lista de servidores.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: OnboardingGlassCard(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, color: Colors.tealAccent, size: 36),
                const SizedBox(height: 12),
                const Text(
                  'Seguridad 2FA',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Inicio protegido mediante Autenticación de Doble Factor.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
