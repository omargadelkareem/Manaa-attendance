import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../attendance/presentation/screens/home_screen.dart';
import '../../authentication/presentation/screens/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scale = Tween<double>(
      begin: .94,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    _openNextScreen();
  }

  Future<void> _openNextScreen() async {
    await Future.delayed(
      const Duration(milliseconds: 2200),
    );

    if (!mounted) return;

    final hasSession = SessionService.hasValidSession;

    final Widget nextScreen;

    if (hasSession) {
      nextScreen = HomeScreen(
        employeeName: SessionService.employeeName.isEmpty
            ? 'موظف مناع'
            : SessionService.employeeName,
        employeeCode: SessionService.employeeCode,
      );
    } else {
      nextScreen = const LoginScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextScreen,
        transitionDuration: const Duration(
          milliseconds: 550,
        ),
        transitionsBuilder: (
          _,
          animation,
          __,
          child,
        ) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _ArchitecturalBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 4),
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: const _LogoContainer(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _fade,
                    child: Column(
                      children: [
                        Text(
                          'شركة مناع للزجاج',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'MANAA GLASS CO.',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 5),
                  FadeTransition(
                    opacity: _fade,
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 2,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(.35),
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          'نصنع رؤية أكثر وضوحاً',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: AppColors.primaryDark.withOpacity(.70),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoContainer extends StatelessWidget {
  const _LogoContainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      height: 176,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.60),
        borderRadius: BorderRadius.circular(42),
        border: Border.all(
          color: Colors.white.withOpacity(.90),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(.10),
            blurRadius: 45,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 15,
            sigmaY: 15,
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset(
              'assets/images/manaa_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchitecturalBackground extends StatelessWidget {
  const _ArchitecturalBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFBFDFF),
                Color(0xFFEAF5FC),
                Color(0xFFF7FBFE),
              ],
              stops: [
                0,
                .52,
                1,
              ],
            ),
          ),
        ),
        Positioned(
          top: -130,
          right: -100,
          child: _Glow(
            size: 320,
            color: AppColors.sky.withOpacity(.16),
          ),
        ),
        Positioned(
          bottom: -130,
          left: -110,
          child: _Glow(
            size: 340,
            color: AppColors.primary.withOpacity(.12),
          ),
        ),
        Positioned(
          top: 70,
          left: -95,
          child: Transform.rotate(
            angle: -.26,
            child: Container(
              width: 205,
              height: 530,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(.08),
                    Colors.white.withOpacity(.55),
                    AppColors.sky.withOpacity(.07),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(.65),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: -95,
          bottom: -60,
          child: Transform.rotate(
            angle: .25,
            child: Container(
              width: 190,
              height: 420,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(.12),
                    AppColors.sky.withOpacity(.07),
                    Colors.white.withOpacity(.38),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(.60),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 32,
          top: 0,
          bottom: 0,
          child: Container(
            width: .7,
            color: Colors.white.withOpacity(.55),
          ),
        ),
        Positioned(
          right: 46,
          top: 0,
          bottom: 0,
          child: Container(
            width: .7,
            color: Colors.white.withOpacity(.45),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: 60,
        sigmaY: 60,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
