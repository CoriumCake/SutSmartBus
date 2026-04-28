import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();

    // Remove the native splash screen so our custom one can fade in or be shown immediately
    FlutterNativeSplash.remove();

    // Navigate to the map screen after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.go('/map');
    });
  }
  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFfa5f00);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/animations/Bus.json',
              width: 200,
              height: 200,
            ),
            const SizedBox(height: 32),
            const Text(
              'SUT SMART BUS',
              style: TextStyle(
                fontFamily: 'MN KaLong',
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
