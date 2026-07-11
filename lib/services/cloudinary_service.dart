import 'dart:io';
import 'package:http/http.dart' as http;


class CloudinaryResponse {
  final String? url;
  final String? errorMessage;
  final bool isSuccess;

  CloudinaryResponse({this.url, this.errorMessage, required this.isSuccess});
}

class CloudinaryService {
  // Use your actual Cloudinary cloud name and unsigned preset
  static const String cloudName = 'daw86j6we';
  static const String uploadPreset = 'fyp_unsigned';

  /// Uploads a file to Cloudinary.
  /// Returns a CloudinaryResponse with either a secure_url or an error message.
  static Future<CloudinaryResponse> uploadImage(File file) async {
    try {
      final filePath = file.path.toLowerCase();
      final isImage =
          filePath.endsWith('.jpg') ||
          filePath.endsWith('.jpeg') ||
          filePath.endsWith('.png') ||
          filePath.endsWith('.gif') ||
          filePath.endsWith('.webp');

      final resourceType = isImage ? 'image' : 'raw';
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      print('Starting Cloudinary upload to: $uri');

      // Top-level timeout for the entire operation (connect + upload + response)
      final response = await request.send().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          print('Cloudinary upload timed out during send phase');
          throw Exception('Upload timed out after 45 seconds');
        },
      );

      print('Cloudinary response headers received: ${response.statusCode}');

      final body = await response.stream.bytesToString().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          print('Cloudinary timed out while reading response body');
          throw Exception('Timeout reading response from server');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final url = RegExp(
          r'"secure_url"\s*:\s*"([^"]+)"',
        ).firstMatch(body)?.group(1);
        if (url != null) {
          print('Cloudinary upload successful: $url');
          return CloudinaryResponse(url: url, isSuccess: true);
        } else {
          return CloudinaryResponse(
            isSuccess: false,
            errorMessage: 'Upload successful but URL not found in response',
          );
        }
      } else {
        String errorMsg = 'Status ${response.statusCode}';
        try {
          final errorDetail = RegExp(
            r'"message"\s*:\s*"([^"]+)"',
          ).firstMatch(body)?.group(1);
          if (errorDetail != null) errorMsg = errorDetail;
        } catch (_) {}
        print('Cloudinary upload failed: $errorMsg');
        return CloudinaryResponse(
          isSuccess: false,
          errorMessage: 'Cloudinary Error: $errorMsg',
        );
      }
    } catch (e) {
      print('CloudinaryService Error: $e');
      String msg = e.toString();
      if (msg.contains('SocketException')) {
        msg = 'Network unreachable. Please check your internet connection.';
      } else if (msg.contains('timeout') || msg.contains('Timeout')) {
        msg =
            'Upload timed out after 45 seconds. Please check your connection stability.';
      }
      return CloudinaryResponse(isSuccess: false, errorMessage: msg);
    }
  }
}
