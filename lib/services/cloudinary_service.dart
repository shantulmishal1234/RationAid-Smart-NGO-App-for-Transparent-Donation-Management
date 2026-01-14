import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class CloudinaryService {
  // Use your actual Cloudinary cloud name and unsigned preset
  static const String cloudName = 'daw86j6we';
  static const String uploadPreset = 'fyp_unsigned';

  static Future<String?> uploadImage(File file) async {
    try {
      // Determine if it's an image or document based on file extension
      final filePath = file.path.toLowerCase();
      final isImage =
          filePath.endsWith('.jpg') ||
          filePath.endsWith('.jpeg') ||
          filePath.endsWith('.png') ||
          filePath.endsWith('.gif') ||
          filePath.endsWith('.webp');

      // Use 'raw' resource type for PDFs and documents, 'image' for images
      final resourceType = isImage ? 'image' : 'raw';

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path,
            contentType: isImage
                ? MediaType('image', 'jpeg')
                : MediaType('application', 'pdf'),
          ),
        );

      // Add timeout to prevent hanging
      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('Cloudinary upload timed out after 30 seconds');
          throw Exception('Upload timed out');
        },
      );

      final body = await response.stream.bytesToString();

      // Debug logs – check console after you try one upload
      print('Cloudinary status: ${response.statusCode}');
      print('Cloudinary body: $body');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final url = RegExp(
          r'"secure_url"\s*:\s*"([^"]+)"',
        ).firstMatch(body)?.group(1);
        return url;
      } else {
        print('Cloudinary upload failed with status: ${response.statusCode}');
        // On 400/401 etc. this returns null so UI shows "Document upload failed"
        return null;
      }
    } catch (e) {
      print('Cloudinary upload error: $e');
      return null;
    }
  }
}
