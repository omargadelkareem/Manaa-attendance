import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/session_service.dart';
import '../../../attendance/presentation/screens/home_screen.dart';
import 'employee_code_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? employeeCode;

  const LoginScreen({
    super.key,
    this.employeeCode,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool _hidePassword = true;
  bool _rememberDevice = true;
  bool _loading = false;

  String? _codeError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();

    if (widget.employeeCode != null && widget.employeeCode!.trim().isNotEmpty) {
      _codeController.text = widget.employeeCode!.trim().toUpperCase();
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, .06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();

    _codeFocus.dispose();
    _passwordFocus.dispose();

    _animationController.dispose();

    super.dispose();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  bool _toBool(dynamic value) {
    if (value == true || value == 1) {
      return true;
    }

    final normalized = value?.toString().trim().toLowerCase();

    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
          value?.toString().trim() ?? '',
        ) ??
        0;
  }

  bool _isEmployeeActive(
    Map<String, dynamic> employee,
  ) {
    if (employee.containsKey('is_active')) {
      if (!_toBool(employee['is_active'])) {
        return false;
      }
    }

    final status =
        employee['app_status']?.toString().trim().toLowerCase() ?? '';

    const blockedStatuses = {
      'موقوف',
      'غير نشط',
      'محظور',
      'inactive',
      'blocked',
      'suspended',
    };

    return !blockedStatuses.contains(status);
  }

  String _getEmployeeName(
    Map<String, dynamic> employee,
  ) {
    final possibleNames = [
      employee['name'],
      employee['employee_name'],
      employee['full_name'],
      employee['fullName'],
    ];

    for (final value in possibleNames) {
      final name = value?.toString().trim() ?? '';

      if (name.isNotEmpty) {
        return name;
      }
    }

    return 'موظف مناع';
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _login() async {
    if (_loading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final code = _codeController.text.trim().toUpperCase();

    final password = _passwordController.text;

    setState(() {
      _codeError = null;
      _passwordError = null;
    });

    // -----------------------------
    // Validation
    // -----------------------------

    if (code.isEmpty) {
      setState(() {
        _codeError = 'أدخل الكود الوظيفي';
      });

      _codeFocus.requestFocus();
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _passwordError = 'أدخل كلمة المرور';
      });

      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // ========================================================
      // Search employee by employee code
      // ========================================================

      final snapshot = await FirebaseDatabase.instance
          .ref('employees')
          .orderByChild('emp_code')
          .equalTo(code)
          .limitToFirst(1)
          .get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.children.isEmpty) {
        setState(() {
          _loading = false;
          _codeError = 'الكود الوظيفي غير موجود';
        });

        _codeFocus.requestFocus();
        return;
      }

      final employeeSnapshot = snapshot.children.first;

      final rawValue = employeeSnapshot.value;

      if (rawValue is! Map) {
        setState(() {
          _loading = false;
          _codeError = 'تعذر قراءة بيانات الموظف';
        });

        return;
      }

      final employee = <String, dynamic>{};

      rawValue.forEach((key, value) {
        employee[key.toString()] = value;
      });

      // ========================================================
      // Employee status
      // ========================================================

      if (!_isEmployeeActive(employee)) {
        setState(() {
          _loading = false;
        });

        _showMessage(
          'الحساب موقوف حالياً، تواصل مع إدارة الموارد البشرية.',
          error: true,
        );

        return;
      }

      // ========================================================
      // Activation state
      // ========================================================

      final accountVersion = _toInt(employee['account_version']);

      final passwordCreated = _toBool(employee['password_created']);

      final faceEnrolled = _toBool(employee['face_enrolled']);

      final accountActivated = _toBool(employee['account_activated']);

      if (accountVersion < 2 ||
          !passwordCreated ||
          !faceEnrolled ||
          !accountActivated) {
        setState(() {
          _loading = false;
        });

        _showActivationRequiredDialog(
          code,
        );

        return;
      }

      // ========================================================
      // Password
      // ========================================================

      final savedPassword = employee['password']?.toString() ?? '';

      if (savedPassword.isEmpty) {
        setState(() {
          _loading = false;
        });

        _showActivationRequiredDialog(
          code,
        );

        return;
      }

      if (savedPassword != password) {
        setState(() {
          _loading = false;
          _passwordError = 'كلمة المرور غير صحيحة';
        });

        _passwordFocus.requestFocus();
        return;
      }

      // ========================================================
      // Employee data
      // ========================================================

      final employeeName = _getEmployeeName(employee);

      // ========================================================
      // GetStorage session
      // ========================================================

      if (_rememberDevice) {
        await SessionService.saveLogin(
          employeeCode: code,
          employeeName: employeeName,
        );
      } else {
        await SessionService.logout();
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      // ========================================================
      // HOME
      // ========================================================

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            employeeName: employeeName,
            employeeCode: code,
          ),
        ),
        (_) => false,
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'Login Firebase error: '
        '${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      if (e.code == 'permission-denied') {
        _showMessage(
          'لا توجد صلاحية للوصول إلى بيانات الموظفين.',
          error: true,
        );
      } else {
        _showMessage(
          'تعذر الاتصال بالنظام، حاول مرة أخرى.',
          error: true,
        );
      }
    } catch (e) {
      debugPrint(
        'Login error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage(
        'حدث خطأ أثناء تسجيل الدخول، حاول مرة أخرى.',
        error: true,
      );
    }
  }

  // ============================================================
  // ACTIVATION
  // ============================================================

  void _goToActivation({
    String? employeeCode,
  }) {
    if (_loading) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmployeeCodeScreen(),
      ),
    );
  }

  void _showActivationRequiredDialog(
    String employeeCode,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            titlePadding: const EdgeInsets.fromLTRB(
              20,
              22,
              20,
              0,
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              0,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(
              16,
              15,
              16,
              16,
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الحساب غير مُفعّل',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'يجب إكمال تفعيل حسابك أولاً قبل تسجيل الدخول.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child: const Text(
                  'إلغاء',
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );

                  _goToActivation(
                    employeeCode: employeeCode,
                  );
                },
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
                child: const Text(
                  'تفعيل الحساب',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.error : AppColors.navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      );
  }

  void _forgotPassword() {
    _showMessage(
      'لتغيير كلمة المرور تواصل مع إدارة الموارد البشرية.',
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LoginBackground(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(
                        context,
                      ).vertical,
                ),
                child: IntrinsicHeight(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          const SizedBox(
                            height: 24,
                          ),
                          const _BrandHeader(),
                          const Spacer(),
                          const _WelcomeVisual(),
                          const SizedBox(
                            height: 25,
                          ),
                          Text(
                            'مرحباً بعودتك',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                          ),
                          const SizedBox(
                            height: 6,
                          ),
                          Text(
                            'سجّل الدخول للوصول إلى حسابك\nوتسجيل حضورك وانصرافك',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.6,
                                ),
                          ),
                          const SizedBox(
                            height: 29,
                          ),
                          _LoginCard(
                            codeController: _codeController,
                            passwordController: _passwordController,
                            codeFocus: _codeFocus,
                            passwordFocus: _passwordFocus,
                            codeError: _codeError,
                            passwordError: _passwordError,
                            hidePassword: _hidePassword,
                            rememberDevice: _rememberDevice,
                            loading: _loading,
                            onCodeChanged: (_) {
                              if (_codeError != null) {
                                setState(() {
                                  _codeError = null;
                                });
                              }
                            },
                            onPasswordChanged: (_) {
                              if (_passwordError != null) {
                                setState(() {
                                  _passwordError = null;
                                });
                              }
                            },
                            onTogglePassword: () {
                              setState(() {
                                _hidePassword = !_hidePassword;
                              });
                            },
                            onRememberChanged: (value) {
                              setState(() {
                                _rememberDevice = value;
                              });
                            },
                            onForgotPassword: _forgotPassword,
                            onLogin: _login,
                          ),
                          const SizedBox(
                            height: 14,
                          ),
                          _ActivationEntry(
                            loading: _loading,
                            onTap: () => _goToActivation(),
                          ),
                          const SizedBox(
                            height: 20,
                          ),
                          const _HelpSection(),
                          const Spacer(),
                          const _SecurityFooter(),
                          const SizedBox(
                            height: 17,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BRAND HEADER
// ============================================================

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.74),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.07),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/manaa_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مناع للزجاج',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                'MANAA GLASS CO.',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary.withOpacity(.75),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white,
            ),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 12,
                color: AppColors.primary,
              ),
              SizedBox(width: 4),
              Text(
                'دخول آمن',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// WELCOME
// ============================================================

class _WelcomeVisual extends StatelessWidget {
  const _WelcomeVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.sky.withOpacity(.045),
            ),
          ),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withOpacity(.06),
              ),
              color: AppColors.primary.withOpacity(.035),
            ),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.80),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(.12),
                  blurRadius: 35,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 42,
              color: AppColors.primary,
            ),
          ),
          Positioned(
            bottom: 21,
            right: 23,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOGIN CARD
// ============================================================

class _LoginCard extends StatelessWidget {
  final TextEditingController codeController;
  final TextEditingController passwordController;

  final FocusNode codeFocus;
  final FocusNode passwordFocus;

  final String? codeError;
  final String? passwordError;

  final bool hidePassword;
  final bool rememberDevice;
  final bool loading;

  final ValueChanged<String> onCodeChanged;
  final ValueChanged<String> onPasswordChanged;

  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;

  final VoidCallback onForgotPassword;
  final VoidCallback onLogin;

  const _LoginCard({
    required this.codeController,
    required this.passwordController,
    required this.codeFocus,
    required this.passwordFocus,
    required this.codeError,
    required this.passwordError,
    required this.hidePassword,
    required this.rememberDevice,
    required this.loading,
    required this.onCodeChanged,
    required this.onPasswordChanged,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onForgotPassword,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 13,
          sigmaY: 13,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            17,
            20,
            17,
            17,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.61),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withOpacity(.92),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(.045),
                blurRadius: 30,
                offset: const Offset(0, 13),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'بيانات الدخول',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'استخدم بيانات حسابك الوظيفي',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                    ),
              ),
              const SizedBox(height: 19),
              _InputField(
                title: 'الكود الوظيفي',
                hint: 'مثال: MN-1025',
                controller: codeController,
                focusNode: codeFocus,
                error: codeError,
                prefixIcon: Icons.badge_outlined,
                textDirection: TextDirection.ltr,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(
                      r'[a-zA-Z0-9\-_]',
                    ),
                  ),
                ],
                onChanged: onCodeChanged,
                onSubmitted: (_) {
                  passwordFocus.requestFocus();
                },
              ),
              const SizedBox(height: 14),
              _InputField(
                title: 'كلمة المرور',
                hint: 'أدخل كلمة المرور',
                controller: passwordController,
                focusNode: passwordFocus,
                error: passwordError,
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: hidePassword,
                textInputAction: TextInputAction.done,
                onChanged: onPasswordChanged,
                onSubmitted: (_) => onLogin(),
                suffix: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    hidePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      onRememberChanged(
                        !rememberDevice,
                      );
                    },
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(
                            milliseconds: 180,
                          ),
                          width: 19,
                          height: 19,
                          decoration: BoxDecoration(
                            color: rememberDevice
                                ? AppColors.primary
                                : Colors.white.withOpacity(.65),
                            borderRadius: BorderRadius.circular(
                              6,
                            ),
                            border: Border.all(
                              color: rememberDevice
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: rememberDevice
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(
                          width: 7,
                        ),
                        const Text(
                          'تذكر هذا الجهاز',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: loading ? null : onForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'نسيت كلمة المرور؟',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              SizedBox(
                height: 53,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
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
                        blurRadius: 21,
                        offset: const Offset(
                          0,
                          9,
                        ),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: loading ? null : onLogin,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          17,
                        ),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(
                                width: 8,
                              ),
                              Icon(
                                Icons.login_rounded,
                                size: 18,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ACTIVATION ENTRY
// ============================================================

class _ActivationEntry extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _ActivationEntry({
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(.09),
          ),
        ),
        child: const Row(
          children: [
            _ActivationIcon(),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أول مرة تستخدم التطبيق؟',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'فعّل حسابك الوظيفي الآن',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 13,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivationIcon extends StatelessWidget {
  const _ActivationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.78),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.person_add_alt_1_rounded,
        size: 17,
        color: AppColors.primary,
      ),
    );
  }
}

// ============================================================
// INPUT
// ============================================================

class _InputField extends StatelessWidget {
  final String title;
  final String hint;

  final TextEditingController controller;
  final FocusNode focusNode;

  final String? error;
  final IconData prefixIcon;

  final bool obscureText;
  final TextDirection? textDirection;
  final TextInputAction textInputAction;

  final Widget? suffix;

  final List<TextInputFormatter>? inputFormatters;

  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _InputField({
    required this.title,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.prefixIcon,
    required this.onChanged,
    required this.onSubmitted,
    this.error,
    this.obscureText = false,
    this.textDirection,
    this.textInputAction = TextInputAction.next,
    this.suffix,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 3,
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.73),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: error == null ? AppColors.border : AppColors.error,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            textDirection: textDirection,
            textInputAction: textInputAction,
            autocorrect: false,
            enableSuggestions: !obscureText,
            inputFormatters: inputFormatters,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.navy,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintTextDirection: TextDirection.rtl,
              hintStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary.withOpacity(.55),
              ),
              prefixIcon: Icon(
                prefixIcon,
                size: 19,
                color: AppColors.primary,
              ),
              suffixIcon: suffix,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 16,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 4,
              top: 6,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 13,
                  color: AppColors.error,
                ),
                const SizedBox(
                  width: 5,
                ),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================
// HELP
// ============================================================

class _HelpSection extends StatelessWidget {
  const _HelpSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.40),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(.65),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: AppColors.lightBlue,
              borderRadius: BorderRadius.circular(
                10,
              ),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 17,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تواجه مشكلة في تسجيل الدخول؟',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                ),
                const SizedBox(
                  height: 1,
                ),
                Text(
                  'تواصل مع إدارة الموارد البشرية',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                      ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 12,
            color: AppColors.primary.withOpacity(.65),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SECURITY
// ============================================================

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 13,
          color: AppColors.primary.withOpacity(.5),
        ),
        const SizedBox(width: 5),
        Text(
          'نظام داخلي مخصص لموظفي شركة مناع للزجاج',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
                color: AppColors.textSecondary.withOpacity(.80),
              ),
        ),
      ],
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFFFAFDFF),
                Color(0xFFEFF7FC),
                Color(0xFFF7FBFE),
              ],
            ),
          ),
        ),
        Positioned(
          top: -130,
          right: -115,
          child: _Glow(
            size: 340,
            color: AppColors.sky.withOpacity(.12),
          ),
        ),
        Positioned(
          bottom: -150,
          left: -130,
          child: _Glow(
            size: 380,
            color: AppColors.primary.withOpacity(.09),
          ),
        ),
        Positioned(
          top: 140,
          left: -120,
          child: Transform.rotate(
            angle: -.23,
            child: Container(
              width: 175,
              height: 470,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(.07),
                    Colors.white.withOpacity(.35),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(.48),
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
