import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_mesh_detection/google_mlkit_face_mesh_detection.dart';
import 'package:camera/camera.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FaceMeshDetectionScreen(cameras: cameras),
    );
  }
}

class FaceMeshDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceMeshDetectionScreen({super.key, required this.cameras});

  @override
  _FaceMeshDetectionScreenState createState() =>
      _FaceMeshDetectionScreenState();
}

class _FaceMeshDetectionScreenState extends State<FaceMeshDetectionScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  List<FaceMesh>? _faceMeshes;
  ui.Image? _necklaceImage;
  ui.Image? _earringsImage;
  final FaceMeshDetector _meshDetector =
      FaceMeshDetector(option: FaceMeshDetectorOptions.faceMesh);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadJewelryImages();
  }

  Future<void> _initializeCamera() async {
    _cameraController = CameraController(
      widget.cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front),
      ResolutionPreset.low,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController?.initialize();
    _cameraController?.startImageStream(_processCameraImage);

    setState(() {
      _isCameraInitialized = true;
    });

    print('Camera Resolution: ${_cameraController?.value.previewSize}');
  }

  Future<void> _loadJewelryImages() async {
    final ByteData necklaceData = await rootBundle.load('assets/necklace.png');
    final ByteData earringData = await rootBundle.load('assets/earring.png');

    final necklaceImage =
        await decodeImageFromList(necklaceData.buffer.asUint8List());
    final earringImage =
        await decodeImageFromList(earringData.buffer.asUint8List());

    setState(() {
      _necklaceImage = necklaceImage;
      _earringsImage = earringImage;
    });
  }

  void _processCameraImage(CameraImage cameraImage) async {
    final inputImage = _convertCameraImageToInputImage(cameraImage);
    final List<FaceMesh> meshes = await _meshDetector.processImage(inputImage);

    if (meshes.isNotEmpty) {
      // Log information about the first detected face mesh
      final firstMesh = meshes.first;
      print('Bounding Box: ${firstMesh.boundingBox}');

      // Log more specific face mesh point details for debugging
      final chinPoint = firstMesh.points[152]; // Chin
      final nosePoint = firstMesh.points[1]; // Nose
      final leftEarPoint = firstMesh.points[234]; // Left Ear
      final rightEarPoint = firstMesh.points[454]; // Right Ear

      print('Chin Point: x=${chinPoint.x}, y=${chinPoint.y}');
      print('Nose Point: x=${nosePoint.x}, y=${nosePoint.y}');
      print('Left Ear Point: x=${leftEarPoint.x}, y=${leftEarPoint.y}');
      print('Right Ear Point: x=${rightEarPoint.x}, y=${rightEarPoint.y}');
    }

    setState(() {
      _faceMeshes = meshes;
    });
  }

  InputImage _convertCameraImageToInputImage(CameraImage cameraImage) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    final int rotationDegrees =
        _cameraController!.description.sensorOrientation;
    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(rotationDegrees) ??
            InputImageRotation.rotation0deg;

    final InputImageFormat inputImageFormat;
    if (Platform.isAndroid) {
      inputImageFormat = InputImageFormat.nv21;
    } else if (Platform.isIOS) {
      inputImageFormat = InputImageFormat.bgra8888;
    } else {
      throw Exception('Unsupported platform');
    }

    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: cameraImage.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageMetadata,
    );

    return inputImage;
  }

  @override
  void dispose() {
    _meshDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Face Mesh Detection'),
      ),
      body: _isCameraInitialized
          ? Stack(
              children: [
                CameraPreview(_cameraController!),
                if (_cameraController != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Text(
                      "Preview Size: ${_cameraController!.value.previewSize?.width} x ${_cameraController!.value.previewSize?.height}",
                      style: const TextStyle(
                        backgroundColor: Colors.black54,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (_faceMeshes != null &&
                    _necklaceImage != null &&
                    _earringsImage != null)
                  CustomPaint(
                    size: Size(
                      MediaQuery.of(context).size.width,
                      MediaQuery.of(context).size.height,
                    ),
                    painter: FaceMeshPainter(
                      _faceMeshes!,
                      _necklaceImage!,
                      _earringsImage!,
                      _cameraController!.value.previewSize!,
                      MediaQuery.of(context).size,
                    ),
                    child: Container(),
                  ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class FaceMeshPainter extends CustomPainter {
  final List<FaceMesh> faceMeshes;
  final ui.Image necklaceImage;
  final ui.Image earringsImage;
  final Size cameraPreviewSize;
  final Size screenSize;

  FaceMeshPainter(this.faceMeshes, this.necklaceImage, this.earringsImage,
      this.cameraPreviewSize, this.screenSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill
      ..strokeWidth = 5;

    // Scale factors to match camera preview with screen dimensions
    double scaleX = size.width / cameraPreviewSize.width;
    double scaleY = size.height / cameraPreviewSize.height;

    // Offset to center the preview on screen
    double offsetX = 0;
    double offsetY = 0;

    if (scaleX > scaleY) {
      // Wider aspect ratio
      scaleX = scaleY;
      offsetX = (size.width - (cameraPreviewSize.width * scaleX)) / 2;
    } else {
      // Taller aspect ratio
      scaleY = scaleX;
      offsetY = (size.height - (cameraPreviewSize.height * scaleY)) / 2;
    }

    for (FaceMesh mesh in faceMeshes) {
      // Draw bounding box
      final boundingBox = mesh.boundingBox;
      final scaledBox = Rect.fromLTRB(
        (boundingBox.left * scaleX) + offsetX,
        (boundingBox.top * scaleY) + offsetY,
        (boundingBox.right * scaleX) + offsetX,
        (boundingBox.bottom * scaleY) + offsetY,
      );
      canvas.drawRect(scaledBox, paint);

      // Draw face mesh points
      for (var point in mesh.points) {
        canvas.drawCircle(
          Offset(
            (point.x * scaleX) + offsetX,
            (point.y * scaleY) + offsetY,
          ),
          3,
          pointPaint,
        );
      }

      // Key landmarks
      final chinPoint = mesh.points[152];
      final leftEarPoint = mesh.points[234];
      final rightEarPoint = mesh.points[454];

      // Debugging: Verify alignment of key points
      canvas.drawCircle(
        Offset(
          (chinPoint.x * scaleX) + offsetX,
          (chinPoint.y * scaleY) + offsetY,
        ),
        6,
        Paint()..color = Colors.green,
      ); // Chin

      canvas.drawCircle(
        Offset(
          (leftEarPoint.x * scaleX) + offsetX,
          (leftEarPoint.y * scaleY) + offsetY,
        ),
        6,
        Paint()..color = Colors.yellow,
      ); // Left Ear

      canvas.drawCircle(
        Offset(
          (rightEarPoint.x * scaleX) + offsetX,
          (rightEarPoint.y * scaleY) + offsetY,
        ),
        6,
        Paint()..color = Colors.purple,
      ); // Right Ear

      // Place jewelry (adjusted for scaling and offsets)
      _drawJewelry(canvas, scaledBox, leftEarPoint, rightEarPoint, scaleX,
          scaleY, offsetX, offsetY);
    }
  }

  void _drawJewelry(
    Canvas canvas,
    Rect scaledBox,
    FaceMeshPoint leftEarPoint,
    FaceMeshPoint rightEarPoint,
    double scaleX,
    double scaleY,
    double offsetX,
    double offsetY,
  ) {
    final paint = Paint();

    // Necklace Placement
    final necklaceWidth = scaledBox.width * 0.9;
    final necklaceHeight = necklaceWidth * 0.4;
    final neckTopY = scaledBox.bottom + 10; // Just below the bounding box
    final neckLeftX = scaledBox.center.dx - (necklaceWidth / 2);

    final necklaceRect = Rect.fromLTWH(
      neckLeftX,
      neckTopY,
      necklaceWidth,
      necklaceHeight,
    );

    canvas.drawImageRect(
      necklaceImage,
      Offset.zero &
          Size(necklaceImage.width.toDouble(), necklaceImage.height.toDouble()),
      necklaceRect,
      paint,
    );

    // Earrings Placement
    final earringSize = scaledBox.width * 0.2;

    // Left Earring
    final leftEarringRect = Rect.fromLTWH(
      (leftEarPoint.x * scaleX) + offsetX - earringSize / 2,
      (leftEarPoint.y * scaleY) + offsetY - earringSize / 2,
      earringSize,
      earringSize,
    );
    canvas.drawImageRect(
      earringsImage,
      Offset.zero &
          Size(earringsImage.width.toDouble(), earringsImage.height.toDouble()),
      leftEarringRect,
      paint,
    );

    // Right Earring
    final rightEarringRect = Rect.fromLTWH(
      (rightEarPoint.x * scaleX) + offsetX - earringSize / 2,
      (rightEarPoint.y * scaleY) + offsetY - earringSize / 2,
      earringSize,
      earringSize,
    );
    canvas.drawImageRect(
      earringsImage,
      Offset.zero &
          Size(earringsImage.width.toDouble(), earringsImage.height.toDouble()),
      rightEarringRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
