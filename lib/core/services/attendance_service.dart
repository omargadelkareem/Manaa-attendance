import 'package:firebase_database/firebase_database.dart';



import 'native_location_service.dart';



class AttendanceLocation {

  final double latitude;

  final double longitude;

  final double radius;

  final String name;




  final String source;




  final String referenceId;



  const AttendanceLocation({

    required this.latitude,

    required this.longitude,

    required this.radius,

    required this.name,

    required this.source,

    required this.referenceId,

  });

}



class AttendanceLocationCheck {

  final AttendanceLocation workplace;

  final NativeLocation deviceLocation;

  final double distance;



  const AttendanceLocationCheck({

    required this.workplace,

    required this.deviceLocation,

    required this.distance,

  });



  bool get inside {

    return distance <= workplace.radius;

  }



  double get accuracy {

    return deviceLocation.accuracy;

  }




  double get maximumPossibleDistance {

    return distance + accuracy;

  }




  double get minimumPossibleDistance {

    final value = distance - accuracy;



    return value < 0 ? 0 : value;

  }




  bool get definitelyInside {

    return maximumPossibleDistance <= workplace.radius;

  }




  bool get definitelyOutside {

    return minimumPossibleDistance > workplace.radius;

  }

}



class AttendanceException implements Exception {

  final String code;

  final String message;



  const AttendanceException({

    required this.code,

    required this.message,

  });



  @override

  String toString() => message;

}



class AttendanceService {

  AttendanceService._();



  static final FirebaseDatabase _database = FirebaseDatabase.instance;
  static Future<AttendanceLocationCheck> verifyLocation({

    required String employeeKey,

    required Map<String, dynamic> employee,

  }) async {












    final workplace = await _resolveWorkplace(

      employeeKey: employeeKey,

      employee: employee,

    );








    final locationEnabled = await NativeLocationService.isLocationEnabled();



    if (!locationEnabled) {

      throw const AttendanceException(

        code: 'LOCATION_DISABLED',

        message: 'خدمة الموقع مغلقة. قم بتشغيل GPS ثم حاول مرة أخرى.',

      );

    }








    final deviceLocation = await NativeLocationService.getCurrentLocation();








    if (!deviceLocation.latitude.isFinite ||

        !deviceLocation.longitude.isFinite) {

      throw const AttendanceException(

        code: 'INVALID_LOCATION',

        message: 'تعذر قراءة إحداثيات موقع الجهاز بشكل صحيح.',

      );

    }



    if (deviceLocation.latitude < -90 ||

        deviceLocation.latitude > 90 ||

        deviceLocation.longitude < -180 ||

        deviceLocation.longitude > 180) {

      throw const AttendanceException(

        code: 'INVALID_LOCATION',

        message: 'إحداثيات موقع الجهاز غير صالحة. حاول مرة أخرى.',

      );

    }



    if (!deviceLocation.accuracy.isFinite || deviceLocation.accuracy <= 0) {

      throw const AttendanceException(

        code: 'INVALID_ACCURACY',

        message: 'تعذر التأكد من دقة موقع الجهاز. حاول مرة أخرى.',

      );

    }
    final distance = NativeLocationService.distanceInMeters(

      fromLatitude: deviceLocation.latitude,

      fromLongitude: deviceLocation.longitude,

      toLatitude: workplace.latitude,

      toLongitude: workplace.longitude,

    );



    if (!distance.isFinite) {

      throw const AttendanceException(

        code: 'DISTANCE_ERROR',

        message: 'تعذر حساب المسافة من موقع العمل.',

      );

    }



    // القرار يعتمد مباشرة على نصف القطر المحدد من لوحة التحكم.
    // مثال: radius = 1000m و distance = 700m => داخل النطاق.
    // دقة GPS تظل محفوظة في deviceLocation للعرض فقط ولا تمنع البصمة.

    return AttendanceLocationCheck(

      workplace: workplace,

      deviceLocation: deviceLocation,

      distance: distance,

    );

  }








  static Future<AttendanceLocation> _resolveWorkplace({

    required String employeeKey,

    required Map<String, dynamic> employee,

  }) async {

    final employeeCode = _readString(

      employee,

      [

        'emp_code',

        'employee_code',

        'employeeCode',

        'code',

      ],

    ).toUpperCase();

















    if (employeeCode.isNotEmpty) {

      final employeeLocation = await _getEmployeeOverride(

        employeeCode,

      );



      if (employeeLocation != null) {

        return employeeLocation;

      }

    }













    final cleanEmployeeKey = employeeKey.trim();



    if (cleanEmployeeKey.isNotEmpty &&

        cleanEmployeeKey.toUpperCase() != employeeCode) {

      final legacyLocation = await _getEmployeeOverride(

        cleanEmployeeKey,

      );



      if (legacyLocation != null) {

        return legacyLocation;

      }

    }











    final branchId = _readString(

      employee,

      [

        'branch_id',

        'branchId',

      ],

    );



    if (branchId.isNotEmpty) {

      final branchLocation = await _getBranchLocation(

        branchId,

      );



      if (branchLocation != null) {

        return branchLocation;

      }

    }














    final branchName = _readString(

      employee,

      [

        'branch_name',

        'branch',

        'work_area',

      ],

    );



    if (branchId.isEmpty && branchName.isNotEmpty) {

      final normalizedBranchId = _normalizeKey(

        branchName,

      );



      if (normalizedBranchId.isNotEmpty) {

        final legacyBranchLocation = await _getBranchLocation(

          normalizedBranchId,

        );



        if (legacyBranchLocation != null) {

          return legacyBranchLocation;

        }

      }

    }








    throw const AttendanceException(

      code: 'WORKPLACE_NOT_CONFIGURED',

      message:

          'لم يتم إعداد موقع البصمة لهذا الموظف أو الفرع. تواصل مع الإدارة.',

    );

  }








  static Future<AttendanceLocation?> _getEmployeeOverride(

    String referenceId,

  ) async {

    try {

      final snapshot = await _database

          .ref(

            'attendance_geofence/$referenceId/override',

          )

          .get();



      if (!snapshot.exists) {

        return null;

      }



      final data = _asMap(

        snapshot.value,

      );



      if (data.isEmpty) {

        return null;

      }



      if (!_isLocationEnabled(data)) {

        return null;

      }



      return _parseLocation(

        data,

        sourceName: 'employee',

        referenceId: referenceId,

        fallbackName: 'موقع الموظف الخاص',

      );

    } catch (_) {





      return null;

    }

  }








  static Future<AttendanceLocation?> _getBranchLocation(

    String branchId,

  ) async {












    try {

      final snapshot = await _database

          .ref(

            'attendance_branches/$branchId/attendance_location',

          )

          .get();



      if (snapshot.exists) {

        final data = _asMap(

          snapshot.value,

        );



        if (data.isNotEmpty && _isLocationEnabled(data)) {

          final location = _parseLocation(

            data,

            sourceName: 'branch',

            referenceId: branchId,

            fallbackName: 'موقع الفرع',

          );



          if (location != null) {

            return location;

          }

        }

      }

    } catch (_) {}














    try {

      final snapshot = await _database

          .ref(

            'branches/$branchId/attendance_location',

          )

          .get();



      if (snapshot.exists) {

        final data = _asMap(

          snapshot.value,

        );



        if (data.isNotEmpty && _isLocationEnabled(data)) {

          final location = _parseLocation(

            data,

            sourceName: 'branch',

            referenceId: branchId,

            fallbackName: 'موقع الفرع',

          );



          if (location != null) {

            return location;

          }

        }

      }

    } catch (_) {}



    return null;

  }








  static AttendanceLocation? _parseLocation(

    Map<String, dynamic> data, {

    required String sourceName,

    required String referenceId,

    required String fallbackName,

  }) {

    final latitude = _readDouble(

      data,

      [

        'latitude',

        'lat',

      ],

    );



    final longitude = _readDouble(

      data,

      [

        'longitude',

        'lng',

        'lon',

      ],

    );



    final radius = _readDouble(

      data,

      [

        'radius',

        'radius_meters',

        'radiusMeters',

      ],

    );



    if (latitude == null || longitude == null || radius == null) {

      return null;

    }








    if (!latitude.isFinite || !longitude.isFinite || !radius.isFinite) {

      return null;

    }



    if (latitude < -90 || latitude > 90) {

      return null;

    }



    if (longitude < -180 || longitude > 180) {

      return null;

    }












    if (radius < 20 || radius > 5000) {

      return null;

    }



    final locationName = _readString(

      data,

      [

        'location_name',

        'locationName',

        'name',

      ],

    );



    return AttendanceLocation(

      latitude: latitude,

      longitude: longitude,

      radius: radius,

      name: locationName.isNotEmpty ? locationName : fallbackName,

      source: sourceName,

      referenceId: referenceId,

    );

  }








  static bool _isLocationEnabled(

    Map<String, dynamic> data,

  ) {







    if (!data.containsKey('active') &&

        !data.containsKey('is_active') &&

        !data.containsKey('enabled')) {

      return true;

    }



    final value = data['active'] ?? data['is_active'] ?? data['enabled'];



    if (value == true || value == 1) {

      return true;

    }



    final normalized = value?.toString().trim().toLowerCase();



    return normalized == 'true' || normalized == '1' || normalized == 'yes';

  }








  static Map<String, dynamic> _asMap(

    dynamic raw,

  ) {

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








  static String _readString(

    Map<String, dynamic> data,

    List<String> keys,

  ) {

    for (final key in keys) {

      final value = data[key];



      if (value == null) {

        continue;

      }



      final text = value.toString().trim();



      if (text.isNotEmpty && text.toLowerCase() != 'null') {

        return text;

      }

    }



    return '';

  }








  static double? _readDouble(

    Map<String, dynamic> data,

    List<String> keys,

  ) {

    for (final key in keys) {

      final value = data[key];



      if (value == null) {

        continue;

      }



      if (value is num) {

        return value.toDouble();

      }



      final parsed = double.tryParse(

        value.toString().trim(),

      );



      if (parsed != null) {

        return parsed;

      }

    }



    return null;

  }








  static String _normalizeKey(

    String value,

  ) {

    return value

        .trim()

        .replaceAll(

          RegExp(

            r'[.#$\[\]/]',

          ),

          '_',

        )

        .replaceAll(

          RegExp(

            r'\s+',

          ),

          '_',

        )

        .toLowerCase();

  }

}
