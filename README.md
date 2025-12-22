# Face Attendance App

A Flutter-based face recognition attendance system that runs entirely on your device. No internet required.

## Features

- **Face Enrollment**: Enroll staff and workers with name, role, contractor, and shift
- **Real-time Recognition**: Automatic face recognition and attendance marking
- **Attendance Tracking**: Daily and monthly attendance records with in/out times
- **Shift Management**: Day and Night shift tracking
- **Export & Email**: CSV export and email reports
- **100% Offline**: All processing happens on-device

## Installation

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run

# Build release APK
flutter build apk --release
```

Place `mobilefacenet.tflite` model in `assets/models/` before building.

## Usage

**Enroll**: Enter name, select role/shift, capture face  
**Recognize**: Point camera at person to mark attendance  
**View Records**: Check daily or monthly attendance  
**Export**: Save CSV or send via email

## Tech Stack

Flutter | Google ML Kit | MobileFaceNet | SQLite

## License

MIT License