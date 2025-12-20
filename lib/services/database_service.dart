import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:math';

class DatabaseService {
  Database? _database;
  static const double similarityThreshold = 0.7;

  Future<void> initialize() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'face_attendance.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE faces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            embedding TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add role column to existing faces table
          await db.execute('ALTER TABLE faces ADD COLUMN role TEXT NOT NULL DEFAULT "Staff"');
        }
      },
    );
  }

  Future<void> saveFace(String name, String role, List<double> embedding) async {
    await _database!.insert('faces', {
      'name': name,
      'role': role,
      'embedding': embedding.join(','),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, String>?> findMatch(List<double> embedding) async {
    final faces = await _database!.query('faces');
    
    if (faces.isEmpty) {
      return null;
    }

    String? matchedName;
    String? matchedRole;
    double maxSimilarity = 0;

    for (final face in faces) {
      final storedEmbedding = (face['embedding'] as String)
          .split(',')
          .map((e) => double.parse(e))
          .toList();
      
      final similarity = _cosineSimilarity(embedding, storedEmbedding);
      
      if (similarity > maxSimilarity && similarity > similarityThreshold) {
        maxSimilarity = similarity;
        matchedName = face['name'] as String;
        matchedRole = face['role'] as String;
      }
    }

    if (matchedName != null && matchedRole != null) {
      return {'name': matchedName, 'role': matchedRole};
    }
    return null;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0;
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  Future<void> recordAttendance(String name, String role) async {
    await _database!.insert('attendance', {
      'name': name,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    // Store role in a separate query if needed
    // For now, we'll fetch it from faces table when displaying attendance
  }

  Future<List<Map<String, dynamic>>> getAllEnrolledFaces() async {
    return await _database!.query('faces', orderBy: 'created_at DESC');
  }

  Future<void> deleteFace(int id) async {
    // Get the name of the person being deleted
    final face = await _database!.query('faces', where: 'id = ?', whereArgs: [id]);
    if (face.isNotEmpty) {
      final name = face.first['name'] as String;
      // Delete all attendance records for this person
      await _database!.delete('attendance', where: 'name = ?', whereArgs: [name]);
    }
    // Delete the face record
    await _database!.delete('faces', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getEnrolledCount() async {
    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM faces');
    return result.first['count'] as int;
  }

  Future<List<Map<String, dynamic>>> getAttendanceRecords() async {
    return await _database!.query('attendance', orderBy: 'timestamp DESC');
  }

  Future<void> deleteAttendanceForDate(String date) async {
    // Delete all attendance records for a specific date
    // date format: YYYY-MM-DD
    final startOfDay = '$date 00:00:00';
    final endOfDay = '$date 23:59:59';
    
    await _database!.delete(
      'attendance',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startOfDay, endOfDay],
    );
  }

  void dispose() {
    _database?.close();
  }
}
