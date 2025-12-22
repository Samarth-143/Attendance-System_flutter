import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

class FaceEmbedder {
  static const int embeddingSize = 192; // MobileFaceNet outputs 192D embeddings
  Interpreter? _interpreter;
  bool _useDeepLearning = false;
  
  // Public getter to check if deep learning is active
  bool get isUsingDeepLearning => _useDeepLearning;

  Future<void> loadModel() async {
    try {
      print('Attempting to load MobileFaceNet TFLite model...');
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      _useDeepLearning = true;
      print('✓ MobileFaceNet model loaded successfully! Using deep learning embeddings.');
    } catch (e) {
      print('⚠ Could not load TFLite model: $e');
      print('Falling back to enhanced feature extraction method');
      _useDeepLearning = false;
    }
  }

  List<double>? getEmbedding(img.Image face) {
    if (_useDeepLearning && _interpreter != null) {
      return _getDeepLearningEmbedding(face);
    } else {
      return _getEnhancedEmbedding(face);
    }
  }

  List<double>? _getDeepLearningEmbedding(img.Image face) {
    try {
      // MobileFaceNet expects 112x112x3 input
      final resized = img.copyResize(face, width: 112, height: 112);
      
      // Prepare input tensor [1, 112, 112, 3]
      var input = List.generate(1, (_) => 
        List.generate(112, (y) =>
          List.generate(112, (x) {
            final pixel = resized.getPixel(x, y);
            return [
              (pixel.r - 127.5) / 128.0,  // Normalize to [-1, 1]
              (pixel.g - 127.5) / 128.0,
              (pixel.b - 127.5) / 128.0,
            ];
          })
        )
      );
      
      // Prepare output tensor [1, 192]
      var output = List.filled(1, List.filled(192, 0.0));
      
      // Run inference
      _interpreter!.run(input, output);
      
      // Normalize the embedding
      List<double> embedding = output[0];
      double norm = 0;
      for (var val in embedding) {
        norm += val * val;
      }
      norm = sqrt(norm);
      
      if (norm > 0) {
        embedding = embedding.map((v) => v / norm).toList();
      }
      
      print('✓ Generated 192D deep learning embedding');
      return embedding;
    } catch (e) {
      print('Error in deep learning embedding: $e');
      return _getEnhancedEmbedding(face);
    }
  }

  List<double>? _getEnhancedEmbedding(img.Image face) {
    // Fallback: Enhanced feature-based embedding
    List<double> embedding = [];
    
    // 1. Extract features at multiple scales (more scales = better accuracy)
    final scales = [24, 32, 48, 64, 80];
    for (var size in scales) {
      final resized = img.copyResize(face, width: size, height: size);
      embedding.addAll(_extractLocalFeatures(resized, size));
    }
    
    // 2. Add global texture features
    embedding.addAll(_extractTextureFeatures(face));
    
    // 3. Normalize the embedding
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

  // Extract local features from small patches
  List<double> _extractLocalFeatures(img.Image face, int size) {
    List<double> features = [];
    final patchSize = size ~/ 4;
    
    // Divide face into regions (eyes, nose, mouth areas)
    for (int py = 0; py < 4; py++) {
      for (int px = 0; px < 4; px++) {
        double sumR = 0, sumG = 0, sumB = 0;
        double sumR2 = 0, sumG2 = 0, sumB2 = 0;
        int count = 0;
        
        // Calculate mean and variance for each patch
        for (int y = py * patchSize; y < (py + 1) * patchSize && y < size; y++) {
          for (int x = px * patchSize; x < (px + 1) * patchSize && x < size; x++) {
            final pixel = face.getPixel(x, y);
            final r = pixel.r / 255.0;
            final g = pixel.g / 255.0;
            final b = pixel.b / 255.0;
            
            sumR += r; sumG += g; sumB += b;
            sumR2 += r * r; sumG2 += g * g; sumB2 += b * b;
            count++;
          }
        }
        
        if (count > 0) {
          // Mean values
          features.add(sumR / count - 0.5);
          features.add(sumG / count - 0.5);
          features.add(sumB / count - 0.5);
          
          // Standard deviation (texture info)
          features.add(sqrt((sumR2 / count) - pow(sumR / count, 2)));
        }
      }
    }
    
    return features;
  }

  // Extract texture features using gradient-like operations
  List<double> _extractTextureFeatures(img.Image face) {
    List<double> features = [];
    final resized = img.copyResize(face, width: 64, height: 64);
    
    // Horizontal and vertical gradients for texture
    for (int y = 1; y < 63; y += 4) {
      for (int x = 1; x < 63; x += 4) {
        final center = resized.getPixel(x, y);
        final right = resized.getPixel(x + 1, y);
        final down = resized.getPixel(x, y + 1);
        
        // Gradient approximation
        final gradX = (right.r - center.r) / 255.0;
        final gradY = (down.r - center.r) / 255.0;
        
        features.add(gradX);
        features.add(gradY);
      }
    }
    
    return features;
  }

  void dispose() {
    _interpreter?.close();
  }
}