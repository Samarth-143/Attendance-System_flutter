import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'screens/home_screen.dart';
import 'services/background_email_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('📧 [WORKMANAGER] Task started: $task');
      await BackgroundEmailService.sendDailyEmail();
      debugPrint('✅ [WORKMANAGER] Task completed successfully');
      return Future.value(true);
    } catch (e) {
      debugPrint('❌ [WORKMANAGER] Task failed: $e');
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Workmanager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Changed to true for better logging
  );
  
  debugPrint('✅ [APP] Workmanager initialized');
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Attendance',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}