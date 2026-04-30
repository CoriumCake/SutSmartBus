import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/legal_consent_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _bounceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _bounceAnimation;
  bool _minimumDelayComplete = false;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();

    // Fade Animation (Once)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    // Bounce Animation (Looping)
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<Offset>(
      begin: const Offset(
          0.0, -0.03), // เลขติดลบน้อยๆ ให้ขยับขึ้นนิดเดียว (เด้งเบาๆ)
      end: const Offset(0.0, 0.03), // เลขบวกน้อยๆ ให้ขยับลงนิดเดียว (เด้งเบาๆ)
    ).animate(CurvedAnimation(
      parent: _bounceController,
      curve: Curves.easeInOut,
    ));

    // Remove the native splash screen so our custom one can fade in or be shown immediately
    FlutterNativeSplash.remove();

    ref.listenManual<LegalConsentState>(legalConsentProvider, (_, next) {
      _attemptNavigation(next);
    });

    Future.delayed(const Duration(seconds: 3), () {
      _minimumDelayComplete = true;
      _attemptNavigation(ref.read(legalConsentProvider));
    });
  }

  void _attemptNavigation(LegalConsentState consentState) {
    if (!mounted ||
        _didNavigate ||
        !_minimumDelayComplete ||
        consentState.isLoading) {
      return;
    }

    _didNavigate = true;
    context.go(consentState.hasAccepted ? '/map' : '/legal-consent');
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFfa5f00);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: _bounceAnimation,
                child: Image.asset(
                  'assets/images/bus_icon.png', // Using the new logo
                  width: 200,
                  height: 200,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 80,
                child: TextLiquidFill(
                  text: 'SUT SMART BUS',
                  waveColor: Colors.white,
                  boxBackgroundColor: backgroundColor,
                  textStyle: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  loadDuration: const Duration(seconds: 3),
                  waveDuration: const Duration(milliseconds: 800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
