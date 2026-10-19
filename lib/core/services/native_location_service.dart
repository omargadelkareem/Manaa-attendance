import 'dart:math' as math;

import 'package:flutter/services.dart';

class NativeLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final int timestamp;
  final String provider;

  const NativeLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.provider,
  });

  factory NativeLocation.fromMap(Map<dynamic, dynamic> map) {
    return NativeLocation(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 999,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      provider: map['provider']?.toString() ?? 'unknown',
    );
  }
}

class NativeLocationException implements Exception {
  final String code;
  final String message;

  const NativeLocationException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class NativeLocationService {
  NativeLocationService._();

  static const MethodChannel _channel = MethodChannel(
    'manaa/location',
  );

  static Future<bool> checkPermission() async {
    try {
      return await _channel.invokeMethod<bool>(
            'checkPermission',
          ) ??
          false;
    } on PlatformException catch (e) {
      throw NativeLocationException(
        code: e.code,
        message: e.message ?? 'تعذر التحقق من صلاحية الموقع.',
      );
    }
  }

  static Future<bool> isLocationEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isLocationEnabled',
          ) ??
          false;
    } on PlatformException catch (e) {
      throw NativeLocationException(
        code: e.code,
        message: e.message ?? 'تعذر التحقق من خدمة الموقع.',
      );
    }
  }

  static Future<NativeLocation> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'getCurrentLocation',
      );

      if (result is! Map) {
        throw const NativeLocationException(
          code: 'INVALID_LOCATION',
          message: 'تعذر قراءة الموقع الحالي.',
        );
      }

      return NativeLocation.fromMap(result);
    } on PlatformException catch (e) {
      throw NativeLocationException(
        code: e.code,
        message: _platformMessage(e.code, e.message),
      );
    }
  }

  static Future<void> openLocationSettings() async {
    await _channel.invokeMethod<void>(
      'openLocationSettings',
    );
  }

  static Future<void> openAppSettings() async {
    await _channel.invokeMethod<void>(
      'openAppSettings',
    );
  }

  static double distanceInMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const earthRadius = 6371000.0;

    final lat1 = _degreesToRadians(fromLatitude);
    final lat2 = _degreesToRadians(toLatitude);

    final deltaLat = _degreesToRadians(
      toLatitude - fromLatitude,
    );

    final deltaLon = _degreesToRadians(
      toLongitude - fromLongitude,
    );

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);

    final c = 2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(1 - a),
        );

    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  static String _platformMessage(
    String code,
    String? original,
  ) {
    switch (code) {
      case 'PERMISSION_DENIED':
        return 'يجب السماح للتطبيق باستخدام الموقع لتسجيل الحضور.';

      case 'LOCATION_DISABLED':
        return 'خدمة الموقع GPS مغلقة. قم بتشغيلها ثم حاول مرة أخرى.';

      case 'LOCATION_UNAVAILABLE':
        return 'تعذر تحديد موقعك الحالي. انتظر قليلاً ثم حاول مرة أخرى.';

      case 'LOCATION_TIMEOUT':
        return 'استغرق تحديد الموقع وقتاً أطول من المتوقع. حاول مرة أخرى.';

      default:
        return original ?? 'حدث خطأ أثناء تحديد الموقع.';
    }
  }
}
