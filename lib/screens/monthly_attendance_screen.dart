import 'package:flutter/material.dart';
import '../services/database_service.dart';

class MonthlyAttendanceScreen extends StatefulWidget {
  const MonthlyAttendanceScreen({super.key});

  @override
  State<MonthlyAttendanceScreen> createState() => _MonthlyAttendanceScreenState();
}

class _MonthlyAttendanceScreenState extends State<MonthlyAttendanceScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Map<String, Map<int, bool>> _attendanceData = {}; // personName -> {day -> hasAttendance}
  List<Map<String, dynamic>> _allPeople = [];
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = true;
  int _daysInMonth = 0;

  @override
  void initState() {
    super.initState();
    _loadMonthlyAttendance();
  }

  Future<void> _loadMonthlyAttendance() async {
    setState(() => _isLoading = true);
    await _databaseService.initialize();

    // Get all enrolled people
    final faces = await _databaseService.getAllEnrolledFaces();
    _allPeople = faces.map((face) => {
      'name': face['name'] as String,
      'role': face['role'] as String,
    }).toList();

    // Sort by role (Staff first) then by name
    _allPeople.sort((a, b) {
      if (a['role'] != b['role']) {
        return a['role'] == 'Staff' ? -1 : 1;
      }
      return (a['name'] as String).compareTo(b['name'] as String);
    });

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
      _attendanceData = attendanceMap;
      _isLoading = false;
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
    _attendanceData[personName]?.forEach((day, present) {
      if (present) total++;
    });
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMonthlyAttendance,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                // Attendance table
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
                              headingRowColor: MaterialStateProperty.all(Colors.blue[50]),
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
                                DataColumn(
                                  label: Text(
                                    'Total A',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                              rows: _allPeople.map((person) {
                                final name = person['name'] as String;
                                final role = person['role'] as String;
                                final totalPresent = _getTotalPresent(name);
                                final totalAbsent = _daysInMonth - totalPresent;
                                
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
                                    // Day cells
                                    ...List.generate(_daysInMonth, (index) {
                                      final day = index + 1;
                                      final hasAttendance = _attendanceData[name]?[day] ?? false;
                                      return DataCell(
                                        Center(
                                          child: Text(
                                            hasAttendance ? 'P' : 'A',
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
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
