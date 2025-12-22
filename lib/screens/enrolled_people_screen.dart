import 'package:flutter/material.dart';
import '../services/database_service.dart';

class EnrolledPeopleScreen extends StatefulWidget {
  const EnrolledPeopleScreen({super.key});

  @override
  State<EnrolledPeopleScreen> createState() => _EnrolledPeopleScreenState();
}

class _EnrolledPeopleScreenState extends State<EnrolledPeopleScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<Map<String, dynamic>> _enrolledPeople = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEnrolledPeople();
  }

  Future<void> _loadEnrolledPeople() async {
    setState(() => _isLoading = true);
    await _databaseService.initialize();
    final people = await _databaseService.getAllEnrolledFaces();
    setState(() {
      _enrolledPeople = people;
      _isLoading = false;
    });
  }

  Future<void> _deletePerson(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Person'),
        content: Text('Are you sure you want to delete $name?'),
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
      await _databaseService.deleteFace(id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name deleted successfully')),
      );
      _loadEnrolledPeople();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrolled People'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                '${_enrolledPeople.length} people',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _enrolledPeople.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No people enrolled yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: const Text('Enroll Someone'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEnrolledPeople,
                  child: ListView.builder(
                    itemCount: _enrolledPeople.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final person = _enrolledPeople[index];
                      final name = person['name'] as String;
                      final id = person['id'] as int;
                      final role = person['role'] as String? ?? 'Staff';
                      final contractor = person['contractor'] as String?;
                      final shift = person['shift'] as String? ?? 'Day';
                      final createdAt = DateTime.parse(person['created_at'] as String);
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Role: $role${contractor != null && contractor.isNotEmpty ? ' | Contractor: $contractor' : ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Shift: $shift',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: shift == 'Night' ? Colors.indigo[700] : Colors.orange[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Enrolled on ${createdAt.day}/${createdAt.month}/${createdAt.year} at ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deletePerson(id, name),
                            tooltip: 'Delete',
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
