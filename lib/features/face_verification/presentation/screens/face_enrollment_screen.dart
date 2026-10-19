import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_plugin/face_plugin.dart' as fp;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../authentication/presentation/screens/account_activated_screen.dart';

class FaceEnrollmentScreen extends StatefulWidget {
  final String employeeName;

  final String employeeCode;

  const FaceEnrollmentScreen({
    super.key,
    required this.employeeName,
    required this.employeeCode,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scanController;

  late final AnimationController _pulseController;

  CameraController? _cameraController;

  late final FaceDetector _faceDetector;

  bool _cameraLoading = true;

  bool _cameraReady = false;

  bool _cameraError = false;

  bool _isScanning = false;

  bool _completed = false;

  bool _processingFrame = false;

  bool _savingFirebase = false;

  int _step = 0;

  double _progress = 0;

  String _statusMessage = 'جاري تشغيل الكاميرا...';

  int _validFrames = 0;

  String? _bestFrontImagePath;
  double _bestFrontFaceArea = -1;

  Timer? _scanTimer;

  final List<String> _instructions = const [
    'انظر مباشرة إلى الكاميرا',
    'حرّك وجهك قليلاً إلى اليمين',
    'حرّك وجهك قليلاً إلى اليسار',
    'ممتاز، ثبّت وجهك للحظة',
  ];

  @override
  void initState() {
    super.initState();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      lowerBound: .96,
      upperBound: 1.03,
    )..repeat(reverse: true);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      if (mounted) {
        setState(() {
          _cameraLoading = true;

          _cameraError = false;

          _statusMessage = 'جاري تشغيل الكاميرا...';
        });
      }

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('NO_CAMERA');
      }

      CameraDescription? frontCamera;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;

          break;
        }
      }

      frontCamera ??= cameras.first;

      final controller = CameraController(
        frontCamera,
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
        _cameraLoading = false;

        _cameraReady = true;

        _cameraError = false;

        _statusMessage = 'ضع وجهك داخل الإطار';
      });
    } on CameraException catch (e) {
      debugPrint(
        'Camera initialization error: ${e.code} - ${e.description}',
      );

      if (!mounted) return;

      setState(() {
        _cameraLoading = false;

        _cameraReady = false;

        _cameraError = true;

        if (e.code == 'CameraAccessDenied' ||
            e.code == 'CameraAccessDeniedWithoutPrompt') {
          _statusMessage = 'يجب السماح للتطبيق باستخدام الكاميرا';
        } else {
          _statusMessage = 'تعذر تشغيل الكاميرا';
        }
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');

      if (!mounted) return;

      setState(() {
        _cameraLoading = false;

        _cameraReady = false;

        _cameraError = true;

        _statusMessage = 'تعذر تشغيل الكاميرا';
      });
    }
  }

  Future<void> _startEnrollment() async {
    if (_isScanning ||
        _completed ||
        !_cameraReady ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    final previousImage = _bestFrontImagePath;
    _bestFrontImagePath = null;
    _bestFrontFaceArea = -1;
    await _deleteFileSafely(previousImage);

    if (!mounted) return;

    setState(() {
      _isScanning = true;
      _completed = false;
      _step = 0;
      _progress = .05;
      _validFrames = 0;
      _statusMessage = _instructions[0];
    });

    _scanController.repeat(reverse: true);

    _scanTimer?.cancel();

    _scanTimer = Timer.periodic(
      const Duration(milliseconds: 850),
      (_) {
        _captureAndProcess();
      },
    );

    await _captureAndProcess();
  }

  Future<void> _captureAndProcess() async {
    if (!_isScanning ||
        _processingFrame ||
        _completed ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _processingFrame = true;
    String? currentImagePath;

    try {
      final file = await _cameraController!.takePicture();
      currentImagePath = file.path;

      if (!_isScanning || !mounted) {
        return;
      }

      final inputImage = InputImage.fromFilePath(currentImagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted || !_isScanning) {
        return;
      }

      if (faces.isEmpty) {
        _validFrames = 0;

        setState(() {
          _statusMessage = 'لم يتم اكتشاف الوجه، قرّب وجهك من الكاميرا';
        });

        return;
      }

      if (faces.length > 1) {
        _validFrames = 0;

        setState(() {
          _statusMessage = 'يجب أن يظهر شخص واحد فقط أمام الكاميرا';
        });

        return;
      }

      final face = faces.first;

      final yaw = face.headEulerAngleY ?? 0;
      final roll = face.headEulerAngleZ ?? 0;

      if (roll.abs() > 22) {
        _validFrames = 0;

        setState(() {
          _statusMessage = 'اجعل الهاتف والوجه في وضع مستقيم';
        });

        return;
      }

      // Keep only the best frontal frame. It becomes the biometric reference
      // after the liveness sequence succeeds.
      if ((_step == 0 || _step == 3) && yaw.abs() <= 12) {
        final kept = await _considerAsBestFrontFrame(
          currentImagePath,
          face,
        );

        if (kept) {
          currentImagePath = null;
        }
      }

      _processFaceDirection(face, yaw);
    } catch (e) {
      debugPrint('Face processing error: $e');

      if (mounted && _isScanning) {
        setState(() {
          _statusMessage = 'ثبّت الهاتف وحاول مرة أخرى';
        });
      }
    } finally {
      if (currentImagePath != null) {
        await _deleteFileSafely(currentImagePath);
      }

      _processingFrame = false;
    }
  }

  Future<bool> _considerAsBestFrontFrame(
    String imagePath,
    Face face,
  ) async {
    final area = face.boundingBox.width * face.boundingBox.height;

    if (area <= _bestFrontFaceArea) {
      return false;
    }

    final oldPath = _bestFrontImagePath;

    _bestFrontImagePath = imagePath;
    _bestFrontFaceArea = area;

    if (oldPath != null && oldPath != imagePath) {
      await _deleteFileSafely(oldPath);
    }

    return true;
  }

  Future<void> _deleteFileSafely(String? path) async {
    if (path == null || path.isEmpty) return;

    try {
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A temporary camera-file cleanup failure must not abort enrollment.
    }
  }

  void _processFaceDirection(Face face, double yaw) {
    if (!mounted || !_isScanning) return;

    bool valid = false;

    switch (_step) {
      case 0:
        // أمام الكاميرا.
        valid = yaw.abs() <= 12;

        if (!valid) {
          _statusMessage = 'انظر مباشرة إلى الكاميرا';
        }

        break;

      case 1:
        // الكاميرا الأمامية قد تعكس الاتجاه بصرياً،        // لكن ML Kit يعطينا زاوية الرأس الفعلية.
        valid = yaw >= 16;

        if (!valid) {
          _statusMessage = 'حرّك وجهك قليلاً إلى اليمين';
        }

        break;

      case 2:
        valid = yaw <= -16;

        if (!valid) {
          _statusMessage = 'حرّك وجهك قليلاً إلى اليسار';
        }

        break;

      case 3:
        valid = yaw.abs() <= 12;

        if (!valid) {
          _statusMessage = 'ارجع بوجهك للأمام وثبّته للحظة';
        }

        break;
    }

    if (!valid) {
      _validFrames = 0;

      setState(() {});

      return;
    }

    _validFrames++;

    setState(() {
      _statusMessage = _step == 3 ? 'ممتاز، ثبّت وجهك للحظة' : 'ممتاز... استمر';
    });
    // نطلب أكثر من قراءة صحيحة حتى لا تنتقل الخطوة        // بسبب Frame واحد خاطئ.
    if (_validFrames < 2) return;

    _validFrames = 0;

    if (_step < _instructions.length - 1) {
      setState(() {
        _step++;

        _progress = (_step + .15) / _instructions.length;

        _statusMessage = _instructions[_step];
      });

      return;
    }

    _finishEnrollment();
  }

  Future<void> _finishEnrollment() async {
    if (_completed || _savingFirebase) return;

    _scanTimer?.cancel();
    _scanTimer = null;

    _scanController.stop();

    setState(() {
      _isScanning = false;
      _savingFirebase = true;
      _progress = .90;
      _statusMessage = 'جاري إنشاء بصمة الوجه...';
    });

    try {
      final imagePath = _bestFrontImagePath;

      if (imagePath == null || imagePath.isEmpty) {
        throw Exception('NO_REFERENCE_FACE');
      }

      final imageFile = File(imagePath);

      if (!await imageFile.exists()) {
        throw Exception('REFERENCE_IMAGE_NOT_FOUND');
      }

      final Uint8List imageBytes = await imageFile.readAsBytes();

      if (imageBytes.isEmpty) {
        throw Exception('EMPTY_REFERENCE_IMAGE');
      }

      if (!mounted) return;

      setState(() {
        _progress = .93;
        _statusMessage = 'جاري التحقق من جودة بصمة الوجه...';
      });

      // The plugin performs its own face detection for the exact image that
      // will be passed to MobileFaceNet. This guarantees index alignment
      // between the detected face and the returned feature vector.
      final pluginFaces = await fp.FacePlugin.detectFaces(imageBytes);

      if (pluginFaces.isEmpty) {
        throw Exception('PLUGIN_FACE_NOT_FOUND');
      }

      if (pluginFaces.length != 1) {
        throw Exception('MULTIPLE_PLUGIN_FACES');
      }

      final pluginFace = pluginFaces.first;

      if (pluginFace.landmarkCount < 3 || pluginFace.faceScore < .60) {
        throw Exception('LOW_FACE_QUALITY');
      }

      if (pluginFace.headEulerAngleY.abs() > 20 ||
          pluginFace.headEulerAngleZ.abs() > 20) {
        throw Exception('FACE_NOT_FRONTAL');
      }

      if (!mounted) return;

      setState(() {
        _progress = .95;
        _statusMessage = 'جاري استخراج بصمة الوجه...';
      });

      final features = await fp.FacePlugin.extractFeatures(imageBytes);

      if (features.length != 1) {
        throw Exception('FEATURE_EXTRACTION_FAILED');
      }

      final List<double> embedding = List<double>.from(features.first);

      if (embedding.isEmpty) {
        throw Exception('EMPTY_EMBEDDING');
      }

      for (final value in embedding) {
        if (value.isNaN || value.isInfinite) {
          throw Exception('INVALID_EMBEDDING');
        }
      }

      final code = widget.employeeCode.trim().toUpperCase();

      if (code.isEmpty) {
        throw Exception('INVALID_EMPLOYEE_CODE');
      }

      if (!mounted) return;

      setState(() {
        _progress = .97;
        _statusMessage = 'جاري ربط بصمة الوجه بحسابك...';
      });

      final employeesRef = FirebaseDatabase.instance.ref('employees');

      final snapshot = await employeesRef
          .orderByChild('emp_code')
          .equalTo(code)
          .limitToFirst(1)
          .get();

      if (!snapshot.exists || snapshot.children.isEmpty) {
        throw Exception('EMPLOYEE_NOT_FOUND');
      }

      final employeeSnapshot = snapshot.children.first;
      final employeeKey = employeeSnapshot.key;

      if (employeeKey == null || employeeKey.isEmpty) {
        throw Exception('EMPLOYEE_KEY_NOT_FOUND');
      }

      await FirebaseDatabase.instance.ref('employees/$employeeKey').update({
        'face_biometric': {
          'version': 1,
          'model': 'mobilefacenet',
          'embedding_dimension': embedding.length,
          'embedding': embedding,
          'quality': {
            'landmark_count': pluginFace.landmarkCount,
            'face_score': pluginFace.faceScore,
            'yaw': pluginFace.headEulerAngleY,
            'pitch': pluginFace.headEulerAngleX,
            'roll': pluginFace.headEulerAngleZ,
          },
          'created_at': ServerValue.timestamp,
          'updated_at': ServerValue.timestamp,
        },
        'face_template_version': 1,
        'face_enrolled': true,
        'account_activated': true,
        'app_status': 'نشط',
        'face_enrolled_at': ServerValue.timestamp,
        'account_activated_at': ServerValue.timestamp,
        'updated_at': ServerValue.timestamp,
      });

      await _deleteFileSafely(imagePath);
      _bestFrontImagePath = null;
      _bestFrontFaceArea = -1;

      if (!mounted) return;

      setState(() {
        _savingFirebase = false;
        _completed = true;
        _progress = 1;
        _statusMessage = 'تم تسجيل بصمة الوجه بنجاح';
      });
    } on FirebaseException catch (e) {
      debugPrint(
        'Face enrollment Firebase error: ${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _savingFirebase = false;
        _completed = false;
        _progress = 0;

        if (e.code == 'permission-denied') {
          _statusMessage = 'لا توجد صلاحية لحفظ بيانات الحساب';
        } else {
          _statusMessage = 'تعذر حفظ بصمة الوجه، حاول مرة أخرى';
        }
      });
    } catch (e, stackTrace) {
      debugPrint('Face enrollment save error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      final error = e.toString();
      String message = 'تعذر تسجيل بصمة الوجه، حاول مرة أخرى';

      if (error.contains('LOW_FACE_QUALITY')) {
        message = 'صورة الوجه غير واضحة، استخدم إضاءة أفضل وحاول مرة أخرى';
      } else if (error.contains('FACE_NOT_FRONTAL')) {
        message = 'انظر مباشرة إلى الكاميرا أثناء حفظ بصمة الوجه';
      } else if (error.contains('MULTIPLE_PLUGIN_FACES')) {
        message = 'يجب أن يظهر شخص واحد فقط أمام الكاميرا';
      } else if (error.contains('NO_REFERENCE_FACE') ||
          error.contains('REFERENCE_IMAGE_NOT_FOUND') ||
          error.contains('PLUGIN_FACE_NOT_FOUND')) {
        message = 'لم نتمكن من الحصول على صورة واضحة لوجهك، حاول مرة أخرى';
      } else if (error.contains('FEATURE_EXTRACTION_FAILED') ||
          error.contains('EMPTY_EMBEDDING') ||
          error.contains('INVALID_EMBEDDING')) {
        message = 'تعذر إنشاء بصمة الوجه، حاول مرة أخرى';
      }

      setState(() {
        _savingFirebase = false;
        _completed = false;
        _progress = 0;
        _statusMessage = message;
      });
    }
  }

  void _continueToActivatedScreen() {
    if (!_completed) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AccountActivatedScreen(
          employeeName: widget.employeeName,
          employeeCode: widget.employeeCode,
        ),
      ),
    );
  }

  Future<void> _retryCamera() async {
    try {
      await _cameraController?.dispose();
    } catch (_) {}

    _cameraController = null;

    setState(() {
      _cameraReady = false;

      _cameraError = false;

      _cameraLoading = true;
    });

    await _initializeCamera();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();

    _scanController.dispose();
    _pulseController.dispose();

    _faceDetector.close();
    _cameraController?.dispose();

    final tempImage = _bestFrontImagePath;
    _bestFrontImagePath = null;

    if (tempImage != null && tempImage.isNotEmpty) {
      try {
        File(tempImage).deleteSync();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Background(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    0,
                  ),
                  child: _Header(
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: _ProgressSteps(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      22,
                      26,
                      22,
                      22,
                    ),
                    child: Column(
                      children: [
                        Text(
                          _completed ? 'تم تسجيل وجهك' : 'تسجيل بصمة الوجه',
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
                          _completed
                              ? 'تم حفظ بصمة الوجه بنجاح وأصبح حسابك جاهزاً'
                              : 'سنستخدم بصمة الوجه للتحقق من هويتك\n'
                                  'عند تسجيل الحضور والانصراف',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: 12.5,
                                    height: 1.6,
                                  ),
                        ),
                        const SizedBox(height: 30),
                        _FaceScanner(
                          scanController: _scanController,
                          pulseController: _pulseController,
                          cameraController: _cameraController,
                          cameraLoading: _cameraLoading,
                          cameraReady: _cameraReady,
                          cameraError: _cameraError,
                          scanning: _isScanning,
                          completed: _completed,
                          saving: _savingFirebase,
                        ),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _completed
                              ? const _CompletedStatus()
                              : _InstructionStatus(
                                  key: ValueKey(
                                    '${_step}_$_statusMessage',
                                  ),
                                  scanning: _isScanning,
                                  cameraLoading: _cameraLoading,
                                  cameraError: _cameraError,
                                  instruction: _statusMessage,
                                ),
                        ),
                        const SizedBox(height: 20),
                        _EnrollmentProgress(
                          progress: _progress,
                          scanning: _isScanning,
                          completed: _completed,
                          saving: _savingFirebase,
                        ),
                        const SizedBox(height: 25),
                        if (!_isScanning && !_completed && !_savingFirebase)
                          const _FaceTips(),
                        if (!_isScanning && !_completed && !_savingFirebase)
                          const SizedBox(height: 24),
                        if (_cameraError)
                          _RetryCameraButton(
                            loading: _cameraLoading,
                            onPressed: _retryCamera,
                          )
                        else
                          _MainButton(
                            scanning: _isScanning || _savingFirebase,
                            completed: _completed,
                            cameraReady: _cameraReady,
                            onPressed: _completed
                                ? _continueToActivatedScreen
                                : _startEnrollment,
                          ),
                        const SizedBox(height: 17),
                        if (!_completed) const _PrivacyNotice(),
                      ],
                    ),
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

class _FaceScanner extends StatelessWidget {
  final AnimationController scanController;

  final AnimationController pulseController;

  final CameraController? cameraController;

  final bool cameraLoading;

  final bool cameraReady;

  final bool cameraError;

  final bool scanning;

  final bool completed;

  final bool saving;

  const _FaceScanner({
    required this.scanController,
    required this.pulseController,
    required this.cameraController,
    required this.cameraLoading,
    required this.cameraReady,
    required this.cameraError,
    required this.scanning,
    required this.completed,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: pulseController,
      child: SizedBox(
        width: 270,
        height: 310,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 250,
              height: 290,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(125),
                boxShadow: [
                  BoxShadow(
                    color: completed
                        ? AppColors.success.withOpacity(.12)
                        : AppColors.primary.withOpacity(.11),
                    blurRadius: 50,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(125),
              child: Container(
                width: 230,
                height: 280,
                color: const Color(0xFFEAF3F8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cameraReady &&
                        cameraController != null &&
                        cameraController!.value.isInitialized)
                      _CameraView(
                        controller: cameraController!,
                      )
                    else
                      _CameraPlaceholder(
                        loading: cameraLoading,
                        error: cameraError,
                      ),
                    CustomPaint(
                      painter: _GridPainter(),
                    ),
                    if (scanning)
                      AnimatedBuilder(
                        animation: scanController,
                        builder: (_, __) {
                          return Positioned(
                            top: 25 + (220 * scanController.value),
                            left: 24,
                            right: 24,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.sky.withOpacity(.8),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.sky,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (completed)
                      Container(
                        color: AppColors.success.withOpacity(.12),
                        child: Center(
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success.withOpacity(.25),
                                  blurRadius: 25,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 35,
                            ),
                          ),
                        ),
                      ),
                    if (saving)
                      Container(
                        color: AppColors.navy.withOpacity(.22),
                        child: const Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ScannerCornersPainter(
                    color: completed ? AppColors.success : AppColors.primary,
                  ),
                ),
              ),
            ),
            if (scanning)
              Positioned(
                top: 22,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withOpacity(.82),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      _LiveDot(),
                      SizedBox(width: 6),
                      Text(
                        'جاري التحقق',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
  }
}

class _CameraView extends StatelessWidget {
  final CameraController controller;

  const _CameraView({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return const SizedBox.expand();
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  final bool loading;

  final bool error;

  const _CameraPlaceholder({
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFDCEBF4).withOpacity(.72),
            const Color(0xFFF5FAFD).withOpacity(.92),
          ],
        ),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: AppColors.primary,
                ),
              )
            : Icon(
                error ? Icons.no_photography_outlined : Icons.face_outlined,
                size: 72,
                color: error
                    ? AppColors.error.withOpacity(.65)
                    : AppColors.primary.withOpacity(.15),
              ),
      ),
    );
  }
}

class _InstructionStatus extends StatelessWidget {
  final bool scanning;

  final bool cameraLoading;

  final bool cameraError;

  final String instruction;

  const _InstructionStatus({
    super.key,
    required this.scanning,
    required this.cameraLoading,
    required this.cameraError,
    required this.instruction,
  });

  @override
  Widget build(BuildContext context) {
    final error = cameraError;

    return Container(
      constraints: const BoxConstraints(
        minHeight: 40,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: error
            ? AppColors.error.withOpacity(.07)
            : scanning
                ? AppColors.primary.withOpacity(.07)
                : Colors.white.withOpacity(.60),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: error
              ? AppColors.error.withOpacity(.12)
              : scanning
                  ? AppColors.primary.withOpacity(.12)
                  : Colors.white,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cameraLoading)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: AppColors.primary,
              ),
            )
          else
            Icon(
              error
                  ? Icons.error_outline_rounded
                  : scanning
                      ? Icons.face_retouching_natural
                      : Icons.face_outlined,
              size: 17,
              color: error ? AppColors.error : AppColors.primary,
            ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              instruction,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: error ? AppColors.error : AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedStatus extends StatelessWidget {
  const _CompletedStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(.09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            size: 17,
            color: AppColors.success,
          ),
          SizedBox(width: 6),
          Text(
            'تم التحقق من جميع الاتجاهات',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollmentProgress extends StatelessWidget {
  final double progress;

  final bool scanning;

  final bool completed;

  final bool saving;

  const _EnrollmentProgress({
    required this.progress,
    required this.scanning,
    required this.completed,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: safeProgress,
              minHeight: 4,
              backgroundColor: AppColors.border,
              color: completed ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            completed
                ? 'اكتمل التسجيل'
                : saving
                    ? 'جاري حفظ التسجيل...'
                    : scanning
                        ? '${(safeProgress * 100).round()}% من عملية التسجيل'
                        : 'جاهز لبدء التسجيل',
            style: TextStyle(
              fontSize: 9.5,
              color: completed ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceTips extends StatelessWidget {
  const _FaceTips();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.58),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white,
        ),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _Tip(
              icon: Icons.light_mode_outlined,
              text: 'إضاءة جيدة',
            ),
          ),
          _SmallDivider(),
          Expanded(
            child: _Tip(
              icon: Icons.face_outlined,
              text: 'الوجه واضح',
            ),
          ),
          _SmallDivider(),
          Expanded(
            child: _Tip(
              icon: Icons.phone_android_rounded,
              text: 'ثبّت الهاتف',
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;

  final String text;

  const _Tip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SmallDivider extends StatelessWidget {
  const _SmallDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: AppColors.border,
    );
  }
}

class _MainButton extends StatelessWidget {
  final bool scanning;

  final bool completed;

  final bool cameraReady;

  final VoidCallback onPressed;

  const _MainButton({
    required this.scanning,
    required this.completed,
    required this.cameraReady,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = completed || (!scanning && cameraReady);

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: completed
              ? const LinearGradient(
                  colors: [
                    AppColors.success,
                    Color(0xFF16895A),
                  ],
                )
              : const LinearGradient(
                  colors: [
                    AppColors.primaryDark,
                    AppColors.primary,
                  ],
                ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (completed ? AppColors.success : AppColors.primary)
                  .withOpacity(.18),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
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
          child: scanning
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 9),
                    Text(
                      'جاري تسجيل الوجه...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      completed ? Icons.arrow_back_rounded : Icons.face_rounded,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      completed
                          ? 'متابعة'
                          : cameraReady
                              ? 'بدء تسجيل الوجه'
                              : 'جاري تجهيز الكاميرا...',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RetryCameraButton extends StatelessWidget {
  final bool loading;

  final VoidCallback onPressed;

  const _RetryCameraButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.refresh_rounded,
                size: 18,
              ),
        label: const Text(
          'إعادة تشغيل الكاميرا',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

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
          'بيانات الوجه تستخدم للتحقق من الهوية فقط',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 9.5,
              ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;

  const _Header({
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
                'إعداد الهوية البيومترية',
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

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            3,
            (index) => Expanded(
              child: Container(
                margin: EdgeInsetsDirectional.only(
                  end: index == 2 ? 0 : 7,
                ),
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StepText('التحقق'),
            _StepText('كلمة المرور'),
            _StepText('بصمة الوجه'),
          ],
        ),
      ],
    );
  }
}

class _StepText extends StatelessWidget {
  final String text;

  const _StepText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9.5,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: .35,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFF65E5C1),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ScannerCornersPainter extends CustomPainter {
  final Color color;

  _ScannerCornersPainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const length = 34.0;

    const left = 12.0;

    final right = size.width - 12;

    const top = 16.0;

    final bottom = size.height - 16;

    canvas.drawLine(
      const Offset(left, top + length),
      const Offset(left, top),
      paint,
    );

    canvas.drawLine(
      const Offset(left, top),
      const Offset(left + length, top),
      paint,
    );

    canvas.drawLine(
      Offset(right - length, top),
      Offset(right, top),
      paint,
    );

    canvas.drawLine(
      Offset(right, top),
      Offset(right, top + length),
      paint,
    );

    canvas.drawLine(
      Offset(left, bottom - length),
      Offset(left, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(left, bottom),
      Offset(left + length, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(right - length, bottom),
      Offset(right, bottom),
      paint,
    );

    canvas.drawLine(
      Offset(right, bottom),
      Offset(right, bottom - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _ScannerCornersPainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(.035)
      ..strokeWidth = .6;

    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

class _Background extends StatelessWidget {
  const _Background();

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
          top: -150,
          left: -120,
          child: _Glow(
            size: 340,
            color: AppColors.sky.withOpacity(.12),
          ),
        ),
        Positioned(
          right: -160,
          bottom: -130,
          child: _Glow(
            size: 400,
            color: AppColors.primary.withOpacity(.08),
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
