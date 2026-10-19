import 'package:firebase_database/firebase_database.dart';

import 'attendance_service.dart';

enum AttendanceAction {
  checkIn,
  checkOut,
}

enum BreakAction {
  start,
  end,
}

class TodayAttendance {
  final String dateKey;
  final int? checkInTimestamp;
  final int? checkOutTimestamp;

  final int? breakStartTimestamp;
  final int? breakEndTimestamp;
  final int breakDurationMinutes;

  const TodayAttendance({
    required this.dateKey,
    this.checkInTimestamp,
    this.checkOutTimestamp,
    this.breakStartTimestamp,
    this.breakEndTimestamp,
    this.breakDurationMinutes = 0,
  });

  bool get hasCheckedIn => checkInTimestamp != null;
  bool get hasCheckedOut => checkOutTimestamp != null;
  bool get completed => hasCheckedIn && hasCheckedOut;

  bool get hasStartedBreak => breakStartTimestamp != null;
  bool get hasEndedBreak => breakEndTimestamp != null;

  bool get isOnBreak =>
      hasStartedBreak && !hasEndedBreak && !hasCheckedOut;

  bool get canStartBreak =>
      hasCheckedIn &&
      !hasCheckedOut &&
      !hasStartedBreak;

  bool get canEndBreak =>
      hasCheckedIn &&
      !hasCheckedOut &&
      hasStartedBreak &&
      !hasEndedBreak;

  AttendanceAction? get nextAction {
    if (!hasCheckedIn) {
      return AttendanceAction.checkIn;
    }

    if (!hasCheckedOut) {
      return AttendanceAction.checkOut;
    }

    return null;
  }

  BreakAction? get nextBreakAction {
    if (canStartBreak) {
      return BreakAction.start;
    }

    if (canEndBreak) {
      return BreakAction.end;
    }

    return null;
  }
}

class AttendanceRecordResult {
  final AttendanceAction action;
  final int timestamp;
  final String dateKey;

  const AttendanceRecordResult({
    required this.action,
    required this.timestamp,
    required this.dateKey,
  });
}

class BreakRecordResult {
  final BreakAction action;
  final int timestamp;
  final String dateKey;
  final int durationMinutes;

  const BreakRecordResult({
    required this.action,
    required this.timestamp,
    required this.dateKey,
    required this.durationMinutes,
  });
}

class AttendanceRecordException implements Exception {
  final String code;
  final String message;

  const AttendanceRecordException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class AttendanceRecordService {
  AttendanceRecordService._();

  static final FirebaseDatabase _database = FirebaseDatabase.instance;

  // ============================================================
  // DATE KEY
  // ============================================================

  static String getTodayKey() {
    final now = DateTime.now();

    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  // ============================================================
  // GET TODAY
  // ============================================================

  static Future<TodayAttendance> getTodayAttendance({
    required String employeeCode,
  }) async {
    final code = employeeCode.trim().toUpperCase();

    if (code.isEmpty) {
      throw const AttendanceRecordException(
        code: 'INVALID_EMPLOYEE',
        message: 'تعذر تحديد كود الموظف.',
      );
    }

    final dateKey = getTodayKey();

    final snapshot = await _database
        .ref('attendance_records/$dateKey/$code')
        .get();

    if (!snapshot.exists || snapshot.value is! Map) {
      return TodayAttendance(
        dateKey: dateKey,
      );
    }

    final data = _asMap(snapshot.value);

    final checkIn = _readTimestamp(data['check_in']);
    final checkOut = _readTimestamp(data['check_out']);

    final breakData = _asMap(data['break']);

    final breakStart = _readTimestamp(breakData['start']);
    final breakEnd = _readTimestamp(breakData['end']);

    int breakDurationMinutes = _readInt(
      breakData['duration_minutes'],
    );

    if (breakDurationMinutes <= 0 &&
        breakStart != null &&
        breakEnd != null &&
        breakEnd >= breakStart) {
      breakDurationMinutes =
          ((breakEnd - breakStart) / 60000).floor();
    }

    return TodayAttendance(
      dateKey: dateKey,
      checkInTimestamp: checkIn,
      checkOutTimestamp: checkOut,
      breakStartTimestamp: breakStart,
      breakEndTimestamp: breakEnd,
      breakDurationMinutes: breakDurationMinutes,
    );
  }

  // ============================================================
  // RECORD ATTENDANCE
  // ============================================================

  static Future<AttendanceRecordResult> recordAttendance({
    required String employeeKey,
    required String employeeCode,
    required String employeeName,
    required AttendanceLocationCheck locationCheck,
    required bool faceLivenessVerified,

    // المطابقة الفعلية لهوية الموظف.
    // مرر true فقط بعد نجاح Face Identity Matching.
    bool faceIdentityVerified = false,

    // صورة بروفايل الموظف الموجودة في employees.
    // لا نضع Base64 هنا. نخزن URL فقط.
    String employeePhotoUrl = '',
  }) async {
    final code = employeeCode.trim().toUpperCase();
    final cleanName = employeeName.trim();
    final cleanPhotoUrl = employeePhotoUrl.trim();

    if (code.isEmpty) {
      throw const AttendanceRecordException(
        code: 'INVALID_EMPLOYEE',
        message: 'تعذر تحديد كود الموظف.',
      );
    }

    if (!faceLivenessVerified) {
      throw const AttendanceRecordException(
        code: 'FACE_NOT_VERIFIED',
        message: 'يجب إتمام التحقق من الوجه أولًا.',
      );
    }

    if (!faceIdentityVerified) {
      throw const AttendanceRecordException(
        code: 'FACE_IDENTITY_NOT_VERIFIED',
        message: 'تعذر مطابقة الوجه مع حساب الموظف.',
      );
    }

    if (!locationCheck.inside) {
      throw const AttendanceRecordException(
        code: 'OUTSIDE_GEOFENCE',
        message: 'أنت خارج نطاق موقع العمل.',
      );
    }

    final dateKey = getTodayKey();

    final recordRef = _database.ref(
      'attendance_records/$dateKey/$code',
    );

    AttendanceAction? action;
    int? recordedTimestamp;

    final transactionResult = await recordRef.runTransaction(
      (currentValue) {
        final now = DateTime.now().millisecondsSinceEpoch;

        final Map<String, dynamic> record =
            currentValue is Map
                ? _asMap(currentValue)
                : <String, dynamic>{};

        final existingCheckIn = record['check_in'];
        final existingCheckOut = record['check_out'];

        // بيانات الموظف نحتفظ بها في نفس سجل اليوم
        // حتى تعرضها لوحة الإدارة بدون Query إضافي.
        record['employee_key'] = employeeKey;
        record['employee_code'] = code;
        record['employee_name'] = cleanName;

        if (cleanPhotoUrl.isNotEmpty) {
          record['employee_photo_url'] = cleanPhotoUrl;
        }

        record['date'] = dateKey;

        // ======================================================
        // CHECK IN
        // ======================================================

        if (existingCheckIn == null) {
          action = AttendanceAction.checkIn;
          recordedTimestamp = now;

          record['status'] = 'present';

          record['check_in'] = {
            'timestamp': now,
            'face_liveness_verified': faceLivenessVerified,
            'face_identity_verified': faceIdentityVerified,
            'location': _locationMap(locationCheck),
            'geofence': _geofenceMap(locationCheck),
          };

          record['created_at'] ??= now;
          record['updated_at'] = now;

          return Transaction.success(record);
        }

        // ======================================================
        // CHECK OUT
        // ======================================================

        if (existingCheckOut == null) {
          final breakData = _asMap(record['break']);

          final breakStart = _readTimestamp(breakData['start']);
          final breakEnd = _readTimestamp(breakData['end']);

          // لا نسمح للموظف بالانصراف أثناء استراحة مفتوحة.
          if (breakStart != null && breakEnd == null) {
            action = null;
            recordedTimestamp = null;

            return Transaction.abort();
          }

          action = AttendanceAction.checkOut;
          recordedTimestamp = now;

          record['check_out'] = {
            'timestamp': now,
            'face_liveness_verified': faceLivenessVerified,
            'face_identity_verified': faceIdentityVerified,
            'location': _locationMap(locationCheck),
            'geofence': _geofenceMap(locationCheck),
          };

          record['status'] = 'completed';
          record['updated_at'] = now;

          return Transaction.success(record);
        }

        action = null;
        recordedTimestamp = null;

        return Transaction.abort();
      },
      applyLocally: false,
    );

    if (!transactionResult.committed ||
        action == null ||
        recordedTimestamp == null) {
      final latest = await getTodayAttendance(
        employeeCode: code,
      );

      if (latest.isOnBreak) {
        throw const AttendanceRecordException(
          code: 'BREAK_ACTIVE',
          message: 'يجب إنهاء الاستراحة قبل تسجيل الانصراف.',
        );
      }

      throw const AttendanceRecordException(
        code: 'ATTENDANCE_COMPLETED',
        message: 'تم تسجيل الحضور والانصراف لهذا اليوم بالفعل.',
      );
    }

    await _syncHistory(
      employeeCode: code,
      dateKey: dateKey,
    );

    return AttendanceRecordResult(
      action: action!,
      timestamp: recordedTimestamp!,
      dateKey: dateKey,
    );
  }

  // ============================================================
  // BREAK
  // ============================================================

  static Future<BreakRecordResult> recordBreak({
    required String employeeKey,
    required String employeeCode,
    required String employeeName,

    // نمرر صورة البروفايل هنا أيضًا لأن بعض السجلات القديمة
    // قد لا تحتوي عليها.
    String employeePhotoUrl = '',
  }) async {
    final code = employeeCode.trim().toUpperCase();
    final cleanName = employeeName.trim();
    final cleanPhotoUrl = employeePhotoUrl.trim();

    if (code.isEmpty) {
      throw const AttendanceRecordException(
        code: 'INVALID_EMPLOYEE',
        message: 'تعذر تحديد كود الموظف.',
      );
    }

    final dateKey = getTodayKey();

    final recordRef = _database.ref(
      'attendance_records/$dateKey/$code',
    );

    BreakAction? action;
    int? recordedTimestamp;
    int durationMinutes = 0;
    String? abortReason;

    final transactionResult = await recordRef.runTransaction(
      (currentValue) {
        abortReason = null;

        if (currentValue is! Map) {
          abortReason = 'NO_CHECK_IN';
          return Transaction.abort();
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final record = _asMap(currentValue);

        final checkIn = _readTimestamp(record['check_in']);
        final checkOut = _readTimestamp(record['check_out']);

        if (checkIn == null) {
          abortReason = 'NO_CHECK_IN';
          return Transaction.abort();
        }

        if (checkOut != null) {
          abortReason = 'ALREADY_CHECKED_OUT';
          return Transaction.abort();
        }

        record['employee_key'] = employeeKey;
        record['employee_code'] = code;
        record['employee_name'] = cleanName;

        if (cleanPhotoUrl.isNotEmpty) {
          record['employee_photo_url'] = cleanPhotoUrl;
        }

        record['date'] = dateKey;

        final breakData = _asMap(record['break']);

        final breakStart = _readTimestamp(breakData['start']);
        final breakEnd = _readTimestamp(breakData['end']);

        // ======================================================
        // START BREAK
        // ======================================================

        if (breakStart == null) {
          action = BreakAction.start;
          recordedTimestamp = now;
          durationMinutes = 0;

          record['break'] = {
            'start': {
              'timestamp': now,
            },
            'end': null,
            'duration_minutes': 0,
            'status': 'active',
          };

          record['status'] = 'on_break';
          record['updated_at'] = now;

          return Transaction.success(record);
        }

        // ======================================================
        // END BREAK
        // ======================================================

        if (breakEnd == null) {
          action = BreakAction.end;
          recordedTimestamp = now;

          durationMinutes =
              ((now - breakStart) / 60000).floor();

          if (durationMinutes < 0) {
            durationMinutes = 0;
          }

          breakData['end'] = {
            'timestamp': now,
          };

          breakData['duration_minutes'] = durationMinutes;
          breakData['status'] = 'completed';

          record['break'] = breakData;
          record['status'] = 'present';
          record['updated_at'] = now;

          return Transaction.success(record);
        }

        abortReason = 'BREAK_COMPLETED';

        action = null;
        recordedTimestamp = null;

        return Transaction.abort();
      },
      applyLocally: false,
    );

    if (!transactionResult.committed ||
        action == null ||
        recordedTimestamp == null) {
      switch (abortReason) {
        case 'NO_CHECK_IN':
          throw const AttendanceRecordException(
            code: 'NO_CHECK_IN',
            message: 'يجب تسجيل الحضور أولًا قبل بدء الاستراحة.',
          );

        case 'ALREADY_CHECKED_OUT':
          throw const AttendanceRecordException(
            code: 'ALREADY_CHECKED_OUT',
            message: 'لا يمكن تسجيل استراحة بعد تسجيل الانصراف.',
          );

        case 'BREAK_COMPLETED':
          throw const AttendanceRecordException(
            code: 'BREAK_COMPLETED',
            message: 'تم استخدام الاستراحة لهذا اليوم بالفعل.',
          );

        default:
          throw const AttendanceRecordException(
            code: 'BREAK_NOT_RECORDED',
            message: 'تعذر تسجيل الاستراحة. حاول مرة أخرى.',
          );
      }
    }

    await _syncHistory(
      employeeCode: code,
      dateKey: dateKey,
    );

    return BreakRecordResult(
      action: action!,
      timestamp: recordedTimestamp!,
      dateKey: dateKey,
      durationMinutes: durationMinutes,
    );
  }

  // ============================================================
  // HISTORY MIRROR
  // ============================================================

  static Future<void> _syncHistory({
    required String employeeCode,
    required String dateKey,
  }) async {
    final code = employeeCode.trim().toUpperCase();

    if (code.isEmpty) return;

    final source = await _database
        .ref('attendance_records/$dateKey/$code')
        .get();

    if (!source.exists || source.value == null) return;

    await _database
        .ref('attendance_history/$code/$dateKey')
        .set(source.value);
  }

  // ============================================================
  // LOCATION MAPS
  // ============================================================

  static Map<String, dynamic> _locationMap(
    AttendanceLocationCheck locationCheck,
  ) {
    return {
      'latitude': locationCheck.deviceLocation.latitude,
      'longitude': locationCheck.deviceLocation.longitude,
      'accuracy': locationCheck.deviceLocation.accuracy,
      'provider': locationCheck.deviceLocation.provider,
    };
  }

  static Map<String, dynamic> _geofenceMap(
    AttendanceLocationCheck locationCheck,
  ) {
    return {
      'latitude': locationCheck.workplace.latitude,
      'longitude': locationCheck.workplace.longitude,
      'radius': locationCheck.workplace.radius,
      'distance': locationCheck.distance,
      'source': locationCheck.workplace.source,
      'reference_id': locationCheck.workplace.referenceId,
      'location_name': locationCheck.workplace.name,
    };
  }

  // ============================================================
  // TIMESTAMP
  // ============================================================

  static int? _readTimestamp(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map) {
      final map = _asMap(value);

      final timestamp = map['timestamp'];

      if (timestamp is num) {
        return timestamp.toInt();
      }

      return int.tryParse(
        timestamp?.toString() ?? '',
      );
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    );
  }

  static int _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // MAP
  // ============================================================

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) {
      return {};
    }

    final result = <String, dynamic>{};

    raw.forEach(
      (key, value) {
        result[key.toString()] = value;
      },
    );

    return result;
  }
}
