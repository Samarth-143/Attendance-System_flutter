// ML Kit Face Detection wrapper (skeleton)

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

final FaceDetector faceDetector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableLandmarks: true,
  ),
);