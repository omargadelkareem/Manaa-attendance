import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_plugin/face_plugin.dart' as fp;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class AttendanceFaceVerificationScreen extends StatefulWidget {
  final String employeeCode;

  final String employeeName;

  const AttendanceFaceVerificationScreen({
    super.key,
    required this.employeeCode,
    required this.employeeName,
  });

  @override
  State<AttendanceFaceVerificationScreen> createState() =>
      _AttendanceFaceVerificationScreenState();
}

enum _VerificationStep {
  preparing,

  front,

  right,

  left,

  finalFront,

  success,
}

class _AttendanceFaceVerificationScreenState
    extends State<AttendanceFaceVerificationScreen> {
  CameraController? _cameraController;

  late final FaceDetector _faceDetector;

  Timer? _scanTimer;

  bool _initializing = true;

  bool _processing = false;

  bool _completed = false;

  String? _errorMessage;

  _VerificationStep _step = _VerificationStep.preparing;

  int _validFrames = 0;

  static const int _requiredFrames = 2;

  static const double _identityThreshold = 0.58;

  XFile? _identityImage;
  double? _lastSimilarity;

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );

    _initializeCamera();
  }

  // ============================================================
  // CAMERA
  // ============================================================
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'لم يتم العثور على كاميرا.',
        );
      }

      CameraDescription camera = cameras.first;

      for (final item in cameras) {
        if (item.lensDirection == CameraLensDirection.front) {
          camera = item;

          break;
        }
      }

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();

        return;
      }

      _cameraController = controller;

      setState(() {
        _initializing = false;

        _step = _VerificationStep.front;
      });

      _startScanning();
    } on CameraException catch (error) {
      _showInitializationError(
        _cameraErrorMessage(error),
      );
    } catch (error) {
      _showInitializationError(
        'تعذر تشغيل الكاميرا. حاول مرة أخرى.',
      );
    }
  }

  void _showInitializationError(
    String message,
  ) {
    if (!mounted) return;

    setState(() {
      _initializing = false;

      _errorMessage = message;
    });
  }

  String _cameraErrorMessage(
    CameraException error,
  ) {
    switch (error.code) {
      case 'CameraAccessDenied':
        return 'يجب السماح للتطبيق باستخدام الكاميرا لإتمام تسجيل الحضور.';

      case 'CameraAccessDeniedWithoutPrompt':
        return 'صلاحية الكاميرا مرفوضة. فعّلها من إعدادات التطبيق.';

      case 'CameraAccessRestricted':
        return 'استخدام الكاميرا غير متاح على هذا الجهاز.';

      default:
        return 'تعذر تشغيل الكاميرا. حاول مرة أخرى.';
    }
  }

  // ============================================================
  // SCANNING
  // ============================================================
  void _startScanning() {
    _scanTimer?.cancel();

    _scanTimer = Timer.periodic(
      const Duration(
        milliseconds: 700,
      ),
      (_) {
        _scanFace();
      },
    );
  }

  Future<void> _scanFace() async {
    if (_processing || _completed || !mounted) {
      return;
    }

    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _processing = true;

    XFile? image;

    try {
      image = await controller.takePicture();

      final inputImage = InputImage.fromFilePath(
        image.path,
      );

      final faces = await _faceDetector.processImage(
        inputImage,
      );

      if (!mounted || _completed) {
        return;
      }

      if (faces.isEmpty) {
        _resetCurrentProgress();

        return;
      }

      /**

       * لا نقبل وجود أكثر من شخص.
       */
      if (faces.length != 1) {
        _resetCurrentProgress();

        return;
      }

      final face = faces.first;

      if (!_isFaceLargeEnough(
        face,
        controller,
      )) {
        _resetCurrentProgress();

        return;
      }
      final currentYaw = face.headEulerAngleY ?? 0;
      final currentRoll = face.headEulerAngleZ ?? 0;

      if (_step == _VerificationStep.finalFront &&
          currentYaw.abs() <= 12 &&
          currentRoll.abs() <= 20) {
        final previous = _identityImage;
        _identityImage = image;
        image = null;

        if (previous != null) {
          try {
            final previousFile = File(previous.path);
            if (await previousFile.exists()) await previousFile.delete();
          } catch (_) {}
        }
      }

      _processFaceDirection(face);
    } catch (_) {
      /**

       * فشل Frame واحد لا يعني
       * فشل عملية التحقق بالكامل.
       */
    } finally {
      if (image != null) {
        try {
          final file = File(image.path);

          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }

      _processing = false;
    }
  }

  // ============================================================
  // FACE SIZE
  // ============================================================
  bool _isFaceLargeEnough(
    Face face,
    CameraController controller,
  ) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return true;
    }

    final imageArea = previewSize.width * previewSize.height;

    if (imageArea <= 0) {
      return true;
    }

    final faceArea = face.boundingBox.width * face.boundingBox.height;

    final ratio = faceArea / imageArea;

    /**

     * يمنع محاولة التحقق
     * بوجه صغير جدًا بعيد عن الكاميرا.
     */
    return ratio >= 0.04;
  }

  // ============================================================
  // DIRECTION
  // ============================================================
  void _processFaceDirection(
    Face face,
  ) {
    final yaw = face.headEulerAngleY ?? 0;

    final roll = face.headEulerAngleZ ?? 0;

    /**

     * ميل شديد للرأس يجعل
     * قراءة الاتجاه غير موثوقة.
     */
    if (roll.abs() > 20) {
      _resetCurrentProgress();

      return;
    }

    bool valid = false;

    switch (_step) {
      case _VerificationStep.front:
        valid = yaw.abs() <= 12;

        break;

      case _VerificationStep.right:

        /**

         * اتجاه إشارة yaw قد يختلف
         * بسبب الكاميرا الأمامية/mirroring.
         *
         * هنا نعتمد التسلسل على الإشارة
         * التي يرجعها ML Kit.
         */
        valid = yaw >= 18;

        break;

      case _VerificationStep.left:
        valid = yaw <= -18;

        break;

      case _VerificationStep.finalFront:
        valid = yaw.abs() <= 12;

        break;

      case _VerificationStep.preparing:
      case _VerificationStep.success:
        return;
    }

    if (!valid) {
      /**

       * لا نصفر فورًا بسبب Frame واحد.
       * ننقص progress تدريجيًا.
       */
      if (_validFrames > 0) {
        _validFrames--;
      }

      if (mounted) {
        setState(() {});
      }

      return;
    }

    if (_errorMessage != null) {
      _errorMessage = null;
    }

    _validFrames++;

    if (_validFrames < _requiredFrames) {
      if (mounted) {
        setState(() {});
      }

      return;
    }

    _validFrames = 0;

    switch (_step) {
      case _VerificationStep.front:
        _step = _VerificationStep.right;

        break;

      case _VerificationStep.right:
        _step = _VerificationStep.left;

        break;

      case _VerificationStep.left:
        _step = _VerificationStep.finalFront;

        break;

      case _VerificationStep.finalFront:
        _finishVerification();

        return;

      case _VerificationStep.preparing:
      case _VerificationStep.success:
        return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _resetCurrentProgress() {
    if (_validFrames == 0 || !mounted) {
      return;
    }

    setState(() {
      _validFrames = 0;
    });
  }

  // ============================================================
  // SUCCESS
  // ============================================================
  Future<void> _finishVerification() async {
    if (_completed) return;

    _completed = true;
    _scanTimer?.cancel();

    try {
      final image = _identityImage;
      if (image == null) {
        throw Exception('تعذر التقاط صورة أمامية واضحة. حاول مرة أخرى.');
      }

      final bytes = await File(image.path).readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('تعذر قراءة صورة التحقق. حاول مرة أخرى.');
      }

      final snapshot = await FirebaseDatabase.instance
          .ref('employees')
          .orderByChild('emp_code')
          .equalTo(widget.employeeCode.trim().toUpperCase())
          .limitToFirst(1)
          .get();

      if (!snapshot.exists || snapshot.children.isEmpty) {
        throw Exception('تعذر العثور على بيانات الموظف.');
      }

      final employeeData = _asMap(snapshot.children.first.value);
      final biometric = _asMap(employeeData['face_biometric']);
      final savedEmbedding = _readEmbedding(biometric['embedding']);

      if (savedEmbedding.isEmpty) {
        throw Exception(
          'لا توجد بصمة وجه محفوظة لهذا الحساب. يجب إعادة تسجيل الوجه أولاً.',
        );
      }

      final List<List<double>> features =
          await fp.FacePlugin.extractFeatures(Uint8List.fromList(bytes));

      if (features.isEmpty) {
        throw Exception('تعذر استخراج بصمة الوجه الحالية. حاول بإضاءة أفضل.');
      }

      final currentEmbedding = features.first;

      if (currentEmbedding.length != savedEmbedding.length) {
        throw Exception(
          'إصدار بصمة الوجه المحفوظة لا يطابق الإصدار الحالي. أعد تسجيل الوجه.',
        );
      }

      final similarity = _cosineSimilarity(savedEmbedding, currentEmbedding);
      _lastSimilarity = similarity;

      debugPrint(
        'Attendance face similarity for ${widget.employeeCode}: '
        '${similarity.toStringAsFixed(4)}',
      );

      if (similarity < _identityThreshold) {
        throw Exception('الوجه غير مطابق للوجه المسجل على حساب الموظف.');
      }

      if (!mounted) return;

      setState(() {
        _step = _VerificationStep.success;
        _errorMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted) return;
      await _deleteIdentityImage();
      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Attendance face identity error: $error');
      debugPrint('$stackTrace');

      _completed = false;
      await _deleteIdentityImage();

      if (!mounted) return;

      setState(() {
        _step = _VerificationStep.front;
        _validFrames = 0;
        _errorMessage = _friendlyIdentityError(error);
      });

      _startScanning();
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      result[key.toString()] = value;
    });
    return result;
  }

  List<double> _readEmbedding(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) {
            if (value is num) return value.toDouble();
            return double.tryParse(value.toString());
          })
          .whereType<double>()
          .toList();
    }

    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) {
          final ai = int.tryParse(a.key.toString()) ?? 0;
          final bi = int.tryParse(b.key.toString()) ?? 0;
          return ai.compareTo(bi);
        });

      return entries
          .map((entry) {
            final value = entry.value;
            if (value is num) return value.toDouble();
            return double.tryParse(value.toString());
          })
          .whereType<double>()
          .toList();
    }

    return [];
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return -1;

    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA <= 0 || normB <= 0) return -1;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  String _friendlyIdentityError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '').trim();

    if (value.contains('MissingPluginException')) {
      return 'تعذر تشغيل محرك مطابقة الوجه. أغلق التطبيق وافتحه من جديد.';
    }

    return value.isEmpty ? 'تعذر التحقق من هوية الوجه. حاول مرة أخرى.' : value;
  }

  Future<void> _deleteIdentityImage() async {
    final image = _identityImage;
    _identityImage = null;
    if (image == null) return;

    try {
      final file = File(image.path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ============================================================
  // UI TEXT
  // ============================================================
  String get _instruction {
    switch (_step) {
      case _VerificationStep.preparing:
        return 'جارٍ تجهيز الكاميرا...';

      case _VerificationStep.front:
        return 'انظر مباشرة إلى الكاميرا';

      case _VerificationStep.right:
        return 'حرّك رأسك ناحية اليمين';

      case _VerificationStep.left:
        return 'الآن حرّك رأسك ناحية اليسار';

      case _VerificationStep.finalFront:
        return 'ممتاز، انظر أمامك مرة أخرى';

      case _VerificationStep.success:
        return 'تم التحقق بنجاح';
    }
  }

  String get _helperText {
    switch (_step) {
      case _VerificationStep.preparing:
        return 'لحظات قليلة';

      case _VerificationStep.front:
        return 'ضع وجهك داخل الإطار';

      case _VerificationStep.right:
        return 'حركة بسيطة تكفي';

      case _VerificationStep.left:
        return 'حركة بسيطة تكفي';

      case _VerificationStep.finalFront:
        return 'ثبت وجهك للحظة';

      case _VerificationStep.success:
        return 'جارٍ تسجيل الحضور';
    }
  }

  double get _progress {
    switch (_step) {
      case _VerificationStep.preparing:
        return 0;

      case _VerificationStep.front:
        return 0.20;

      case _VerificationStep.right:
        return 0.45;

      case _VerificationStep.left:
        return 0.70;

      case _VerificationStep.finalFront:
        return 0.90;

      case _VerificationStep.success:
        return 1;
    }
  }

  // ============================================================
  // RETRY
  // ============================================================
  Future<void> _retry() async {
    _scanTimer?.cancel();

    final oldController = _cameraController;

    _cameraController = null;

    try {
      await oldController?.dispose();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _initializing = true;

      _processing = false;

      _completed = false;

      _errorMessage = null;

      _validFrames = 0;

      _step = _VerificationStep.preparing;
    });

    await _initializeCamera();
  }

  // ============================================================
  // DISPOSE
  // ============================================================
  @override
  void dispose() {
    _scanTimer?.cancel();

    _cameraController?.dispose();

    _faceDetector.close();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      backgroundColor: const Color(0xFF06141F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _initializing
                  ? _buildLoading()
                  : controller != null && controller.value.isInitialized
                      ? _buildCamera(controller)
                      : _buildError(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        10,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التحقق من الوجه',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.employeeName,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================
  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
          SizedBox(height: 18),
          Text(
            'جارٍ تجهيز الكاميرا...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: Color(0x22FFFFFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'تعذر تشغيل الكاميرا.',
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(
                  0xFF06141F,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
              ),
              child: const Text(
                'إعادة المحاولة',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAMERA
  // ============================================================
  Widget _buildCamera(
    CameraController controller,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _cameraPreview(controller),

        /**

         * Dark overlay around face area.
         */
        IgnorePointer(
          child: CustomPaint(
            painter: _FaceOverlayPainter(),
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          top: 24,
          child: _buildInstructionCard(),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: _buildBottomPanel(),
        ),
        if (_errorMessage != null && _step != _VerificationStep.success)
          Positioned(
            left: 24,
            right: 24,
            bottom: 132,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xE6B42318),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (_step == _VerificationStep.success) _buildSuccessOverlay(),
      ],
    );
  }

  Widget _cameraPreview(
    CameraController controller,
  ) {
    final size = MediaQuery.sizeOf(context);

    var scale = size.aspectRatio * controller.value.aspectRatio;

    if (scale < 1) {
      scale = 1 / scale;
    }

    return Transform.scale(
      scale: scale,
      child: Center(
        child: CameraPreview(
          controller,
        ),
      ),
    );
  }

  // ============================================================
  // INSTRUCTION
  // ============================================================
  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 15,
      ),
      decoration: BoxDecoration(
        color: const Color(0xD90A1924),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(
            0.12,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            _instruction,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _helperText,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTTOM
  // ============================================================
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xE60A1924),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(
            0.10,
          ),
        ),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              20,
            ),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              backgroundColor: Colors.white.withOpacity(
                0.10,
              ),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF58D68D),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF58D68D),
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                'تحقق آمن من الحضور',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUCCESS
  // ============================================================
  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xE6073A2B),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 78,
              ),
              SizedBox(height: 18),
              Text(
                'تم التحقق بنجاح',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'جارٍ استكمال تسجيل الحضور',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
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
// FACE OVERLAY
// ============================================================
class _FaceOverlayPainter extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height * 0.49,
    );

    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.66,
      height: size.height * 0.45,
    );

    final overlayPath = Path()
      ..addRect(
        Offset.zero & size,
      );

    final facePath = Path()
      ..addOval(
        ovalRect,
      );

    final finalPath = Path.combine(
      PathOperation.difference,
      overlayPath,
      facePath,
    );

    final darkPaint = Paint()
      ..color = Colors.black.withOpacity(
        0.48,
      );

    canvas.drawPath(
      finalPath,
      darkPaint,
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(
        0xFF58D68D,
      );

    canvas.drawOval(
      ovalRect,
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}
