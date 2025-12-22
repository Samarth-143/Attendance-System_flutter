import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'email_service.dart';
import 'database_service.dart';

class BackgroundEmailService {
  static Future<void> sendDailyEmail() async {
    try {
      debugPrint('📧 [AUTO-SEND] Background email task started at ${DateTime.now()}');
      
      // Get email configuration
      final prefs = await SharedPreferences.getInstance();
      final gmailEmail = prefs.getString('gmail_email') ?? '';
      final gmailPassword = prefs.getString('gmail_password') ?? '';
      final recipientEmail = prefs.getString('recipient_email') ?? '';
      final autoSendEnabled = prefs.getBool('auto_send_enabled') ?? false;
      
      debugPrint('📧 [AUTO-SEND] Gmail: $gmailEmail');
      debugPrint('📧 [AUTO-SEND] Auto-send enabled: $autoSendEnabled');
      
      if (!autoSendEnabled) {
        debugPrint('⏸️ [AUTO-SEND] Auto-send is disabled');
        return;
      }
      
      if (gmailEmail.isEmpty || gmailPassword.isEmpty || recipientEmail.isEmpty) {
        debugPrint('⚠️ [AUTO-SEND] Email configuration incomplete');
        return;
      }
      
      // Get today's attendance records
      final dbService = DatabaseService();
      await dbService.initialize();
      debugPrint('📧 [AUTO-SEND] Database initialized');
      
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      debugPrint('📧 [AUTO-SEND] Fetching records for date: $dateStr');
      
      final records = await dbService.getAttendanceRecords();
      final todayRecords = records.where((r) => r['date'] == dateStr).toList();
      
      debugPrint('📧 [AUTO-SEND] Found ${todayRecords.length} records for today');
      
      if (todayRecords.isEmpty) {
        debugPrint('ℹ️ [AUTO-SEND] No attendance records for today');
        return;
      }
      
      // Generate CSV
      List<List<dynamic>> rows = [];
      rows.add(['Daily Attendance Report - ${today.day}/${today.month}/${today.year}']);
      rows.add([]);
      rows.add(['Name', 'Role', 'Shift', 'In-Time', 'Out-Time']);
      
      for (var record in todayRecords) {
        rows.add([
          record['name'] ?? '',
          record['role'] ?? '',
          record['shift'] ?? 'Day',
          record['in_time'] ?? '',
          record['out_time'] ?? '',
        ]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      
      // Save CSV file
      Directory? directory;
      if (Platform.isAndroid) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      final filename = 'daily_attendance_${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}.csv';
      final path = '${directory.path}/$filename';
      final file = File(path);
      await file.writeAsString(csv);
      debugPrint('📧 [AUTO-SEND] CSV saved to: $path');
      
      // Send email
      final emailService = EmailService();
      debugPrint('📧 [AUTO-SEND] Sending email to: $recipientEmail');
      final success = await emailService.sendEmail(
        gmailEmail: gmailEmail,
        gmailPassword: gmailPassword,
        recipientEmail: recipientEmail,
        subject: 'Daily Attendance Report - ${today.day}/${today.month}/${today.year}',
        body: 'Please find the attached daily attendance report.\n\nTotal records: ${todayRecords.length}',
        csvPath: path,
      );
      
      if (success) {
        debugPrint('✅ [AUTO-SEND] Background email sent successfully at ${DateTime.now()}');
      } else {
        debugPrint('❌ [AUTO-SEND] Failed to send background email');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [AUTO-SEND] Error in background email task: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
}
