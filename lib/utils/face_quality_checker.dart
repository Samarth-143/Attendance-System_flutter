import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:ui' show Rect;

class FaceQualityChecker {
  /// Check if the detected face meets quality requirements
  /// Returns a quality score from 0.0 to 1.0 and a message
  static FaceQuality checkQuality(Face face, img.Image image) {
    double score = 1.0;
    List<String> issues = [];
    
    // 1. Check face size (should be at least 20% of image)
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = image.width * image.height;
    final faceRatio = faceArea / imageArea;
    
    if (faceRatio < 0.10) {
      score -= 0.3;
      issues.add('Face too far (move closer)');
    } else if (faceRatio < 0.15) {
      score -= 0.15;
      issues.add('Face could be closer');
    }
    
    // 2. Check head rotation angles
    final headEulerX = face.headEulerAngleX ?? 0; // Up/Down
    final headEulerY = face.headEulerAngleY ?? 0; // Left/Right
    final headEulerZ = face.headEulerAngleZ ?? 0; // Tilt
    
    if (headEulerX.abs() > 15 || headEulerY.abs() > 15 || headEulerZ.abs() > 15) {
      score -= 0.3;
      if (headEulerX > 15) issues.add('Look up less');
      if (headEulerX < -15) issues.add('Look down less');
      if (headEulerY > 15) issues.add('Turn face left');
      if (headEulerY < -15) issues.add('Turn face right');
      if (headEulerZ.abs() > 15) issues.add('Keep head straight');
    }
    
    // 3. Check if eyes are open (using classification probabilities)
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    
    if (leftEyeOpen < 0.5 || rightEyeOpen < 0.5) {
      score -= 0.25;
      issues.add('Keep eyes open');
    }
    
    // 4. Check smiling probability (prefer neutral expression)
    final smiling = face.smilingProbability ?? 0.0;
    if (smiling > 0.7) {
      score -= 0.1;
      issues.add('Neutral expression preferred');
    }
    
    // 5. Check image brightness
    final brightness = _calculateBrightness(image, face.boundingBox);
    if (brightness < 0.2) {
      score -= 0.25;
      issues.add('Too dark (need more light)');
    } else if (brightness > 0.85) {
      score -= 0.2;
      issues.add('Too bright (reduce light)');
    }
    
    // 6. Check face position in frame
    final centerX = face.boundingBox.center.dx;
    final centerY = face.boundingBox.center.dy;
    final imageCenterX = image.width / 2;
    final imageCenterY = image.height / 2;
    
    final offsetX = (centerX - imageCenterX).abs() / image.width;
    final offsetY = (centerY - imageCenterY).abs() / image.height;
    
    if (offsetX > 0.2 || offsetY > 0.2) {
      score -= 0.15;
      if (offsetX > 0.2) issues.add('Center face horizontally');
      if (offsetY > 0.2) issues.add('Center face vertically');
    }
    
    score = max(0.0, min(1.0, score));
    
    return FaceQuality(
      score: score,
      isGoodQuality: score >= 0.7,
      issues: issues,
    );
  }
  
  /// Calculate average brightness of face region
  static double _calculateBrightness(img.Image image, Rect boundingBox) {
    int startX = max(0, boundingBox.left.toInt());
    int startY = max(0, boundingBox.top.toInt());
    int endX = min(image.width, boundingBox.right.toInt());
    int endY = min(image.height, boundingBox.bottom.toInt());
    
    double totalBrightness = 0;
    int pixelCount = 0;
    
    // Sample every 5th pixel for performance
    for (int y = startY; y < endY; y += 5) {
      for (int x = startX; x < endX; x += 5) {
        final pixel = image.getPixel(x, y);
        // Calculate relative luminance
        final brightness = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
        totalBrightness += brightness;
        pixelCount++;
      }
    }
    
    return pixelCount > 0 ? totalBrightness / pixelCount : 0.5;
  }
}

class FaceQuality {
  final double score;
  final bool isGoodQuality;
  final List<String> issues;
  
  FaceQuality({
    required this.score,
    required this.isGoodQuality,
    required this.issues,
  });
  
  String getMessage() {
    if (isGoodQuality) {
      return 'Good quality ✓';
    } else if (issues.isEmpty) {
      return 'Poor quality';
    } else {
      return issues.join(', ');
    }
  }
}
