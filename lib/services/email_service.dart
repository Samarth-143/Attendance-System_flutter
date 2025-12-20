import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailService {
  static const String _keyGmailEmail = 'gmail_email';
  static const String _keyGmailPassword = 'gmail_password';
  static const String _keyRecipientEmail = 'recipient_email';
  static const String _keyAutoSendEnabled = 'auto_send_enabled';
  static const String _keyAutoSendTime = 'auto_send_time';

  Future<void> saveEmailConfig({
    required String gmailEmail,
    required String gmailPassword,
    required String recipientEmail,
    required bool autoSendEnabled,
    required String autoSendTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGmailEmail, gmailEmail);
    await prefs.setString(_keyGmailPassword, gmailPassword);
    await prefs.setString(_keyRecipientEmail, recipientEmail);
    await prefs.setBool(_keyAutoSendEnabled, autoSendEnabled);
    await prefs.setString(_keyAutoSendTime, autoSendTime);
  }

  Future<Map<String, dynamic>> getEmailConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'gmailEmail': prefs.getString(_keyGmailEmail) ?? '',
      'gmailPassword': prefs.getString(_keyGmailPassword) ?? '',
      'recipientEmail': prefs.getString(_keyRecipientEmail) ?? '',
      'autoSendEnabled': prefs.getBool(_keyAutoSendEnabled) ?? false,
      'autoSendTime': prefs.getString(_keyAutoSendTime) ?? '18:00',
    };
  }

  Future<bool> sendEmail({
    required String gmailEmail,
    required String gmailPassword,
    required String recipientEmail,
    required String subject,
    required String body,
    required String csvPath,
  }) async {
    try {
      // Configure Gmail SMTP
      final smtpServer = gmail(gmailEmail, gmailPassword);

      // Create the email message
      final message = Message()
        ..from = Address(gmailEmail)
        ..recipients.add(recipientEmail)
        ..subject = subject
        ..text = body
        ..attachments = [FileAttachment(File(csvPath))];

      // Send the email
      final sendReport = await send(message, smtpServer);
      print('Email sent: ${sendReport.toString()}');
      return true;
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  Future<bool> isConfigured() async {
    final config = await getEmailConfig();
    return config['gmailEmail'].toString().isNotEmpty &&
        config['gmailPassword'].toString().isNotEmpty &&
        config['recipientEmail'].toString().isNotEmpty;
  }
}
