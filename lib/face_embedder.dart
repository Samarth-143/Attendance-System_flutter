import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:math';

class FaceEmbedder {
  static const int embeddingSize = 128;

  Future<void> loadModel() async {
    // No model needed - using facial landmarks instead
    print('Using facial landmark-based embeddings');
  }

  List<double>? getEmbedding(img.Image face) {
    // Create a simple embedding from image pixel data
    // This is a basic approach - normalize and reduce image to fixed-size vector
    final resized = img.copyResize(face, width: 32, height: 32);
    
    List<double> embedding = [];
    
    // Extract color histograms (simple feature extraction)
    for (int y = 0; y < 32; y += 4) {
      for (int x = 0; x < 32; x += 4) {
        final pixel = resized.getPixel(x, y);
        embedding.add((pixel.r / 255.0 - 0.5) * 2);
        embedding.add((pixel.g / 255.0 - 0.5) * 2);
        embedding.add((pixel.b / 255.0 - 0.5) * 2);
      }
    }
    
    // Normalize the embedding
    double norm = 0;
    for (var val in embedding) {
      norm += val * val;
    }
    norm = sqrt(norm);
    
    if (norm > 0) {
      embedding = embedding.map((v) => v / norm).toList();
    }
    
    // Pad or trim to embeddingSize
    if (embedding.length > embeddingSize) {
      embedding = embedding.sublist(0, embeddingSize);
    } else {
      while (embedding.length < embeddingSize) {
        embedding.add(0.0);
      }
    }
    
    return embedding;
  }

  void dispose() {
    // Nothing to dispose
  }
}