// ML Kit Face Detection wrapper

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

final FaceDetector faceDetector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.accurate,
    enableLandmarks: true,
    enableContours: true,
    enableClassification: true,
    minFaceSize: 0.15, // Minimum 15% of image
  ),
);