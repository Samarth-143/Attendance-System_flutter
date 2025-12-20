# Face Attendance App

A Flutter-based **on-device face recognition attendance system** with offline capabilities. Capture, recognize, and track attendance using facial recognition technology that runs entirely on your device.

## Features

### 🎯 Core Functionality
- **Face Enrollment**: Enroll staff and workers with multiple captures for accuracy
- **Real-time Recognition**: Instant face recognition with attendance marking
- **Role Management**: Differentiate between Staff and Worker roles
- **Contractor Tracking**: Optional contractor field for additional classification
- **Attendance Records**: Track check-in and check-out times automatically

### 📊 Reporting & Analytics
- **Daily View**: View attendance by date with in/out times
- **Monthly View**: Complete monthly attendance matrix with:
  - Present/Absent marking (only up to current date)
  - Total present and absent days
  - Attendance percentage calculation
- **CSV Export**: Export daily and monthly reports to CSV format
- **Email Reports**: Send attendance reports via email

### 🔒 Privacy & Security
- **100% On-Device Processing**: No data leaves your device
- **Offline Operation**: Works without internet connection
- **Local Storage**: SQLite database for all data

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter |
| Face Detection | Google ML Kit |
| Face Recognition | MobileFaceNet (TFLite) |
| Database | SQLite |
| Permissions | Permission Handler |
| CSV Export | CSV Package |

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / VS Code
- Android device or emulator (iOS support available)
- MobileFaceNet TFLite model file

## Installation

### 1. Clone the Repository
```bash
git clone <repository-url>
cd attendance_flutter
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Add Model File
Place the `mobilefacenet.tflite` model in:
```
assets/models/mobilefacenet.tflite
```

### 4. Run the App
```bash
# For debug build
flutter run

# For release APK
flutter build apk --release
```

The release APK will be located at:
```
build/app/outputs/flutter-apk/app-release.apk
```

## Usage

### Enrolling People
1. Tap **"Enroll Face"** from the home screen
2. Enter the person's name
3. Select their role (Staff/Worker)
4. Optionally enter contractor name
5. Tap **"Start Enrollment"**
6. The app will automatically capture 5 images
7. Face is enrolled with averaged embeddings

### Marking Attendance
1. Tap **"Recognize Face"** from the home screen
2. Point camera at the person
3. Face is automatically detected and recognized
4. Attendance is marked with timestamp
5. In-time: Before 4 PM | Out-time: After 4 PM

### Viewing Records
1. **Daily Records**: View attendance grouped by date and role
2. **Monthly View**: See full month attendance matrix
3. Filter by month using navigation arrows

### Exporting Data
- **Daily CSV**: Includes name, role, contractor, in-time, out-time
- **Monthly CSV**: Includes attendance matrix (P/A), totals, and percentage
- Files saved to Downloads folder

### Email Reports
1. Configure SMTP settings in Email Settings
2. Select records to send
3. Compose and send email with CSV attachment

## Database Schema

### Faces Table
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| name | TEXT | Person's name |
| role | TEXT | Staff/Worker |
| contractor | TEXT | Contractor name (optional) |
| embedding | TEXT | Face embedding (comma-separated) |
| created_at | TEXT | ISO8601 timestamp |

### Attendance Table
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| name | TEXT | Person's name |
| timestamp | TEXT | ISO8601 timestamp |

## App Structure

```
lib/
├── main.dart                           # App entry point
├── face_detector.dart                  # Face detection logic
├── face_embedder.dart                  # Face embedding extraction
├── screens/
│   ├── home_screen.dart               # Main navigation
│   ├── enroll_screen.dart             # Face enrollment
│   ├── recognize_screen.dart          # Face recognition
│   ├── enrolled_people_screen.dart    # View enrolled people
│   ├── attendance_table_screen.dart   # Attendance reports
│   ├── monthly_attendance_screen.dart # Monthly view
│   └── email_settings_screen.dart     # Email configuration
└── services/
    ├── database_service.dart          # SQLite operations
    ├── face_service.dart              # Face processing
    └── email_service.dart             # Email functionality
```

## Configuration

### Similarity Threshold
Adjust face matching sensitivity in `database_service.dart`:
```dart
static const double similarityThreshold = 0.7; // Range: 0.0 - 1.0
```

### In/Out Time Threshold
Modify the time that separates check-in from check-out in `attendance_table_screen.dart`:
```dart
if (time.hour < 16) { // Before 4 PM = In-time
  // ...
}
```

## Permissions

The app requires the following Android permissions:
- **Camera**: For face detection and recognition
- **Storage**: For CSV export and file access
- **Manage External Storage**: For Android 11+ file access

Permissions are automatically requested at runtime.

## Troubleshooting

### Build Issues
- **OneDrive file locks**: Project should ideally be outside OneDrive folders
- **Gradle cache**: Run `flutter clean` and rebuild
- **Duplicate files**: Delete any files with `-WIN-` suffix

### Recognition Issues
- **Low accuracy**: Re-enroll with better lighting conditions
- **False positives**: Increase similarity threshold
- **No detection**: Ensure face is well-lit and within frame

### Export Issues
- **Permission denied**: Grant storage permissions in app settings
- **File not found**: Check Downloads folder path

## Building for Production

### Release APK
```bash
flutter build apk --release
```

### App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

### Signed APK
1. Create `key.properties` in `android/` folder
2. Generate keystore
3. Configure signing in `android/app/build.gradle`
4. Build signed APK

## Future Enhancements

- [ ] Cloud backup and sync
- [ ] Advanced analytics and insights
- [ ] Multi-language support
- [ ] Wear OS support
- [ ] Biometric authentication
- [ ] Shift management
- [ ] Leave management system
- [ ] QR code fallback

## Contributing

Contributions are welcome! Please follow these steps:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

This project is licensed under the MIT License.

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Contact the development team

---

**Made with ❤️ using Flutter**