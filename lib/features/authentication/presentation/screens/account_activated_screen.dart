import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import 'login_screen.dart';

class AccountActivatedScreen extends StatefulWidget {
  final String employeeName;
  final String employeeCode;

  const AccountActivatedScreen({
    super.key,
    required this.employeeName,
    required this.employeeCode,
  });

  @override
  State<AccountActivatedScreen> createState() => _AccountActivatedScreenState();
}

class _AccountActivatedScreenState extends State<AccountActivatedScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;

  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
      lowerBound: .97,
      upperBound: 1.025,
    )..repeat(reverse: true);

    _fade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _scale = Tween<double>(
      begin: .85,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutBack,
      ),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, .12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SuccessBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 20,
              ),
              child: Column(
                children: [
                  const _BrandHeader(),
                  const Spacer(),
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: ScaleTransition(
                        scale: _pulseController,
                        child: const _SuccessVisual(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: Column(
                        children: [
                          Text(
                            'تم تفعيل حسابك',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'أهلاً ${widget.employeeName}',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'تم إعداد حسابك وبصمة الوجه بنجاح\nيمكنك الآن استخدام نظام الحضور والانصراف',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.65,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 27),
                  FadeTransition(
                    opacity: _fade,
                    child: _EmployeeTicket(
                      employeeName: widget.employeeName,
                      employeeCode: widget.employeeCode,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: _fade,
                    child: const _CompletedSteps(),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _fade,
                    child: _EnterButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => LoginScreen(
                              employeeCode: widget.employeeCode,
                            ),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  FadeTransition(
                    opacity: _fade,
                    child: const _Footer(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white,
            ),
          ),
          child: Image.asset(
            'assets/images/manaa_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مناع للزجاج',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
            ),
            Text(
              'نظام الحضور والانصراف',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SuccessVisual extends StatelessWidget {
  const _SuccessVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(.035),
            ),
          ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(.055),
              border: Border.all(
                color: AppColors.success.withOpacity(.08),
              ),
            ),
          ),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(.82),
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withOpacity(.18),
                  blurRadius: 40,
                  spreadRadius: 2,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 77,
                height: 77,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF37BE88),
                      Color(0xFF168C5C),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 42,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 17,
            right: 30,
            child: _SmallDot(size: 8),
          ),
          const Positioned(
            bottom: 29,
            left: 22,
            child: _SmallDot(size: 6),
          ),
          Positioned(
            top: 40,
            left: 13,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(.35),
              ),
            ),
          ),
          Positioned(
            bottom: 21,
            right: 42,
            child: Transform.rotate(
              angle: .7,
              child: Icon(
                Icons.add_rounded,
                size: 16,
                color: AppColors.success.withOpacity(.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallDot extends StatelessWidget {
  final double size;

  const _SmallDot({
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.success.withOpacity(.45),
      ),
    );
  }
}

class _EmployeeTicket extends StatelessWidget {
  final String employeeName;
  final String employeeCode;

  const _EmployeeTicket({
    required this.employeeName,
    required this.employeeCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(.035),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.badge_outlined,
              size: 22,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  employeeCode,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .8,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(.09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 13,
                  color: AppColors.success,
                ),
                SizedBox(width: 4),
                Text(
                  'حساب مفعّل',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedSteps extends StatelessWidget {
  const _CompletedSteps();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withOpacity(.45),
        borderRadius: BorderRadius.circular(17),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _CompletedItem(
              icon: Icons.badge_outlined,
              text: 'تم التحقق',
            ),
          ),
          _StepConnector(),
          Expanded(
            child: _CompletedItem(
              icon: Icons.lock_outline_rounded,
              text: 'كلمة المرور',
            ),
          ),
          _StepConnector(),
          Expanded(
            child: _CompletedItem(
              icon: Icons.face_outlined,
              text: 'بصمة الوجه',
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompletedItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.85),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 17,
                color: AppColors.primary,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -1,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 23,
      height: 1,
      margin: const EdgeInsets.only(bottom: 18),
      color: AppColors.success.withOpacity(.28),
    );
  }
}

class _EnterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EnterButton({
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              AppColors.primaryDark,
              AppColors.primary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'الدخول إلى حسابي',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.arrow_back_rounded,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 13,
          color: AppColors.primary.withOpacity(.5),
        ),
        const SizedBox(width: 5),
        Text(
          'حسابك جاهز للاستخدام بشكل آمن',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
              ),
        ),
      ],
    );
  }
}

class _SuccessBackground extends StatelessWidget {
  const _SuccessBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFFFAFDFF),
                Color(0xFFF0F9F7),
                Color(0xFFF1F8FC),
                Color(0xFFFBFDFF),
              ],
              stops: [
                0,
                .34,
                .68,
                1,
              ],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -120,
          child: _Glow(
            size: 350,
            color: AppColors.sky.withOpacity(.10),
          ),
        ),
        Positioned(
          bottom: -160,
          left: -130,
          child: _Glow(
            size: 390,
            color: AppColors.success.withOpacity(.08),
          ),
        ),
        Positioned(
          right: -120,
          top: 170,
          child: Transform.rotate(
            angle: .22,
            child: Container(
              width: 170,
              height: 430,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.12),
                border: Border.all(
                  color: Colors.white.withOpacity(.50),
                ),
              ),
            ),
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
