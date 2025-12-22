import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import '../face_embedder.dart';
import '../utils/face_quality_checker.dart';

class FaceService {
  late FaceDetector _faceDetector;
  late FaceEmbedder _faceEmbedder;

  Future<void> initialize() async {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableContours: true,
        enableClassification: true,
        minFaceSize: 0.15,
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

  Future<List<double>?> detectAndEmbed(InputImage inputImage, {bool checkQuality = false}) async {
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
      
      // Check face quality if requested
      if (checkQuality) {
        final quality = FaceQualityChecker.checkQuality(face, image);
        if (!quality.isGoodQuality) {
          print('Poor face quality: ${quality.getMessage()}');
          return null;
        }
      }
      
      final boundingBox = face.boundingBox;

      // Crop the face from the image with some padding
      final padding = 20;
      final faceImg = img.copyCrop(
        image,
        x: (boundingBox.left.toInt() - padding).clamp(0, image.width),
        y: (boundingBox.top.toInt() - padding).clamp(0, image.height),
        width: (boundingBox.width.toInt() + 2 * padding).clamp(0, image.width - (boundingBox.left.toInt() - padding).clamp(0, image.width)),
        height: (boundingBox.height.toInt() + 2 * padding).clamp(0, image.height - (boundingBox.top.toInt() - padding).clamp(0, image.height)),
      );

      // Get embedding
      final embedding = _faceEmbedder.getEmbedding(faceImg);
      if (embedding != null) {
        print('DEBUG: Generated embedding with ${embedding.length} dimensions');
        print('DEBUG: First 5 values: ${embedding.take(5).toList()}');
      }
      return embedding;
    } catch (e) {
      print('Error in detectAndEmbed: $e');
      return null;
    }
  }
  
  Future<FaceDetectionResult?> detectAndEmbedWithQuality(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isEmpty) {
        return FaceDetectionResult(
          embedding: null,
          quality: null,
          message: 'No face detected',
        );
      }

      final imageFile = File(inputImage.filePath!);
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return FaceDetectionResult(
          embedding: null,
          quality: null,
          message: 'Failed to decode image',
        );
      }

      final face = faces.first;
      final quality = FaceQualityChecker.checkQuality(face, image);
      
      if (!quality.isGoodQuality) {
        return FaceDetectionResult(
          embedding: null,
          quality: quality,
          message: quality.getMessage(),
        );
      }
      
      final boundingBox = face.boundingBox;
      final padding = 20;
      
      final faceImg = img.copyCrop(
        image,
        x: (boundingBox.left.toInt() - padding).clamp(0, image.width),
        y: (boundingBox.top.toInt() - padding).clamp(0, image.height),
        width: (boundingBox.width.toInt() + 2 * padding).clamp(0, image.width - (boundingBox.left.toInt() - padding).clamp(0, image.width)),
        height: (boundingBox.height.toInt() + 2 * padding).clamp(0, image.height - (boundingBox.top.toInt() - padding).clamp(0, image.height)),
      );

      final embedding = _faceEmbedder.getEmbedding(faceImg);
      
      return FaceDetectionResult(
        embedding: embedding,
        quality: quality,
        message: 'Face detected successfully',
      );
    } catch (e) {
      return FaceDetectionResult(
        embedding: null,
        quality: null,
        message: 'Error: $e',
      );
    }
  }

  void dispose() {
    _faceDetector.close();
    _faceEmbedder.dispose();
  }
}

class FaceDetectionResult {
  final List<double>? embedding;
  final FaceQuality? quality;
  final String message;
  
  FaceDetectionResult({
    required this.embedding,
    required this.quality,
    required this.message,
  });
}
