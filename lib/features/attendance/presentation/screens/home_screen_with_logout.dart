import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:manaa_attendance/core/services/attendance_record_service.dart';
import 'package:manaa_attendance/core/services/session_service.dart';
import 'package:manaa_attendance/features/face_verification/presentation/screens/face_verification_screen.dart';
import 'package:manaa_attendance/features/authentication/presentation/screens/login_screen.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/services/attendance_service.dart';
import '../../../../core/services/native_location_service.dart';

class HomeScreen extends StatefulWidget {
  final String employeeName;
  final String employeeCode;

  const HomeScreen({
    super.key,
    this.employeeName = 'موظف مناع',
    this.employeeCode = '',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late Timer _timer;

  DateTime _now = DateTime.now();

  late final AnimationController _pulseController;
  late final AnimationController _entryController;

  int _navIndex = 0;

  bool _employeeLoading = true;
  bool _employeeLoadFailed = false;

  bool _checkingAttendance = false;

  String? _employeeKey;

  Map<String, dynamic> _employeeData = {};

  String _employeeName = '';
  String _employeeCode = '';
  String _positionName = '';
  String _branchName = '';
  String _workArea = '';
  String _photoUrl = '';
  String _hireDate = '';
  String _phone = '';

  AttendanceLocationCheck? _lastLocationCheck;

  @override
  void initState() {
    super.initState();

    _employeeName = widget.employeeName.trim();
    _employeeCode = widget.employeeCode.trim().toUpperCase();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        setState(() {
          _now = DateTime.now();
        });
      },
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      lowerBound: .97,
      upperBound: 1.025,
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _loadEmployee();
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    _entryController.dispose();

    super.dispose();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) {
      return {};
    }

    final result = <String, dynamic>{};

    raw.forEach((key, value) {
      result[key.toString()] = value;
    });

    return result;
  }

  String _readString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }

  // ============================================================
  // EMPLOYEE
  // ============================================================

  Future<void> _loadEmployee() async {
    if (_employeeCode.isEmpty) {
      if (!mounted) return;

      setState(() {
        _employeeLoading = false;
        _employeeLoadFailed = true;
      });

      return;
    }

    if (mounted) {
      setState(() {
        _employeeLoading = true;
        _employeeLoadFailed = false;
      });
    }

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('employees')
          .orderByChild('emp_code')
          .equalTo(_employeeCode)
          .limitToFirst(1)
          .get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.children.isEmpty) {
        setState(() {
          _employeeLoading = false;
          _employeeLoadFailed = true;
        });

        return;
      }

      final employeeSnapshot = snapshot.children.first;

      final data = _asMap(
        employeeSnapshot.value,
      );

      if (data.isEmpty) {
        setState(() {
          _employeeLoading = false;
          _employeeLoadFailed = true;
        });

        return;
      }

      final name = _readString(
        data,
        [
          'name',
          'employee_name',
          'full_name',
          'fullName',
        ],
      );

      final code = _readString(
        data,
        [
          'emp_code',
          'employee_code',
          'employeeCode',
        ],
      );

      final position = _readString(
        data,
        [
          'position_name',
          'job_title',
          'position',
          'jobTitle',
        ],
      );

      final branch = _readString(
        data,
        [
          'branch_name',
          'branch',
          'branchName',
        ],
      );

      final workArea = _readString(
        data,
        [
          'work_area',
          'workArea',
          'address',
        ],
      );

      final photo = _readString(
        data,
        [
          'photo_url',
          'photo',
          'image_url',
          'avatar_url',
        ],
      );

      final hireDate = _readString(
        data,
        [
          'hire_date',
          'joining_date',
          'date_of_hire',
        ],
      );

      final phone = _readString(
        data,
        [
          'phone',
          'mobile',
          'phone_number',
        ],
      );

      if (!mounted) return;

      setState(() {
        _employeeKey = employeeSnapshot.key;

        _employeeData = data;

        if (name.isNotEmpty) {
          _employeeName = name;
        }

        if (code.isNotEmpty) {
          _employeeCode = code.toUpperCase();
        }

        _positionName = position;
        _branchName = branch;
        _workArea = workArea;
        _photoUrl = photo;
        _hireDate = hireDate;
        _phone = phone;

        _employeeLoading = false;
        _employeeLoadFailed = false;
      });
    } on FirebaseException catch (e) {
      debugPrint(
        'Home employee Firebase error: '
        '${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _employeeLoading = false;
        _employeeLoadFailed = true;
      });
    } catch (e) {
      debugPrint(
        'Home employee load error: $e',
      );

      if (!mounted) return;

      setState(() {
        _employeeLoading = false;
        _employeeLoadFailed = true;
      });
    }
  }

  // ============================================================
  // DISPLAY DATA
  // ============================================================

  String get _displayName {
    if (_employeeName.trim().isNotEmpty) {
      return _employeeName.trim();
    }

    return 'موظف مناع';
  }

  String get _displayPosition {
    if (_positionName.trim().isNotEmpty) {
      return _positionName.trim();
    }

    return 'موظف';
  }

  String get _displayBranch {
    if (_branchName.trim().isNotEmpty) {
      return _branchName.trim();
    }

    if (_workArea.trim().isNotEmpty) {
      return _workArea.trim();
    }

    return 'لم يتم تحديد موقع العمل';
  }

  String get _time {
    return DateFormat('hh:mm').format(_now);
  }

  String get _period {
    return _now.hour >= 12 ? 'م' : 'ص';
  }

  String get _greeting {
    if (_now.hour < 12) {
      return 'صباح الخير';
    }

    return 'مساء الخير';
  }

  // ============================================================
  // ATTENDANCE
  // ============================================================

  Future<void> _attendancePressed() async {
    if (_checkingAttendance) {
      return;
    }

    if (_employeeLoading) {
      _showMessage(
        'انتظر حتى يتم تحميل بيانات الموظف.',
      );
      return;
    }

    if (_employeeLoadFailed) {
      _showMessage(
        'تعذر تحميل بيانات الموظف. حاول تحديث الصفحة.',
        error: true,
      );
      return;
    }

    if (_employeeKey == null ||
        _employeeKey!.trim().isEmpty ||
        _employeeData.isEmpty) {
      _showMessage(
        'تعذر تحديد حساب الموظف.',
        error: true,
      );
      return;
    }

    setState(() {
      _checkingAttendance = true;
      _lastLocationCheck = null;
    });

    _showLocationProgress();

    try {
      final result = await AttendanceService.verifyLocation(
        employeeKey: _employeeKey!,
        employee: _employeeData,
      );

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      setState(() {
        _checkingAttendance = false;
        _lastLocationCheck = result;
      });

      if (!result.inside) {
        _showOutsideLocationDialog(result);
        return;
      }

      _showLocationSuccessDialog(result);
    } on AttendanceException catch (e) {
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      setState(() {
        _checkingAttendance = false;
      });

      if (e.code == 'LOCATION_DISABLED') {
        _showLocationDisabledDialog();
        return;
      }

      _showMessage(
        e.message,
        error: true,
      );
    } on NativeLocationException catch (e) {
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      setState(() {
        _checkingAttendance = false;
      });

      if (e.code == 'LOCATION_DISABLED') {
        _showLocationDisabledDialog();
        return;
      }

      if (e.code == 'PERMISSION_DENIED') {
        _showPermissionDialog();
        return;
      }

      _showMessage(
        e.message,
        error: true,
      );
    } catch (e) {
      debugPrint(
        'Attendance location error: $e',
      );

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      setState(() {
        _checkingAttendance = false;
      });

      _showMessage(
        'تعذر التحقق من موقعك حالياً. حاول مرة أخرى.',
        error: true,
      );
    }
  }

  void _showLocationProgress() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: _LocationCheckingDialog(),
        );
      },
    );
  }

  void _showLocationSuccessDialog(
    AttendanceLocationCheck result,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.success,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'تم التحقق من الموقع',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'أنت داخل نطاق ${result.workplace.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 17),
                _LocationResultRow(
                  title: 'المسافة',
                  value: '${result.distance.round()} متر',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'النطاق المسموح',
                  value: '${result.workplace.radius.round()} متر',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'دقة GPS',
                  value: '${result.deviceLocation.accuracy.round()} متر',
                ),
                const SizedBox(height: 19),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);

                      _continueToFaceVerification(
                        result,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.face_retouching_natural_rounded,
                          size: 19,
                        ),
                        SizedBox(width: 7),
                        Text(
                          'متابعة التحقق من الوجه',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOutsideLocationDialog(
    AttendanceLocationCheck result,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.error,
                    size: 29,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'أنت خارج نطاق العمل',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'لا يمكن تسجيل الحضور من موقعك الحالي.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary.withOpacity(.9),
                  ),
                ),
                const SizedBox(height: 17),
                _LocationResultRow(
                  title: 'موقع العمل',
                  value: result.workplace.name,
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'المسافة الحالية',
                  value: '${result.distance.round()} متر',
                ),
                _LocationResultRow(
                  title: 'إحداثيات الموبايل',
                  value:
                      '${result.deviceLocation.latitude.toStringAsFixed(6)}, '
                      '${result.deviceLocation.longitude.toStringAsFixed(6)}',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'إحداثيات موقع العمل',
                  value: '${result.workplace.latitude.toStringAsFixed(6)}, '
                      '${result.workplace.longitude.toStringAsFixed(6)}',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'المسافة',
                  value: '${result.distance.round()} متر',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'النطاق',
                  value: '${result.workplace.radius.round()} متر',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'دقة GPS',
                  value: '${result.deviceLocation.accuracy.round()} متر',
                ),
                const SizedBox(height: 7),
                _LocationResultRow(
                  title: 'النطاق المسموح',
                  value: '${result.workplace.radius.round()} متر',
                ),
                const SizedBox(height: 19),
                SizedBox(
                  width: double.infinity,
                  height: 47,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);

                      _attendancePressed();
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'إعادة التحقق',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLocationDisabledDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.location_disabled_rounded,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'خدمة الموقع مغلقة',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'يجب تشغيل GPS حتى يتمكن النظام من التحقق من وجودك داخل موقع العمل.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await NativeLocationService.openLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'تشغيل الموقع',
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'صلاحية الموقع مطلوبة',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          content: const Text(
            'تسجيل الحضور يحتاج إلى صلاحية الموقع أثناء استخدام التطبيق.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                await NativeLocationService.openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'فتح الإعدادات',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _continueToFaceVerification(
    AttendanceLocationCheck result,
  ) async {
    if (!mounted) return;

    // ============================================================
    // 1. فتح شاشة التحقق من الوجه
    // ============================================================

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AttendanceFaceVerificationScreen(
          employeeCode: _employeeCode,
          employeeName: _employeeName,
        ),
      ),
    );

    if (!mounted) return;

    // المستخدم رجع أو التحقق من الوجه لم ينجح
    if (verified != true) {
      return;
    }

    // ============================================================
    // 2. التأكد أن بيانات الموظف جاهزة
    // ============================================================

    if (_employeeKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر تحميل بيانات الموظف. حاول مرة أخرى.',
          ),
        ),
      );

      return;
    }

    // ============================================================
    // 3. إعادة فحص الموقع بعد نجاح الوجه
    // ============================================================

    AttendanceLocationCheck finalLocationCheck;

    try {
      finalLocationCheck = await AttendanceService.verifyLocation(
        employeeKey: _employeeKey!,
        employee: _employeeData,
      );

      if (!finalLocationCheck.inside) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إلغاء التسجيل لأنك خارج نطاق موقع العمل.',
            ),
          ),
        );

        return;
      }
    } on AttendanceException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message,
          ),
        ),
      );

      return;
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إعادة التحقق من الموقع. حاول مرة أخرى.',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    // ============================================================
    // 4. تسجيل الحضور / الانصراف في Firebase
    // ============================================================

    try {
      final attendance = await AttendanceRecordService.recordAttendance(
        employeeKey: _employeeKey!,
        employeeCode: _employeeCode,
        employeeName: _employeeName,
        locationCheck: finalLocationCheck,
        faceLivenessVerified: true,
      );

      if (!mounted) return;

      // ==========================================================
      // 5. تحويل وقت التسجيل إلى HH:mm
      // ==========================================================

      final dateTime = DateTime.fromMillisecondsSinceEpoch(
        attendance.timestamp,
      );

      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');

      final time = '$hour:$minute';

      final isCheckIn = attendance.action == AttendanceAction.checkIn;

      // ==========================================================
      // 6. رسالة النجاح
      // ==========================================================

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCheckIn
                ? 'تم تسجيل الحضور بنجاح الساعة $time'
                : 'تم تسجيل الانصراف بنجاح الساعة $time',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // مؤقتًا لإعادة بناء الشاشة.
      // بعد نجاح الاختبار هنربط بيانات اليوم
      // بالـ Home بشكل مباشر.
      setState(() {});
    } on AttendanceRecordException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'حدث خطأ أثناء تسجيل الحضور. حاول مرة أخرى.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } // ============================================================
  // MESSAGE
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
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _ManaaHomeBackground(),
          SafeArea(
            bottom: false,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entryController,
                curve: Curves.easeOut,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadEmployee,
                      color: AppColors.primary,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          120,
                        ),
                        child: Column(
                          children: [
                            _EmployeeHeader(
                              greeting: _greeting,
                              employeeName: _displayName,
                              employeeCode: _employeeCode,
                              positionName: _displayPosition,
                              photoUrl: _photoUrl,
                              loading: _employeeLoading,
                              loadFailed: _employeeLoadFailed,
                              onRetry: _loadEmployee,
                            ),

                            const SizedBox(height: 27),

                            _TodayLabel(
                              now: _now,
                            ),

                            const SizedBox(height: 7),

                            _LiveClock(
                              time: _time,
                              period: _period,
                            ),

                            const SizedBox(height: 25),

                            _AttendanceStage(
                              pulseController: _pulseController,
                              loading: _checkingAttendance,
                              onTap: _attendancePressed,
                            ),

                            const SizedBox(height: 24),

                            _LocationStatus(
                              branchName: _displayBranch,
                              loading: _employeeLoading,
                              lastCheck: _lastLocationCheck,
                            ),

                            const SizedBox(height: 31),

                            const _ShiftJourney(),

                            // الاختصارات تم حذفها بالكامل.
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 17,
            child: SafeArea(
              top: false,
              child: _ManaaNavigation(
                selectedIndex: _navIndex,
                onChanged: (index) {
                  setState(() {
                    _navIndex = index;
                  });

                  if (index == 3) {
                    _showEmployeeInfo();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    if (!mounted) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.logout_rounded,
                color: AppColors.primary,
                size: 21,
              ),
              SizedBox(width: 8),
              Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          content: const Text(
            'هل تريد تسجيل الخروج من حسابك على هذا الجهاز؟',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) return;

    await SessionService.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  void _showEmployeeInfo() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _EmployeeInfoSheet(
          employeeName: _displayName,
          employeeCode: _employeeCode,
          positionName: _displayPosition,
          branchName: _displayBranch,
          photoUrl: _photoUrl,
          hireDate: _hireDate,
          phone: _phone,
          onLogout: () {
            Navigator.of(context).pop();
            _logout();
          },
        );
      },
    );
  }
}

// ============================================================
// HEADER
// ============================================================

class _EmployeeHeader extends StatelessWidget {
  final String greeting;
  final String employeeName;
  final String employeeCode;
  final String positionName;
  final String photoUrl;

  final bool loading;
  final bool loadFailed;

  final VoidCallback onRetry;

  const _EmployeeHeader({
    required this.greeting,
    required this.employeeName,
    required this.employeeCode,
    required this.positionName,
    required this.photoUrl,
    required this.loading,
    required this.loadFailed,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EmployeeAvatar(
          name: employeeName,
          photoUrl: photoUrl,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                employeeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 3),
              if (loading)
                const SizedBox(
                  width: 75,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.primary,
                    backgroundColor: Colors.transparent,
                  ),
                )
              else if (loadFailed)
                GestureDetector(
                  onTap: onRetry,
                  child: const Text(
                    'تعذر تحديث البيانات • إعادة المحاولة',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                )
              else
                Text(
                  '$positionName  •  $employeeCode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.60),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: Colors.white.withOpacity(.9),
            ),
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 19,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _EmployeeAvatar extends StatelessWidget {
  final String name;
  final String photoUrl;

  const _EmployeeAvatar({
    required this.name,
    required this.photoUrl,
  });

  String get _initial {
    final value = name.trim();

    if (value.isEmpty) {
      return 'م';
    }

    return value.substring(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 53,
      height: 53,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(.10),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrl.trim().isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return _AvatarFallback(
                    initial: _initial,
                  );
                },
              )
            : _AvatarFallback(
                initial: _initial,
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String initial;

  const _AvatarFallback({
    required this.initial,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.lightBlue,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ============================================================
// TODAY
// ============================================================

class _TodayLabel extends StatelessWidget {
  final DateTime now;

  const _TodayLabel({
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'EEEE، d MMMM',
      'ar',
    ).format(now);

    return Text(
      date,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

// ============================================================
// CLOCK
// ============================================================

class _LiveClock extends StatelessWidget {
  final String time;
  final String period;

  const _LiveClock({
    required this.time,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          time,
          style: const TextStyle(
            fontSize: 39,
            height: 1,
            fontWeight: FontWeight.w300,
            letterSpacing: -1,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            period,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ATTENDANCE HERO
// ============================================================

class _AttendanceStage extends StatelessWidget {
  final AnimationController pulseController;
  final bool loading;
  final VoidCallback onTap;

  const _AttendanceStage({
    required this.pulseController,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: pulseController,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(.025),
                border: Border.all(
                  color: AppColors.primary.withOpacity(.045),
                ),
              ),
            ),
          ),
          Container(
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(.035),
              border: Border.all(
                color: AppColors.primary.withOpacity(.065),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: loading ? null : onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 139,
                height: 139,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryDark,
                      AppColors.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(.25),
                      blurRadius: 35,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: loading
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'جاري التحقق...',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: 39,
                            color: Colors.white,
                          ),
                          SizedBox(height: 7),
                          Text(
                            'تسجيل الحضور',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'المس للبدء',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0,
            child: Row(
              children: [
                _OrbitInfo(
                  icon: Icons.schedule_rounded,
                  label: 'بداية الدوام',
                  value: '08:00',
                ),
                SizedBox(width: 10),
                _OrbitInfo(
                  icon: Icons.verified_outlined,
                  label: 'الحالة',
                  value: 'لم تسجل',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OrbitInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 7.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOCATION STATUS
// ============================================================

class _LocationStatus extends StatelessWidget {
  final String branchName;
  final bool loading;
  final AttendanceLocationCheck? lastCheck;

  const _LocationStatus({
    required this.branchName,
    required this.loading,
    required this.lastCheck,
  });

  @override
  Widget build(BuildContext context) {
    final checked = lastCheck != null;

    final inside = lastCheck?.inside ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        13,
        10,
        13,
        10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.53),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(.90),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: checked
                  ? inside
                      ? AppColors.success.withOpacity(.09)
                      : AppColors.error.withOpacity(.07)
                  : AppColors.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              checked
                  ? inside
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded
                  : Icons.location_on_outlined,
              size: 18,
              color: checked
                  ? inside
                      ? AppColors.success
                      : AppColors.error
                  : AppColors.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading
                      ? 'جاري تحميل موقع العمل...'
                      : checked
                          ? inside
                              ? 'تم التحقق من موقعك'
                              : 'خارج نطاق العمل'
                          : 'موقع العمل',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading
                      ? '...'
                      : checked
                          ? '${lastCheck!.workplace.name} • ${lastCheck!.distance.round()} متر'
                          : branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: checked
                  ? inside
                      ? AppColors.success.withOpacity(.08)
                      : AppColors.error.withOpacity(.07)
                  : AppColors.primary.withOpacity(.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              checked
                  ? inside
                      ? 'داخل النطاق'
                      : 'خارج النطاق'
                  : 'GPS عند الحضور',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: checked
                    ? inside
                        ? AppColors.success
                        : AppColors.error
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SHIFT JOURNEY
// ============================================================

class _ShiftJourney extends StatelessWidget {
  const _ShiftJourney();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'رحلة اليوم',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'دوام 8 ساعات',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.48),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(.85),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: _JourneyItem(
                  icon: Icons.login_rounded,
                  title: 'الحضور',
                  value: '--:--',
                  active: true,
                ),
              ),
              _JourneyLine(),
              Expanded(
                child: _JourneyItem(
                  icon: Icons.coffee_outlined,
                  title: 'الاستراحة',
                  value: '--',
                ),
              ),
              _JourneyLine(),
              Expanded(
                child: _JourneyItem(
                  icon: Icons.logout_rounded,
                  title: 'الانصراف',
                  value: '--:--',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JourneyItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool active;

  const _JourneyItem({
    required this.icon,
    required this.title,
    required this.value,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.lightBlue,
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(.15),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 8.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _JourneyLine extends StatelessWidget {
  const _JourneyLine();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1,
        margin: const EdgeInsets.only(
          left: 3,
          right: 3,
          bottom: 29,
        ),
        color: AppColors.border,
      ),
    );
  }
}

// ============================================================
// LOCATION CHECKING DIALOG
// ============================================================

class _LocationCheckingDialog extends StatelessWidget {
  const _LocationCheckingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 25,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 17),
            Text(
              'جاري التحقق من موقعك',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'انتظر لحظات للحصول على موقع GPS دقيق',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationResultRow extends StatelessWidget {
  final String title;
  final String value;

  const _LocationResultRow({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withOpacity(.45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// NAVIGATION
// ============================================================

class _ManaaNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _ManaaNavigation({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 18,
          sigmaY: 18,
        ),
        child: Container(
          height: 69,
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.83),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(
              color: Colors.white,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _NavigationItem(
                index: 0,
                icon: Icons.home_rounded,
                title: 'الرئيسية',
                selectedIndex: selectedIndex,
                onTap: onChanged,
              ),
              _NavigationItem(
                index: 1,
                icon: Icons.calendar_month_outlined,
                title: 'السجل',
                selectedIndex: selectedIndex,
                onTap: onChanged,
              ),
              _NavigationItem(
                index: 2,
                icon: Icons.description_outlined,
                title: 'الطلبات',
                selectedIndex: selectedIndex,
                onTap: onChanged,
              ),
              _NavigationItem(
                index: 3,
                icon: Icons.person_outline_rounded,
                title: 'حسابي',
                selectedIndex: selectedIndex,
                onTap: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _NavigationItem({
    required this.index,
    required this.icon,
    required this.title,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = selectedIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withOpacity(.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.primary : AppColors.textSecondary,
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
// PROFILE SHEET
// ============================================================

class _EmployeeInfoSheet extends StatelessWidget {
  final String employeeName;
  final String employeeCode;
  final String positionName;
  final String branchName;
  final String photoUrl;
  final String hireDate;
  final String phone;
  final VoidCallback onLogout;

  const _EmployeeInfoSheet({
    required this.employeeName,
    required this.employeeCode,
    required this.positionName,
    required this.branchName,
    required this.photoUrl,
    required this.hireDate,
    required this.phone,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          22,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFEFF),
          borderRadius: BorderRadius.circular(27),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 18),
            _EmployeeAvatar(
              name: employeeName,
              photoUrl: photoUrl,
            ),
            const SizedBox(height: 10),
            Text(
              employeeName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '$positionName • $employeeCode',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _ProfileInfoRow(
              icon: Icons.location_on_outlined,
              title: 'موقع العمل',
              value: branchName,
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ProfileInfoRow(
                icon: Icons.phone_outlined,
                title: 'رقم الهاتف',
                value: phone,
              ),
            ],
            if (hireDate.isNotEmpty) ...[
              
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withOpacity(.22),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                ),
                label: const Text(
                  'تسجيل الخروج',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
const SizedBox(height: 8),
              _ProfileInfoRow(
                icon: Icons.event_outlined,
                title: 'تاريخ التعيين',
                value: hireDate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withOpacity(.40),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: AppColors.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 8.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
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

// ============================================================
// BACKGROUND
// ============================================================

class _ManaaHomeBackground extends StatelessWidget {
  const _ManaaHomeBackground();

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
                Color(0xFFF8FBFD),
              ],
            ),
          ),
        ),
        Positioned(
          top: -130,
          right: -100,
          child: _Glow(
            size: 320,
            color: AppColors.sky.withOpacity(.11),
          ),
        ),
        Positioned(
          bottom: -150,
          left: -120,
          child: _Glow(
            size: 360,
            color: AppColors.primary.withOpacity(.075),
          ),
        ),
        Positioned(
          top: 100,
          left: -115,
          child: Transform.rotate(
            angle: -.24,
            child: Container(
              width: 175,
              height: 500,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(.05),
                    Colors.white.withOpacity(.30),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(.45),
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
