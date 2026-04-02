import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class UploadService {
  static const String _workerUrl = 'https://cdn.aansocial.me/upload';


  static Future<String?> uploadProfileImage(File image, String uid) async {
    try {
      // جلب الـ Firebase idToken الحالي
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();

      if (token == null) {
        return null;
      }

      final request = http.MultipartRequest('POST', Uri.parse(_workerUrl));

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          image.path,
          contentType: http.MediaType(
            'image',
            'jpeg',
          ), 
        ),
      );

      final response = await request.send();

      final body = await response.stream.bytesToString();



      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data['url'];
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
  static Future<String?> uploadCoverImage(File image, String uid) async {
  try {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return null;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://cdn.aansocial.me/upload-cover'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        image.path,
        contentType: http.MediaType('image', 'jpeg'),
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      return jsonDecode(body)['url'];
    }
    return null;
  } catch (e) {
    return null;
  }
}
static Future<String?> uploadPostImage(File image, String uid, String postId) async {
  try {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return null;

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://cdn.aansocial.me/upload-post'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.headers['x-post-id'] = postId;
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        image.path,
        contentType: http.MediaType('image', 'jpeg'),
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      return jsonDecode(body)['url'];
    }
    return null;
  } catch (e) {
    return null;
  }
}
}
