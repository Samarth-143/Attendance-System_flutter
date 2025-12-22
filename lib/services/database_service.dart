import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:math';

class DatabaseService {
  Database? _database;
  static const double similarityThreshold = 0.82; // Increased for better accuracy

  Future<void> initialize() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'face_attendance.db');

    _database = await openDatabase(
      path,
      version: 7, // Updated to add leave_type column
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE faces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            contractor TEXT,
            shift TEXT NOT NULL,
            embedding TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            date TEXT NOT NULL,
            in_time TEXT,
            out_time TEXT,
            leave_type TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE faces ADD COLUMN role TEXT NOT NULL DEFAULT "Staff"');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE faces ADD COLUMN contractor TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE faces ADD COLUMN shift TEXT NOT NULL DEFAULT "Day"');
        }
        if (oldVersion < 5) {
          // Clear old face embeddings - they're incompatible with new 256D embeddings
          await db.execute('DELETE FROM faces');
          print('Cleared old face data - please re-enroll all faces with improved accuracy system');
        }
        if (oldVersion < 6) {
          // Migrate attendance table to new schema
          await db.execute('ALTER TABLE attendance ADD COLUMN date TEXT');
          await db.execute('ALTER TABLE attendance ADD COLUMN in_time TEXT');
          await db.execute('ALTER TABLE attendance ADD COLUMN out_time TEXT');
          // Update existing records
          final records = await db.query('attendance');
          for (var record in records) {
            final timestamp = DateTime.parse(record['timestamp'] as String);
            final date = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
            await db.update(
              'attendance',
              {'date': date, 'in_time': record['timestamp']},
              where: 'id = ?',
              whereArgs: [record['id']],
            );
          }
        }
        if (oldVersion < 7) {
          // Add leave_type column for SL/CL marking
          await db.execute('ALTER TABLE attendance ADD COLUMN leave_type TEXT');
        }
      },
    );
  }

  Future<void> saveFace(String name, String role, List<double> embedding, {String? contractor, required String shift}) async {
    print('DEBUG: Saving face - Name: $name, Role: $role, Shift: $shift, Embedding length: ${embedding.length}');
    print('DEBUG: First 5 embedding values: ${embedding.take(5).toList()}');
    
    await _database!.insert('faces', {
      'name': name,
      'role': role,
      'contractor': contractor,
      'shift': shift,
      'embedding': embedding.join(','),
      'created_at': DateTime.now().toIso8601String(),
    });
    
    // Verify it was saved
    final faces = await _database!.query('faces', where: 'name = ?', whereArgs: [name]);
    print('DEBUG: Face saved successfully. Total faces with this name: ${faces.length}');
  }

  Future<Map<String, dynamic>?> findMatch(List<double> embedding) async {
    final faces = await _database!.query('faces');
    
    print('DEBUG: Total enrolled faces in database: ${faces.length}');
    
    if (faces.isEmpty) {
      print('DEBUG: No faces found in database');
      return null;
    }

    String? matchedName;
    String? matchedRole;
    String? matchedShift;
    double maxSimilarity = 0;

    for (final face in faces) {
      final embeddingStr = face['embedding'] as String?;
      if (embeddingStr == null || embeddingStr.isEmpty) {
        print('DEBUG: Empty embedding for face ${face['name']}');
        continue;
      }
      
      final storedEmbedding = embeddingStr
          .split(',')
          .map((e) => double.parse(e))
          .toList();
      
      print('DEBUG: Comparing with ${face['name']}, stored embedding length: ${storedEmbedding.length}, input embedding length: ${embedding.length}');
      
      final similarity = _cosineSimilarity(embedding, storedEmbedding);
      
      print('DEBUG: Similarity with ${face['name']}: $similarity (threshold: $similarityThreshold)');
      
      if (similarity > maxSimilarity && similarity > similarityThreshold) {
        maxSimilarity = similarity;
        matchedName = face['name'] as String?;
        matchedRole = face['role'] as String?;
        matchedShift = face['shift'] as String? ?? 'Day';
      }
    }

    if (matchedName != null && matchedRole != null) {
      print('DEBUG: Match found! Name: $matchedName, Similarity: $maxSimilarity');
      return {
        'name': matchedName, 
        'role': matchedRole, 
        'shift': matchedShift ?? 'Day',
        'confidence': maxSimilarity, // Add confidence score
        'accuracy': (maxSimilarity * 100).toStringAsFixed(1), // Percentage
      };
    }
    print('DEBUG: No match found. Max similarity: $maxSimilarity');
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

  Future<String> recordAttendance(String name, String role) async {
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final currentHour = now.hour;
    
    // Get person's shift from faces table
    final face = await _database!.query(
      'faces',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    
    if (face.isEmpty) {
      return 'ERROR';
    }
    
    final shift = face.first['shift'] as String? ?? 'Day';
    
    // Determine date and IN/OUT based on shift and time
    String attendanceDate;
    bool isInTime;
    
    if (shift == 'Day') {
      // Day shift: Simple - same calendar day
      attendanceDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      // Before 4 PM (16:00) = IN, After 4 PM = OUT
      isInTime = currentHour < 16;
    } else {
      // Night shift: Complex - spans two calendar days
      // Logic: 
      // - 2 PM to midnight (14:00-23:59) = IN time for current date
      // - Midnight to 2 PM (00:00-13:59) = OUT time for previous date
      
      if (currentHour >= 14) {
        // Afternoon/Evening (2 PM onwards) - This is IN time for today
        attendanceDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        isInTime = true;
      } else {
        // Morning (before 2 PM) - This is OUT time for yesterday's shift
        final yesterday = now.subtract(const Duration(days: 1));
        attendanceDate = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
        isInTime = false;
      }
    }
    
    // Check if there's already an attendance record for the determined date
    final existing = await _database!.query(
      'attendance',
      where: 'name = ? AND date = ?',
      whereArgs: [name, attendanceDate],
    );
    
    if (existing.isEmpty) {
      // No record for this date - create new one
      if (isInTime) {
        await _database!.insert('attendance', {
          'name': name,
          'date': attendanceDate,
          'in_time': timestamp,
          'out_time': null,
          'timestamp': timestamp,
        });
        return 'IN';
      } else {
        await _database!.insert('attendance', {
          'name': name,
          'date': attendanceDate,
          'in_time': null,
          'out_time': timestamp,
          'timestamp': timestamp,
        });
        return 'OUT';
      }
    } else {
      // Record exists for this date
      final record = existing.first;
      
      if (isInTime) {
        // Trying to mark IN time
        if (record['in_time'] == null) {
          await _database!.update(
            'attendance',
            {'in_time': timestamp},
            where: 'id = ?',
            whereArgs: [record['id']],
          );
          return 'IN';
        } else {
          return 'IN_ALREADY_MARKED';
        }
      } else {
        // Trying to mark OUT time
        if (record['out_time'] == null) {
          await _database!.update(
            'attendance',
            {'out_time': timestamp},
            where: 'id = ?',
            whereArgs: [record['id']],
          );
          return 'OUT';
        } else {
          return 'OUT_ALREADY_MARKED';
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAllEnrolledFaces() async {
    return await _database!.query('faces', orderBy: 'created_at DESC');
  }

  Future<void> deleteFace(int id) async {
    // Get the name of the person being deleted
    final face = await _database!.query('faces', where: 'id = ?', whereArgs: [id]);
    if (face.isNotEmpty) {
      final name = face.first['name'] as String?;
      if (name != null) {
        // Delete all attendance records for this person
        await _database!.delete('attendance', where: 'name = ?', whereArgs: [name]);
      }
    }
    // Delete the face record
    await _database!.delete('faces', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getEnrolledCount() async {
    final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM faces');
    return (result.first['count'] as int?) ?? 0;
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

  Future<void> markLeave(String name, String date, String leaveType) async {
    // leaveType: 'SL' (Sick Leave) or 'CL' (Casual Leave)
    // Check if attendance record exists for this date
    final existing = await _database!.query(
      'attendance',
      where: 'name = ? AND date = ?',
      whereArgs: [name, date],
    );
    
    if (existing.isEmpty) {
      // No record exists, create one with leave type
      await _database!.insert('attendance', {
        'name': name,
        'date': date,
        'in_time': null,
        'out_time': null,
        'leave_type': leaveType,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } else {
      // Update existing record with leave type
      await _database!.update(
        'attendance',
        {'leave_type': leaveType},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> clearLeave(String name, String date) async {
    // Remove leave marking (revert to normal absent)
    final existing = await _database!.query(
      'attendance',
      where: 'name = ? AND date = ?',
      whereArgs: [name, date],
    );
    
    if (existing.isNotEmpty) {
      final record = existing.first;
      // If no in_time or out_time, delete the record entirely
      if (record['in_time'] == null && record['out_time'] == null) {
        await _database!.delete(
          'attendance',
          where: 'id = ?',
          whereArgs: [record['id']],
        );
      } else {
        // Just clear the leave_type
        await _database!.update(
          'attendance',
          {'leave_type': null},
          where: 'id = ?',
          whereArgs: [record['id']],
        );
      }
    }
  }

  Future<String?> getLeaveType(String name, String date) async {
    final records = await _database!.query(
      'attendance',
      where: 'name = ? AND date = ?',
      whereArgs: [name, date],
      limit: 1,
    );
    
    if (records.isNotEmpty) {
      return records.first['leave_type'] as String?;
    }
    return null;
  }

  Future<void> deleteAttendanceRecord(String name, String date) async {
    await _database!.delete(
      'attendance',
      where: 'name = ? AND date = ?',
      whereArgs: [name, date],
    );
  }

  Future<void> deleteAllAttendance() async {
    await _database!.delete('attendance');
  }

  void dispose() {
    _database?.close();
  }
}
