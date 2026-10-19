import 'package:get_storage/get_storage.dart';

class SessionService {
  SessionService._();

  static final GetStorage _box = GetStorage();

  static const String _loggedInKey = 'logged_in';
  static const String _employeeCodeKey = 'employee_code';
  static const String _employeeNameKey = 'employee_name';

  static bool get isLoggedIn {
    return _box.read<bool>(_loggedInKey) ?? false;
  }

  static String get employeeCode {
    return (_box.read<String>(_employeeCodeKey) ?? '').trim().toUpperCase();
  }

  static String get employeeName {
    return (_box.read<String>(_employeeNameKey) ?? '').trim();
  }

  static bool get hasValidSession {
    return isLoggedIn && employeeCode.isNotEmpty;
  }

  static Future<void> saveLogin({
    required String employeeCode,
    required String employeeName,
  }) async {
    await _box.write(_loggedInKey, true);

    await _box.write(
      _employeeCodeKey,
      employeeCode.trim().toUpperCase(),
    );

    await _box.write(
      _employeeNameKey,
      employeeName.trim(),
    );
  }

  static Future<void> logout() async {
    await _box.remove(_loggedInKey);
    await _box.remove(_employeeCodeKey);
    await _box.remove(_employeeNameKey);
  }
}
