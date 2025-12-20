import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import '../face_embedder.dart';

class FaceService {
  late FaceDetector _faceDetector;
  late FaceEmbedder _faceEmbedder;

  Future<void> initialize() async {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    _faceEmbedder = FaceEmbedder();
    await _faceEmbedder.loadModel();
  }

  List<double> averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    
    final size = embeddings.first.length;
    final averaged = List<double>.filled(size, 0.0);
    
    for (var embedding in embeddings) {
      for (int i = 0; i < size; i++) {
        averaged[i] += embedding[i];
      }
    }
    
    for (int i = 0; i < size; i++) {
      averaged[i] /= embeddings.length;
    }
    
    return averaged;
  }

  Future<List<double>?> detectAndEmbed(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isEmpty) {
        print('No faces detected');
        return null;
      }

      // Load the image file
      final imageFile = File(inputImage.filePath!);
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        print('Failed to decode image');
        return null;
      }

      // Get the first detected face
      final face = faces.first;
      final boundingBox = face.boundingBox;

      // Crop the face from the image
      final faceImg = img.copyCrop(
        image,
        x: boundingBox.left.toInt().clamp(0, image.width),
        y: boundingBox.top.toInt().clamp(0, image.height),
        width: boundingBox.width.toInt().clamp(0, image.width - boundingBox.left.toInt()),
        height: boundingBox.height.toInt().clamp(0, image.height - boundingBox.top.toInt()),
      );

      // Get embedding
      final embedding = _faceEmbedder.getEmbedding(faceImg);
      return embedding;
    } catch (e) {
      print('Error in detectAndEmbed: $e');
      return null;
    }
  }

  void dispose() {
    _faceDetector.close();
    _faceEmbedder.dispose();
  }
}
