import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/face_service.dart';
import '../services/database_service.dart';

class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key});

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  CameraController? _cameraController;
  final FaceService _faceService = FaceService();
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _nameController = TextEditingController();
  bool _isProcessing = false;
  String _message = '';
  bool _faceDetected = false;
  int _captureCount = 0;
  final int _totalCaptures = 5;
  String _selectedRole = 'Staff';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceService.initialize();
    _databaseService.initialize();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    setState(() {});
  }

  Future<void> _enrollFace() async {
    if (_nameController.text.isEmpty) {
      setState(() => _message = 'Please enter a name');
      return;
    }

    setState(() {
      _isProcessing = true;
      _captureCount = 0;
      _message = 'Capturing image 1/$_totalCaptures...';
    });

    try {
      List<List<double>> embeddings = [];
      
      // Auto-capture multiple images
      for (int i = 0; i < _totalCaptures; i++) {
        setState(() => _message = 'Capturing image ${i + 1}/$_totalCaptures...');
        
        // Wait a moment between captures
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
        
        final image = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(image.path);
        
        final embedding = await _faceService.detectAndEmbed(inputImage);
        
        if (embedding != null) {
          embeddings.add(embedding);
          setState(() => _captureCount = i + 1);
        } else {
          setState(() => _message = 'No face detected in image ${i + 1}. Keep your face visible.');
          await Future.delayed(const Duration(seconds: 1));
          i--; // Retry this capture
          continue;
        }
      }
      
      if (embeddings.length == _totalCaptures) {
        // Average all embeddings
        setState(() => _message = 'Processing $_totalCaptures images...');
        final averagedEmbedding = _faceService.averageEmbeddings(embeddings);
        
        await _databaseService.saveFace(_nameController.text, _selectedRole, averagedEmbedding);
        setState(() => _message = 'Face enrolled successfully with $_totalCaptures images!');
        
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        setState(() => _message = 'Failed to capture enough images. Please try again.');
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
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Face'),
      ),
      body: _cameraController?.value.isInitialized ?? false
          ? Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),
                      if (_faceDetected)
                        Center(
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green, width: 3),
                              borderRadius: BorderRadius.circular(125),
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
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Enter Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: ['Staff', 'Worker'].map((role) {
                          return DropdownMenuItem(
                            value: role,
                            child: Text(role),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedRole = value!);
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_message.isNotEmpty)
                        Column(
                          children: [
                            Text(
                              _message,
                              style: TextStyle(
                                color: _message.contains('success')
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_isProcessing && _captureCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: LinearProgressIndicator(
                                  value: _captureCount / _totalCaptures,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _enrollFace,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          child: _isProcessing
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Start Enrollment (5 captures)',
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
