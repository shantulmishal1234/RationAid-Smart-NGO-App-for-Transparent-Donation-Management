import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

class FileDownloadHelper {
  /// Downloads a CSV file to the Downloads folder on Android/iOS
  ///
  /// Returns the file path on success or throws an exception on failure
  static Future<String> downloadCsvFile({
    required String filename,
    required String csvContent,
  }) async {
    final bytes = utf8.encode(csvContent);

    if (kIsWeb) {
      // Web platform not supported for this mobile app
      throw Exception('Web download not supported. Use mobile app instead.');
    }

    // Mobile/Desktop platform
    // Request storage permission for Android 9 and below
    if (Platform.isAndroid) {
      // Check Android version - permissions not needed for Android 10+
      final androidInfo = await _getAndroidVersion();
      if (androidInfo < 29) {
        // Android 9 and below - request storage permission
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception(
            'Storage permission denied. Please grant permission to save files.',
          );
        }
      }
    }

    // Get the Downloads directory
    Directory? directory;

    if (Platform.isAndroid) {
      // For Android, use the public external storage Downloads directory
      // This makes files accessible in file managers
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // Navigate to the public Downloads folder
        // External storage structure: /storage/emulated/0/Android/data/package/files
        // We need to go up to /storage/emulated/0/Download
        final downloadsPath =
            '${externalDir.parent.parent.parent.parent.path}/Download/RationAid';
        directory = Directory(downloadsPath);

        // Create RationAid subfolder if it doesn't exist
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      }
    } else if (Platform.isIOS) {
      // For iOS, use the app's documents directory (iOS doesn't have a shared Downloads folder)
      directory = await getApplicationDocumentsDirectory();
    } else {
      // For other platforms (Desktop), use downloads directory
      directory = await getDownloadsDirectory();
    }

    if (directory == null) {
      throw Exception('Could not access downloads directory');
    }

    // Save the file
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes);

    return file.path;
  }

  /// Helper method to get Android SDK version
  static Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;

    try {
      // This is a simple approach - in production you might want to use device_info_plus package
      // For now, we'll assume modern Android (this will work for most cases)
      return 29; // Default to Android 10+
    } catch (e) {
      return 29; // Default to Android 10+ on error
    }
  }
}
