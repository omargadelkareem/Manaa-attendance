import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import 'create_password_screen.dart';

class EmployeeCodeScreen extends StatefulWidget {
  const EmployeeCodeScreen({super.key});

  @override
  State<EmployeeCodeScreen> createState() => _EmployeeCodeScreenState();
}

class _EmployeeCodeScreenState extends State<EmployeeCodeScreen> {
  final _codeController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool _toBool(dynamic value) {
    if (value == true || value == 1) {
      return true;
    }

    final normalized = value?.toString().trim().toLowerCase();

    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Future<void> _continue() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    final code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() {
        _error = 'من فضلك أدخل الكود الوظيفي';
      });
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final employeesRef = FirebaseDatabase.instance.ref('employees');

      final snapshot = await employeesRef
          .orderByChild('emp_code')
          .equalTo(code)
          .limitToFirst(1)
          .get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.children.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = 'الكود الوظيفي غير موجود';
        });
        return;
      }

      final employeeSnapshot = snapshot.children.first;
      final rawData = employeeSnapshot.value;

      if (rawData is! Map) {
        setState(() {
          _isLoading = false;
          _error = 'تعذر قراءة بيانات الموظف';
        });
        return;
      }

      final employee = Map<String, dynamic>.from(rawData);

      final employeeId = employeeSnapshot.key?.trim() ?? '';

      final employeeCode =
          (employee['emp_code'] ?? code).toString().trim().toUpperCase();

      final employeeName = (employee['name'] ?? '').toString().trim();

      final appStatus = (employee['app_status'] ?? '').toString().trim();

      /*
       * التحقق من حالة الموظف
       *
       * بعض الموظفين القدامى قد لا يحتوي سجلهم
       * على is_active، لذلك في حالة عدم وجوده
       * نعتبر الموظف فعالاً.
       */

      final isActiveValue = employee['is_active'];

      final isActive = isActiveValue == null ? true : _toBool(isActiveValue);

      if (!isActive) {
        setState(() {
          _isLoading = false;
          _error = 'حساب الموظف غير نشط، تواصل مع الموارد البشرية';
        });
        return;
      }

      final normalizedStatus = appStatus.toLowerCase();

      if (appStatus == 'موقوف' ||
          normalizedStatus == 'inactive' ||
          normalizedStatus == 'blocked' ||
          normalizedStatus == 'suspended') {
        setState(() {
          _isLoading = false;
          _error = 'حساب الموظف موقوف، تواصل مع الموارد البشرية';
        });
        return;
      }

      /*
       * مهم جداً:
       *
       * النسخة التجريبية القديمة كانت قد تسجل:
       *
       * password_created = true
       *
       * رغم أن كلمة المرور لم تكن مرتبطة بالنظام
       * الحقيقي الحالي.
       *
       * لذلك لا نعتمد على password_created وحدها.
       *
       * الحساب الجديد الحقيقي سيحتوي على:
       *
       * account_version = 2
       *
       * وبالتالي:
       *
       * password_created = true
       * account_version = 2
       *
       * معناها أن الموظف فعّل الحساب على النظام الجديد.
       */

      final accountVersion = int.tryParse(
            employee['account_version']?.toString().trim() ?? '',
          ) ??
          0;

      final passwordCreated = _toBool(employee['password_created']);

      final isNewAccountActivated = accountVersion >= 2 && passwordCreated;

      if (isNewAccountActivated) {
        setState(() {
          _isLoading = false;
          _error = 'تم تفعيل هذا الحساب بالفعل، استخدم شاشة تسجيل الدخول';
        });
        return;
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      debugPrint(
        'Employee verified: '
        'id=$employeeId '
        'code=$employeeCode '
        'name=$employeeName '
        'accountVersion=$accountVersion '
        'oldPasswordCreated=$passwordCreated',
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreatePasswordScreen(
            employeeCode: employeeCode,
            employeeName: employeeName.isEmpty ? 'موظف مناع' : employeeName,
          ),
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'Firebase error: ${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;

        if (e.code == 'permission-denied') {
          _error = 'لا توجد صلاحية للوصول لبيانات الموظفين';
        } else if (e.code == 'network-error' || e.code == 'disconnected') {
          _error = 'تحقق من اتصال الإنترنت وحاول مرة أخرى';
        } else {
          _error = 'حدث خطأ أثناء الاتصال بقاعدة البيانات';
        }
      });
    } catch (e, stackTrace) {
      debugPrint('Employee verification error: $e');

      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = 'تعذر الاتصال، تحقق من الإنترنت وحاول مرة أخرى';
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
          const _EmployeeCodeBackground(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 22),

                      // Header
                      const _Header(),

                      const Spacer(),

                      // Main content
                      const _IdentityIcon(),

                      const SizedBox(height: 25),

                      Text(
                        'أهلاً بك في مناع',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                      ),

                      const SizedBox(height: 7),

                      Text(
                        'أدخل الكود الوظيفي الخاص بك\nللبدء في تفعيل حسابك',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.65,
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                      ),

                      const SizedBox(height: 30),

                      _EmployeeCodeField(
                        controller: _codeController,
                        focusNode: _focusNode,
                        error: _error,
                        onChanged: (_) {
                          if (_error != null) {
                            setState(() => _error = null);
                          }
                        },
                        onSubmitted: (_) => _continue(),
                      ),

                      const SizedBox(height: 17),

                      _ContinueButton(
                        loading: _isLoading,
                        onPressed: _continue,
                      ),

                      const SizedBox(height: 22),

                      const _HelpText(),

                      const Spacer(),

                      const _SecurityFooter(),

                      const SizedBox(height: 18),
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.76),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/manaa_logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مناع للزجاج',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 1),
            Text(
              'نظام الحضور والانصراف',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IdentityIcon extends StatelessWidget {
  const _IdentityIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(.64),
        border: Border.all(
          color: Colors.white,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(.11),
            blurRadius: 38,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withOpacity(.10),
                AppColors.sky.withOpacity(.16),
              ],
            ),
          ),
          child: const Icon(
            Icons.badge_outlined,
            size: 34,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _EmployeeCodeField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const _EmployeeCodeField({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(
            'الكود الوظيفي',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: error != null
                  ? AppColors.error
                  : focusNode.hasFocus
                      ? AppColors.primary
                      : AppColors.border,
              width: error != null || focusNode.hasFocus ? 1.3 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[a-zA-Z0-9\-_]'),
              ),
              LengthLimitingTextInputFormatter(30),
            ],
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: .7,
              color: AppColors.navy,
            ),
            decoration: InputDecoration(
              hintText: 'مثال: MN-1025',
              hintTextDirection: TextDirection.rtl,
              hintStyle: TextStyle(
                fontSize: 13,
                letterSpacing: 0,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary.withOpacity(.62),
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(9),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 18,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: error == null
              ? const SizedBox(height: 0)
              : Padding(
                  key: ValueKey(error),
                  padding: const EdgeInsetsDirectional.only(
                    start: 5,
                    top: 7,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _ContinueButton({
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
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shadowColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'متابعة',
                      style: TextStyle(
                        fontSize: 14,
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

class _HelpText extends StatelessWidget {
  const _HelpText();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.help_outline_rounded,
          size: 15,
          color: AppColors.textSecondary.withOpacity(.75),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'لا تعرف الكود الوظيفي؟ تواصل مع الموارد البشرية',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 13,
          color: AppColors.primary.withOpacity(.55),
        ),
        const SizedBox(width: 5),
        Text(
          'دخول آمن لموظفي شركة مناع فقط',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: AppColors.textSecondary.withOpacity(.75),
              ),
        ),
      ],
    );
  }
}

class _EmployeeCodeBackground extends StatelessWidget {
  const _EmployeeCodeBackground();

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
          top: -120,
          left: -110,
          child: _Glow(
            size: 300,
            color: AppColors.sky.withOpacity(.12),
          ),
        ),
        Positioned(
          right: -150,
          bottom: -110,
          child: _Glow(
            size: 370,
            color: AppColors.primary.withOpacity(.09),
          ),
        ),

        // subtle glass sheet
        Positioned(
          top: 130,
          right: -125,
          child: Transform.rotate(
            angle: .22,
            child: Container(
              width: 180,
              height: 430,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.16),
                border: Border.all(
                  color: Colors.white.withOpacity(.55),
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
