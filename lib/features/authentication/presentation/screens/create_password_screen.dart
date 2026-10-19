import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../face_verification/presentation/screens/face_enrollment_screen.dart';

class CreatePasswordScreen extends StatefulWidget {
  final String employeeCode;
  final String employeeName;

  const CreatePasswordScreen({
    super.key,
    required this.employeeCode,
    this.employeeName = 'موظف مناع',
  });

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _loading = false;

  String? _passwordError;
  String? _confirmError;

  bool get _hasMinLength => _passwordController.text.length >= 6;

  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_passwordController.text);

  bool get _passwordsMatch =>
      _confirmController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;

    FocusScope.of(context).unfocus();

    final password = _passwordController.text;
    final confirmPassword = _confirmController.text;

    setState(() {
      _passwordError = null;
      _confirmError = null;
    });

    if (password.isEmpty) {
      setState(() {
        _passwordError = 'أدخل كلمة المرور';
      });
      return;
    }

    if (password.length < 6) {
      setState(() {
        _passwordError = 'كلمة المرور يجب ألا تقل عن 6 أحرف';
      });
      return;
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      setState(() {
        _passwordError = 'يجب أن تحتوي كلمة المرور على رقم واحد على الأقل';
      });
      return;
    }

    if (confirmPassword.isEmpty) {
      setState(() {
        _confirmError = 'أعد كتابة كلمة المرور';
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _confirmError = 'كلمتا المرور غير متطابقتين';
      });
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final code = widget.employeeCode.trim().toUpperCase();

      final employeesRef = FirebaseDatabase.instance.ref('employees');

      final snapshot = await employeesRef
          .orderByChild('emp_code')
          .equalTo(code)
          .limitToFirst(1)
          .get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.children.isEmpty) {
        setState(() {
          _loading = false;
          _passwordError = 'تعذر العثور على بيانات الموظف';
        });
        return;
      }

      final employeeSnapshot = snapshot.children.first;

      final employeeKey = employeeSnapshot.key;

      if (employeeKey == null || employeeKey.trim().isEmpty) {
        setState(() {
          _loading = false;
          _passwordError = 'تعذر تحديد حساب الموظف';
        });
        return;
      }

      final employeeRef = FirebaseDatabase.instance.ref(
        'employees/$employeeKey',
      );

      await employeeRef.update({
        'password': password,
        'password_created': true,
        'account_version': 2,

        // لن نعتبر الحساب مكتملاً
        // إلا بعد إنهاء بصمة الوجه.
        'account_activated': false,

        'updated_at': ServerValue.timestamp,
      });

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء كلمة المرور بنجاح'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FaceEnrollmentScreen(
            employeeName: widget.employeeName,
            employeeCode: widget.employeeCode,
          ),
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'Create password Firebase error: '
        '${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;

        if (e.code == 'permission-denied') {
          _passwordError = 'لا توجد صلاحية لحفظ كلمة المرور';
        } else {
          _passwordError = 'حدث خطأ أثناء حفظ كلمة المرور';
        }
      });
    } catch (e) {
      debugPrint(
        'Create password error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _passwordError = 'تعذر حفظ كلمة المرور، حاول مرة أخرى';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _PasswordBackground(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      _TopBar(
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 27),
                      const _ProgressHeader(),
                      const SizedBox(height: 34),
                      const _PasswordVisual(),
                      const SizedBox(height: 23),
                      Text(
                        'أنشئ كلمة مرورك',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontSize: 20,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'ستستخدمها مع الكود الوظيفي\n'
                        'في المرات القادمة للدخول إلى حسابك',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12.5,
                              height: 1.6,
                            ),
                      ),
                      const SizedBox(height: 24),
                      _EmployeeBadge(
                        employeeCode: widget.employeeCode,
                        employeeName: widget.employeeName,
                      ),
                      const SizedBox(height: 23),
                      _PasswordField(
                        title: 'كلمة المرور',
                        hint: 'أدخل كلمة المرور',
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _hidePassword,
                        error: _passwordError,
                        onToggleVisibility: () {
                          setState(() {
                            _hidePassword = !_hidePassword;
                          });
                        },
                        onChanged: (_) {
                          setState(() {
                            _passwordError = null;
                          });
                        },
                        onSubmitted: (_) {
                          _confirmFocus.requestFocus();
                        },
                      ),
                      const SizedBox(height: 14),
                      _PasswordField(
                        title: 'تأكيد كلمة المرور',
                        hint: 'أعد كتابة كلمة المرور',
                        controller: _confirmController,
                        focusNode: _confirmFocus,
                        obscureText: _hideConfirmPassword,
                        error: _confirmError,
                        textInputAction: TextInputAction.done,
                        onToggleVisibility: () {
                          setState(() {
                            _hideConfirmPassword = !_hideConfirmPassword;
                          });
                        },
                        onChanged: (_) {
                          setState(() {
                            _confirmError = null;
                          });
                        },
                        onSubmitted: (_) => _continue(),
                      ),
                      const SizedBox(height: 17),
                      _PasswordRequirements(
                        hasMinLength: _hasMinLength,
                        hasNumber: _hasNumber,
                        passwordsMatch: _passwordsMatch,
                      ),
                      const SizedBox(height: 22),
                      _CreateButton(
                        loading: _loading,
                        onPressed: _continue,
                      ),
                      const SizedBox(height: 22),
                      const _SecurityNotice(),
                      const SizedBox(height: 22),
                    ],
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

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _TopBar({
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 43,
          height: 43,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.75),
            borderRadius: BorderRadius.circular(14),
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
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تفعيل الحساب',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
              ),
              Text(
                'إعداد حساب الموظف',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                    ),
              ),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onBack,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.68),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Colors.white,
              ),
            ),
            child: const Icon(
              Icons.arrow_forward_rounded,
              size: 19,
              color: AppColors.navy,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _ProgressLine(active: true),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _ProgressLine(active: true),
            ),
            SizedBox(width: 7),
            Expanded(
              child: _ProgressLine(active: false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'التحقق',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              'كلمة المرور',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              'بصمة الوجه',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final bool active;

  const _ProgressLine({
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: active ? AppColors.primary : AppColors.border.withOpacity(.75),
      ),
    );
  }
}

class _PasswordVisual extends StatelessWidget {
  const _PasswordVisual();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.sky.withOpacity(.055),
          ),
        ),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(.72),
            border: Border.all(
              color: Colors.white,
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.12),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 35,
            color: AppColors.primary,
          ),
        ),
        Positioned(
          bottom: 7,
          right: 10,
          child: Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmployeeBadge extends StatelessWidget {
  final String employeeCode;
  final String employeeName;

  const _EmployeeBadge({
    required this.employeeCode,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.lightBlue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
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
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  employeeCode,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .7,
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
            child: const Text(
              'تم التحقق',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final String title;
  final String hint;

  final TextEditingController controller;
  final FocusNode focusNode;

  final bool obscureText;
  final String? error;

  final VoidCallback onToggleVisibility;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  final TextInputAction textInputAction;

  const _PasswordField({
    required this.title,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.obscureText,
    required this.onToggleVisibility,
    required this.onChanged,
    required this.onSubmitted,
    this.error,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.82),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: error != null ? AppColors.error : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(.03),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            textInputAction: textInputAction,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.navy,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary.withOpacity(.6),
              ),
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                size: 19,
                color: AppColors.primary,
              ),
              suffixIcon: IconButton(
                onPressed: onToggleVisibility,
                icon: Icon(
                  obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                  color: AppColors.textSecondary,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 17,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 5,
              top: 6,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 13,
                  color: AppColors.error,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 10.5,
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

class _PasswordRequirements extends StatelessWidget {
  final bool hasMinLength;
  final bool hasNumber;
  final bool passwordsMatch;

  const _PasswordRequirements({
    required this.hasMinLength,
    required this.hasNumber,
    required this.passwordsMatch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withOpacity(.58),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.primary.withOpacity(.06),
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          _Requirement(
            text: '6 أحرف على الأقل',
            completed: hasMinLength,
          ),
          _Requirement(
            text: 'تحتوي على رقم',
            completed: hasNumber,
          ),
          _Requirement(
            text: 'متطابقتان',
            completed: passwordsMatch,
          ),
        ],
      ),
    );
  }
}

class _Requirement extends StatelessWidget {
  final String text;
  final bool completed;

  const _Requirement({
    required this.text,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed ? AppColors.success : Colors.white.withOpacity(.8),
            border: Border.all(
              color: completed ? AppColors.success : AppColors.border,
            ),
          ),
          child: completed
              ? const Icon(
                  Icons.check,
                  size: 11,
                  color: Colors.white,
                )
              : null,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: completed ? FontWeight.w600 : FontWeight.w400,
            color: completed ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CreateButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _CreateButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              AppColors.primaryDark,
              AppColors.primary,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(.20),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
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
                      'إنشاء كلمة المرور',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 13,
          color: AppColors.primary.withOpacity(.55),
        ),
        const SizedBox(width: 5),
        Text(
          'بيانات حسابك محمية ومخصصة لك فقط',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _PasswordBackground extends StatelessWidget {
  const _PasswordBackground();

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
                Color(0xFFF0F8FD),
                Color(0xFFF9FCFE),
              ],
            ),
          ),
        ),
        Positioned(
          top: -140,
          right: -120,
          child: _Glow(
            size: 330,
            color: AppColors.sky.withOpacity(.11),
          ),
        ),
        Positioned(
          left: -160,
          bottom: -120,
          child: _Glow(
            size: 390,
            color: AppColors.primary.withOpacity(.08),
          ),
        ),
        Positioned(
          top: 170,
          left: -120,
          child: Transform.rotate(
            angle: -.22,
            child: Container(
              width: 175,
              height: 440,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.14),
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
        sigmaX: 55,
        sigmaY: 55,
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
