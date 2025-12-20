import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import '../services/database_service.dart';
import '../services/email_service.dart';

class AttendanceTableScreen extends StatefulWidget {
  const AttendanceTableScreen({super.key});

  @override
  State<AttendanceTableScreen> createState() => _AttendanceTableScreenState();
}

class _AttendanceTableScreenState extends State<AttendanceTableScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  final EmailService _emailService = EmailService();
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupedRecords = {};
  Map<String, String?> contractorMap = {};
  bool _isLoading = true;
  
  // Monthly attendance data
  Map<String, Map<int, bool>> _monthlyAttendanceData = {};
  List<Map<String, dynamic>> _allPeople = [];
  DateTime _selectedMonth = DateTime.now();
  int _daysInMonth = 0;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadAttendance();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    await _databaseService.initialize();
    
    // Get all faces to map names to roles
    Map<String, String> roleMap = {};
    List<Map<String, dynamic>> allPeople = [];
    final faces = await _databaseService.getAllEnrolledFaces();
    for (var face in faces) {
      final name = face['name'] as String;
      final role = face['role'] as String;
      final contractor = face['contractor'] as String?;
      roleMap[name] = role;
      contractorMap[name] = contractor;
      allPeople.add({'name': name, 'role': role, 'contractor': contractor});
    }
    
    // Get attendance records
    final records = await _databaseService.getAttendanceRecords();
    
    // Get all unique dates from attendance records
    Set<String> allDates = {};
    for (var record in records) {
      final timestamp = DateTime.parse(record['timestamp'] as String);
      final dateKey = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      allDates.add(dateKey);
    }
    
    // Group by date, then role, then person
    Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};
    
    // Initialize all dates with all enrolled people
    for (var dateKey in allDates) {
      grouped[dateKey] = {'Staff': [], 'Worker': []};
      
      // Add all enrolled people to this date
      for (var person in allPeople) {
        grouped[dateKey]![person['role']]!.add({
          'name': person['name'],
          'contractor': person['contractor'],
          'inTime': null,
          'outTime': null,
          'timestamps': <DateTime>[],
        });
      }
    }
    
    // Now fill in attendance data
    for (var record in records) {
      final name = record['name'] as String;
      final role = roleMap[name] ?? 'Staff';
      final timestamp = DateTime.parse(record['timestamp'] as String);
      final dateKey = '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
      
      if (grouped.containsKey(dateKey) && grouped[dateKey]!.containsKey(role)) {
        // Find the person entry
        var personEntry = grouped[dateKey]![role]!.firstWhere(
          (entry) => entry['name'] == name,
          orElse: () => {'name': name, 'contractor': contractorMap[name], 'inTime': null, 'outTime': null, 'timestamps': <DateTime>[]}
        );
        
        personEntry['timestamps'].add(timestamp);
      }
    }
    
    // Process timestamps to determine in-time and out-time
    grouped.forEach((date, roles) {
      roles.forEach((role, people) {
        for (var person in people) {
          List<DateTime> timestamps = person['timestamps'];
          if (timestamps.isNotEmpty) {
            timestamps.sort();
            
            for (var time in timestamps) {
              if (time.hour < 16) {
                if (person['inTime'] == null || time.isBefore(person['inTime'])) {
                  person['inTime'] = time;
                }
              } else {
                if (person['outTime'] == null || time.isAfter(person['outTime'])) {
                  person['outTime'] = time;
                }
              }
            }
          }
          person.remove('timestamps');
        }
        
        // Sort people by name
        people.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      });
    });
    
    setState(() {
      _groupedRecords = grouped;
      _allPeople = allPeople;
      _isLoading = false;
    });
    
    // Also load monthly attendance
    _loadMonthlyAttendance();
  }

  Future<void> _loadMonthlyAttendance() async {
    // Calculate days in selected month
    _daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;

    // Initialize attendance map
    Map<String, Map<int, bool>> attendanceMap = {};
    for (var person in _allPeople) {
      attendanceMap[person['name']] = {};
      for (int day = 1; day <= _daysInMonth; day++) {
        attendanceMap[person['name']]![day] = false;
      }
    }

    // Get all attendance records for the selected month
    final records = await _databaseService.getAttendanceRecords();
    
    for (var record in records) {
      final timestamp = DateTime.parse(record['timestamp'] as String);
      if (timestamp.year == _selectedMonth.year && 
          timestamp.month == _selectedMonth.month) {
        final name = record['name'] as String;
        final day = timestamp.day;
        
        if (attendanceMap.containsKey(name)) {
          attendanceMap[name]![day] = true;
        }
      }
    }

    setState(() {
      _monthlyAttendanceData = attendanceMap;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset, 1);
    });
    _loadMonthlyAttendance();
  }

  String _getMonthYearText() {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[_selectedMonth.month - 1]}, ${_selectedMonth.year}';
  }

  int _getTotalPresent(String personName) {
    int total = 0;
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final maxDay = isCurrentMonth ? now.day : _daysInMonth;
    
    _monthlyAttendanceData[personName]?.forEach((day, present) {
      if (day <= maxDay && present) total++;
    });
    return total;
  }
  
  int _getTotalAbsent(String personName) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final maxDay = isCurrentMonth ? now.day : _daysInMonth;
    final totalPresent = _getTotalPresent(personName);
    return maxDay - totalPresent;
  }
  
  String _getAttendancePercentage(String personName) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final maxDay = isCurrentMonth ? now.day : _daysInMonth;
    
    if (maxDay == 0) return '0%';
    
    final totalPresent = _getTotalPresent(personName);
    final percentage = (totalPresent / maxDay * 100).toStringAsFixed(1);
    return '$percentage%';
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '-';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(String dateKey) {
    final parts = dateKey.split('-');
    final date = DateTime.parse(dateKey);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${parts[2]}, ${parts[0]}';
  }

  Future<void> _deleteAttendanceForDate(String dateKey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attendance'),
        content: Text('Are you sure you want to delete all attendance records for ${_formatDate(dateKey)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _databaseService.deleteAttendanceForDate(dateKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted attendance for ${_formatDate(dateKey)}')),
      );
      await _loadAttendance();
    }
  }

  Future<void> _exportToCSV() async {
    try {
      // Request storage permission for Android
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            // Try manageExternalStorage for Android 11+
            status = await Permission.manageExternalStorage.request();
            if (!status.isGranted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission denied')),
              );
              return;
            }
          }
        }
      }

      List<List<dynamic>> rows = [];
      
      // Sort dates
      final sortedDates = _groupedRecords.keys.toList()..sort((a, b) => b.compareTo(a));
      
      // Add data grouped by date
      for (var date in sortedDates) {
        final roles = _groupedRecords[date]!;
        
        // Add date as header row
        rows.add([_formatDate(date)]);
        
        // Add column headers
        rows.add(['Name', 'Role', 'Contractor', 'In-Time', 'Out-Time']);
        
        // Add Staff records
        for (var person in roles['Staff']!) {
          final contractor = contractorMap[person['name']];
          rows.add([
            person['name'],
            'Staff',
            contractor ?? '',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        
        // Add Worker records
        for (var person in roles['Worker']!) {
          final contractor = contractorMap[person['name']];
          rows.add([
            person['name'],
            'Worker',
            contractor ?? '',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        
        // Add empty row between dates
        rows.add([]);
      }
      
      // Convert to CSV
      String csv = const ListToCsvConverter().convert(rows);
      
      // Get Downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      if (directory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access storage')),
        );
        return;
      }
      
      // Create filename with timestamp
      final timestamp = DateTime.now();
      final filename = 'attendance_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}.csv';
      final path = '${directory.path}/$filename';
      final file = File(path);
      
      // Write file
      await file.writeAsString(csv);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to: $path'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting CSV: $e')),
      );
    }
  }

  Future<void> _exportMonthlyToCSV() async {
    try {
      // Request storage permission for Android
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            status = await Permission.manageExternalStorage.request();
            if (!status.isGranted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission denied')),
              );
              return;
            }
          }
        }
      }

      List<List<dynamic>> rows = [];
      
      // Add month/year as first row
      rows.add([_getMonthYearText()]);
      rows.add([]);
      
      // Add header
      List<dynamic> header = ['Person Name', 'Role', 'Contractor'];
      for (int day = 1; day <= _daysInMonth; day++) {
        header.add('$day');
      }
      header.add('Total P');
      header.add('Total A');
      header.add('Attendance %');
      rows.add(header);
      
      // Add data for each person
      final now = DateTime.now();
      final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
      
      for (var person in _allPeople) {
        final name = person['name'] as String;
        final role = person['role'] as String;
        final contractor = person['contractor'] as String?;
        final totalPresent = _getTotalPresent(name);
        final totalAbsent = _getTotalAbsent(name);
        final attendancePercentage = _getAttendancePercentage(name);
        
        List<dynamic> row = [name, role, contractor ?? ''];
        for (int day = 1; day <= _daysInMonth; day++) {
          final isFutureDate = isCurrentMonth && day > now.day;
          final hasAttendance = _monthlyAttendanceData[name]?[day] ?? false;
          row.add(isFutureDate ? '' : (hasAttendance ? 'P' : 'A'));
        }
        row.add(totalPresent);
        row.add(totalAbsent);
        row.add(attendancePercentage);
        rows.add(row);
      }
      
      // Convert to CSV
      String csv = const ListToCsvConverter().convert(rows);
      
      // Get Downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      if (directory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access storage')),
        );
        return;
      }
      
      // Create filename with month and year
      final filename = 'monthly_attendance_${_selectedMonth.year}_${_selectedMonth.month.toString().padLeft(2, '0')}.csv';
      final path = '${directory.path}/$filename';
      final file = File(path);
      
      // Write file
      await file.writeAsString(csv);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('CSV saved to: $path'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting CSV: $e')),
      );
    }
  }

  Future<void> _emailDailyAttendance() async {
    try {
      // Generate CSV content
      List<List<dynamic>> rows = [];
      
      final sortedDates = _groupedRecords.keys.toList()..sort((a, b) => b.compareTo(a));
      
      // Add data grouped by date
      for (var date in sortedDates) {
        final roles = _groupedRecords[date]!;
        
        // Add date as header row
        rows.add([_formatDate(date)]);
        
        // Add column headers
        rows.add(['Name', 'Role', 'In-Time', 'Out-Time']);
        
        for (var person in roles['Staff']!) {
          rows.add([
            person['name'],
            'Staff',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        
        for (var person in roles['Worker']!) {
          rows.add([
            person['name'],
            'Worker',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        
        // Add empty row between dates
        rows.add([]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      
      // Save to Downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      if (directory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access storage')),
        );
        return;
      }
      
      final timestamp = DateTime.now();
      final filename = 'daily_attendance_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour}${timestamp.minute}.csv';
      final path = '${directory.path}/$filename';
      final file = File(path);
      await file.writeAsString(csv);
      
      // Prepare email
      final Email email = Email(
        subject: 'Daily Attendance Report - ${timestamp.day}/${timestamp.month}/${timestamp.year}',
        body: 'Please find the attached daily attendance report.\n\nTotal records: ${rows.length - 1}',
        attachmentPaths: [path],
        isHTML: false,
      );
      
      await FlutterEmailSender.send(email);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email opened. CSV saved to: $filename')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e\nPlease check if an email app is installed.'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _emailMonthlyAttendance() async {
    try {
      // Generate CSV content
      List<List<dynamic>> rows = [];
      
      // Add month/year as first row
      rows.add([_getMonthYearText()]);
      rows.add([]);
      
      // Add month/year as first row
      rows.add([_getMonthYearText()]);
      rows.add([]);
      
      List<dynamic> header = ['Person Name', 'Role'];
      for (int day = 1; day <= _daysInMonth; day++) {
        header.add('$day');
      }
      header.add('Total P');
      header.add('Total A');
      rows.add(header);
      
      for (var person in _allPeople) {
        final name = person['name'] as String;
        final role = person['role'] as String;
        final totalPresent = _getTotalPresent(name);
        final totalAbsent = _daysInMonth - totalPresent;
        
        List<dynamic> row = [name, role];
        for (int day = 1; day <= _daysInMonth; day++) {
          final hasAttendance = _monthlyAttendanceData[name]?[day] ?? false;
          row.add(hasAttendance ? 'P' : 'A');
        }
        row.add(totalPresent);
        row.add(totalAbsent);
        rows.add(row);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      
      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final filename = 'monthly_attendance_${_selectedMonth.year}_${_selectedMonth.month.toString().padLeft(2, '0')}.csv';
      final path = '${directory.path}/$filename';
      final file = File(path);
      await file.writeAsString(csv);
      
      // Prepare email
      final Email email = Email(
        subject: 'Monthly Attendance Report - ${_getMonthYearText()}',
        body: 'Please find the attached monthly attendance report.\n\nTotal employees: ${_allPeople.length}\nDays in month: $_daysInMonth',
        attachmentPaths: [path],
        isHTML: false,
      );
      
      await FlutterEmailSender.send(email);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email client opened')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending email: $e')),
      );
    }
  }

  Future<void> _autoSendDailyEmail() async {
    try {
      // Check if email is configured
      final isConfigured = await _emailService.isConfigured();
      if (!isConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not configured. Please go to Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Get email config
      final config = await _emailService.getEmailConfig();
      
      // Generate CSV
      List<List<dynamic>> rows = [];
      
      final sortedDates = _groupedRecords.keys.toList()..sort((a, b) => b.compareTo(a));
      
      for (var date in sortedDates) {
        final roles = _groupedRecords[date]!;
        rows.add([_formatDate(date)]);
        rows.add(['Name', 'Role', 'In-Time', 'Out-Time']);
        
        for (var person in roles['Staff']!) {
          rows.add([
            person['name'],
            'Staff',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        
        for (var person in roles['Worker']!) {
          rows.add([
            person['name'],
            'Worker',
            _formatTime(person['inTime']),
            _formatTime(person['outTime']),
          ]);
        }
        rows.add([]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      
      // Save to file
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      final timestamp = DateTime.now();
      final filename = 'daily_attendance_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}.csv';
      final path = '${directory!.path}/$filename';
      final file = File(path);
      await file.writeAsString(csv);
      
      // Send email using Gmail SMTP
      final success = await _emailService.sendEmail(
        gmailEmail: config['gmailEmail'],
        gmailPassword: config['gmailPassword'],
        recipientEmail: config['recipientEmail'],
        subject: 'Daily Attendance Report - ${timestamp.day}/${timestamp.month}/${timestamp.year}',
        body: 'Please find the attached daily attendance report.\n\nTotal records: ${rows.length}',
        csvPath: path,
      );
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send email. Check your settings.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildRoleTable(String role, List<Map<String, dynamic>> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Icon(
                role == 'Staff' ? Icons.work : Icons.construction,
                size: 20,
                color: role == 'Staff' ? Colors.blue[700] : Colors.green[700],
              ),
              const SizedBox(width: 8),
              Text(
                role,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: role == 'Staff' ? Colors.blue[700] : Colors.green[700],
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              role == 'Staff' ? Colors.blue[50] : Colors.green[50]
            ),
            border: TableBorder.all(color: Colors.grey[300]!),
            columnSpacing: 40,
            columns: const [
              DataColumn(
                label: Text(
                  'Name',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Contractor',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'In-Time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Out-Time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows: people.map((person) {
              return DataRow(cells: [
                DataCell(Text(person['name'])),
                DataCell(Text(person['contractor'] ?? '-')),
                DataCell(
                  Text(
                    _formatTime(person['inTime']),
                    style: TextStyle(
                      color: person['inTime'] != null
                          ? Colors.green[700]
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    _formatTime(person['outTime']),
                    style: TextStyle(
                      color: person['outTime'] != null
                          ? Colors.orange[700]
                          : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedDates = _groupedRecords.keys.toList()..sort((a, b) => b.compareTo(a));
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Records'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Daily Records'),
            Tab(text: 'Monthly View'),
          ],
        ),
        actions: [
          if (_tabController.index == 0 && _groupedRecords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _autoSendDailyEmail,
              tooltip: 'Auto-Send Email',
            ),
          if (_tabController.index == 0 && _groupedRecords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.email),
              onPressed: _emailDailyAttendance,
              tooltip: 'Manual Email (Open Client)',
            ),
          if (_tabController.index == 0 && _groupedRecords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _exportToCSV,
              tooltip: 'Download Daily CSV',
            ),
          if (_tabController.index == 1 && _allPeople.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.email),
              onPressed: _emailMonthlyAttendance,
              tooltip: 'Email Monthly Report',
            ),
          if (_tabController.index == 1 && _allPeople.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _exportMonthlyToCSV,
              tooltip: 'Download Monthly CSV',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _tabController.index == 0 ? _loadAttendance : _loadMonthlyAttendance,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Daily Records Tab
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _groupedRecords.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No attendance records yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        final date = sortedDates[index];
                        final roles = _groupedRecords[date]!;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 24.0),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo[700],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.calendar_today,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDate(date),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteAttendanceForDate(date),
                                      tooltip: 'Delete this day',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildRoleTable('Staff', roles['Staff']!),
                                _buildRoleTable('Worker', roles['Worker']!),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          // Monthly View Tab
          Column(
            children: [
              // Month selector
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.indigo[700],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: () => _changeMonth(-1),
                    ),
                    Text(
                      _getMonthYearText(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
              ),
              // Monthly attendance table
              Expanded(
                child: _allPeople.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No enrolled people yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(Colors.blue[50]),
                            border: TableBorder.all(color: Colors.grey[300]!),
                            columnSpacing: 20,
                            dataRowMinHeight: 40,
                            dataRowMaxHeight: 40,
                            columns: [
                              const DataColumn(
                                label: Text(
                                  'Person Name',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const DataColumn(
                                label: Text(
                                  'Role',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const DataColumn(
                                label: Text(
                                  'Contractor',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              // Day columns
                              ...List.generate(_daysInMonth, (index) {
                                return DataColumn(
                                  label: SizedBox(
                                    width: 25,
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const DataColumn(
                                label: Text(
                                  'Total P',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const DataColumn(
                                label: Text(
                                  'Total A',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const DataColumn(
                                label: Text(
                                  'Attendance %',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            rows: _allPeople.map((person) {
                              final name = person['name'] as String;
                              final role = person['role'] as String;
                              final contractor = person['contractor'] as String?;
                              final totalPresent = _getTotalPresent(name);
                              final totalAbsent = _getTotalAbsent(name);
                              final attendancePercentage = _getAttendancePercentage(name);
                              final now = DateTime.now();
                              final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
                              
                              return DataRow(
                                cells: [
                                  DataCell(Text(name)),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: role == 'Staff'
                                            ? Colors.blue[100]
                                            : Colors.green[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          color: role == 'Staff'
                                              ? Colors.blue[900]
                                              : Colors.green[900],
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(contractor ?? '-')),
                                  // Day cells
                                  ...List.generate(_daysInMonth, (index) {
                                    final day = index + 1;
                                    final isFutureDate = isCurrentMonth && day > now.day;
                                    final hasAttendance = _monthlyAttendanceData[name]?[day] ?? false;
                                    return DataCell(
                                      Center(
                                        child: Text(
                                          isFutureDate ? '' : (hasAttendance ? 'P' : 'A'),
                                          style: TextStyle(
                                            color: hasAttendance
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        '$totalPresent',
                                        style: TextStyle(
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        '$totalAbsent',
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: Text(
                                        attendancePercentage,
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
