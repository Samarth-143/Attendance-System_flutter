import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import '../services/email_service.dart';

class EmailSettingsScreen extends StatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  State<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends State<EmailSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailService = EmailService();
  
  final _gmailEmailController = TextEditingController();
  final _gmailPasswordController = TextEditingController();
  final _recipientEmailController = TextEditingController();
  
  bool _autoSendEnabled = false;
  TimeOfDay _autoSendTime = const TimeOfDay(hour: 18, minute: 0);
  bool _obscurePassword = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = await _emailService.getEmailConfig();
    setState(() {
      _gmailEmailController.text = config['gmailEmail'];
      _gmailPasswordController.text = config['gmailPassword'];
      _recipientEmailController.text = config['recipientEmail'];
      _autoSendEnabled = config['autoSendEnabled'];
      
      final timeParts = config['autoSendTime'].split(':');
      _autoSendTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _emailService.saveEmailConfig(
          gmailEmail: _gmailEmailController.text.trim(),
          gmailPassword: _gmailPasswordController.text,
          recipientEmail: _recipientEmailController.text.trim(),
          autoSendEnabled: _autoSendEnabled,
          autoSendTime: '${_autoSendTime.hour.toString().padLeft(2, '0')}:${_autoSendTime.minute.toString().padLeft(2, '0')}',
        );
        
        // Schedule or cancel background task
        await Workmanager().cancelAll();
        
        if (_autoSendEnabled) {
          // Calculate initial delay to target time
          final now = DateTime.now();
          final targetTime = DateTime(
            now.year,
            now.month,
            now.day,
            _autoSendTime.hour,
            _autoSendTime.minute,
          );
          
          Duration initialDelay;
          if (targetTime.isAfter(now)) {
            initialDelay = targetTime.difference(now);
          } else {
            // If time has passed today, schedule for tomorrow
            final tomorrow = targetTime.add(const Duration(days: 1));
            initialDelay = tomorrow.difference(now);
          }
          
          // Register periodic task (runs daily)
          await Workmanager().registerPeriodicTask(
            'daily-email-task',
            'dailyEmailTask',
            frequency: const Duration(hours: 24),
            initialDelay: initialDelay,
            constraints: Constraints(
              networkType: NetworkType.connected,
            ),
          );
          
          print('✅ Background email scheduled for ${_autoSendTime.format(context)}');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_autoSendEnabled 
                ? 'Settings saved! Auto-send scheduled for ${_autoSendTime.format(context)}' 
                : 'Settings saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving settings: $e')),
          );
        }
      }
    }
  }

  Future<void> _triggerAutoSendNow() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Triggering background task...'),
          ],
        ),
      ),
    );

    try {
      // Trigger the task to run immediately for testing
      await Workmanager().registerOneOffTask(
        'test-email-task',
        'dailyEmailTask',
        initialDelay: const Duration(seconds: 5),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Background task triggered! Email will be sent in 5 seconds.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _autoSendTime,
    );
    if (picked != null) {
      setState(() {
        _autoSendTime = picked;
      });
    }
  }

  Future<void> _sendTestEmail() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final success = await _emailService.sendEmail(
        gmailEmail: _gmailEmailController.text.trim(),
        gmailPassword: _gmailPasswordController.text,
        recipientEmail: _recipientEmailController.text.trim(),
        subject: 'Test Email - Face Attendance App',
        body: 'This is a test email from Face Attendance App.\n\nIf you received this, your email configuration is working correctly!',
        csvPath: '', // Empty for test
      );

      Navigator.pop(context); // Close loading dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Test email sent successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✗ Failed to send test email. Check your Gmail App Password and internet connection.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'How to Get Gmail App Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Go to myaccount.google.com\n'
                      '2. Click Security → 2-Step Verification (Enable if not enabled)\n'
                      '3. Scroll down and click "App passwords"\n'
                      '4. Select "Mail" and "Other" device\n'
                      '5. Copy the 16-character password\n'
                      '6. Paste it below (without spaces)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gmail Configuration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'To use auto-email, you need a Gmail App Password.\nGo to: Google Account → Security → 2-Step Verification → App Passwords',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _gmailEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Your Gmail Address',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your Gmail address';
                        }
                        if (!value.contains('@gmail.com')) {
                          return 'Please enter a valid Gmail address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _gmailPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Gmail App Password',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your Gmail App Password';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recipient',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _recipientEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Send Reports To',
                        prefixIcon: Icon(Icons.send),
                        border: OutlineInputBorder(),
                        hintText: 'recipient@example.com',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter recipient email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Auto-Send Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Automatically send daily attendance report',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Enable Auto-Send'),
                      subtitle: const Text('Send report automatically every day'),
                      value: _autoSendEnabled,
                      onChanged: (value) {
                        setState(() {
                          _autoSendEnabled = value;
                        });
                      },
                    ),
                    if (_autoSendEnabled) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: const Text('Send Time'),
                        subtitle: Text(_autoSendTime.format(context)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _selectTime,
                      ),                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.play_arrow, color: Colors.orange),
                        title: const Text('Test Auto-Send Now'),
                        subtitle: const Text('Manually trigger background email'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _triggerAutoSendNow,
                      ),                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _sendTestEmail,
              icon: const Icon(Icons.send),
              label: const Text('Send Test Email'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _gmailEmailController.dispose();
    _gmailPasswordController.dispose();
    _recipientEmailController.dispose();
    super.dispose();
  }
}
