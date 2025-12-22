import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/face_service.dart';
import '../services/database_service.dart';

class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  CameraController? _cameraController;
  final FaceService _faceService = FaceService();
  final DatabaseService _databaseService = DatabaseService();
  bool _isProcessing = false;
  String _message = '';
  String _recognizedName = '';
  String _accuracyScore = '';
  List<CameraDescription> _cameras = [];
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceService.initialize();
    _databaseService.initialize();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    final camera = _cameras.firstWhere(
      (camera) => camera.lensDirection == (_isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
      orElse: () => _cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    if (_isProcessing) return;
    
    setState(() => _isFrontCamera = !_isFrontCamera);
    await _cameraController?.dispose();
    await _initializeCamera();
  }

  Future<void> _recognizeFace() async {
    setState(() {
      _isProcessing = true;
      _message = 'Recognizing...';
    });

    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      
      final embedding = await _faceService.detectAndEmbed(inputImage);
      
      if (embedding != null) {
        final match = await _databaseService.findMatch(embedding);
        
        if (match != null && match['name'] != null && match['role'] != null) {
          final name = match['name'] as String;
          final role = match['role'] as String;
          final shift = match['shift'] ?? 'Day';
          final accuracy = match['accuracy'] as String? ?? '0.0';
          final confidence = match['confidence'] as double? ?? 0.0;
          
          // Color based on confidence
          Color confidenceColor;
          String confidenceLabel;
          if (confidence >= 0.9) {
            confidenceColor = Colors.green;
            confidenceLabel = 'Excellent';
          } else if (confidence >= 0.85) {
            confidenceColor = Colors.lightGreen;
            confidenceLabel = 'Very Good';
          } else if (confidence >= 0.80) {
            confidenceColor = Colors.orange;
            confidenceLabel = 'Good';
          } else {
            confidenceColor = Colors.deepOrange;
            confidenceLabel = 'Fair';
          }
          
          // Record attendance and check status
          final attendanceStatus = await _databaseService.recordAttendance(name, role);
          
          String statusMessage;
          if (attendanceStatus == 'IN') {
            statusMessage = '✓ IN Time Marked';
          } else if (attendanceStatus == 'OUT') {
            statusMessage = '✓ OUT Time Marked';
          } else if (attendanceStatus == 'IN_ALREADY_MARKED') {
            statusMessage = '⚠ IN Time Already Marked Today';
          } else if (attendanceStatus == 'OUT_ALREADY_MARKED') {
            statusMessage = '⚠ OUT Time Already Marked Today';
          } else {
            statusMessage = '⚠ Attendance Error';
          }
          
          setState(() {
            _recognizedName = name;
            _accuracyScore = '$accuracy% ($confidenceLabel)';
            _message = 'Recognized: $name ($role - $shift Shift)\nAccuracy: $_accuracyScore\n$statusMessage';
          });
        } else {
          setState(() {
            _recognizedName = '';
            _accuracyScore = '';
            _message = 'Face not recognized';
          });
        }
      } else {
        setState(() => _message = 'No face detected. Please try again.');
      }
    } catch (e) {
      setState(() => _message = 'Error: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognize Face'),
      ),
      body: _cameraController?.value.isInitialized ?? false
          ? Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),
                      if (_recognizedName.isNotEmpty)
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Welcome, $_recognizedName!',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (_accuracyScore.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '✓ Match: $_accuracyScore',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        top: 20,
                        right: 20,
                        child: FloatingActionButton(
                          heroTag: 'cameraToggle',
                          mini: true,
                          onPressed: _toggleCamera,
                          backgroundColor: Colors.white.withOpacity(0.8),
                          child: Icon(
                            _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  child: Column(
                    children: [
                      if (_message.isNotEmpty)
                        Text(
                          _message,
                          style: TextStyle(
                            color: _recognizedName.isNotEmpty
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _recognizeFace,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: _isProcessing
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Capture & Recognize',
                                  style: TextStyle(fontSize: 18),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
