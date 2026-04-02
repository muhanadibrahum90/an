// lib/features/posts/create_post_page.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/services/upload_service.dart';
import 'package:aan/services/snack_bar_service.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final _textController = TextEditingController();
  File? _selectedImage;
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _selectedImage = File(picked.path));
  }

  Future<void> _syncToAlgolia(String postId, Map<String, dynamic> post) async {
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      final response = await http.post(
        Uri.parse('https://aan-upload.aan52907394.workers.dev/algolia-add'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'objectID': postId,
          'text': post['text'] ?? '',
          'uid': post['uid'] ?? '',
          'username': post['username'] ?? '',
          'displayName': post['displayName'] ?? '',
          'userPhoto': post['userPhoto'] ?? '',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      print('Algolia: ${response.statusCode}');
    } catch (e) {
      print('Algolia error: $e');
    }
  }

  void _removeImage() => setState(() => _selectedImage = null);

  Future<void> _publish() async {
    final text = _textController.text.trim();

    if (text.isEmpty && _selectedImage == null) {
      showSnackBar(context, 'اكتب شيئاً أو أضف صورة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      Map<String, dynamic>? userData = CacheManager.getUser();

      if (userData == null || userData.isEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        userData = doc.data() ?? {};
        if (userData.isNotEmpty) await CacheManager.saveUser(userData);
      }
      final postRef = FirebaseFirestore.instance.collection('posts').doc();
      final postId = postRef.id;

      // رفع الصورة إذا وجدت
      List<String> media = [];
      String? mediaType;
      if (_selectedImage != null) {
        final url = await UploadService.uploadPostImage(
          _selectedImage!,
          uid,
          postId,
        );
        if (url != null) {
          media = [url];
          mediaType = 'image';
        }
      }

      final boostTarget = 50 + Random().nextInt(101);

      final postData = {
        'postId': postId,
        'uid': uid,
        'username': userData?['username'] ?? '',
        'displayName': userData?['name'] ?? '',
        'userPhoto': userData?['photoUrl'] ?? '',
        'text': text,
        'media': media,
        'mediaType': mediaType,
        'likeCount': 0,
        'commentCount': 0,
        'shareCount': 0,
        'viewCount': 0,
        'trendScore': 400.0,
        'createdAt': FieldValue.serverTimestamp(),
        'editedAt': null,
      };

      await postRef.set(postData);
      await _syncToAlgolia(postId, postData);

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'postsCount': FieldValue.increment(1),
      });

      await CacheManager.updateField(
        'postsCount',
        (userData?['postsCount'] ?? 0) + 1,
      );

      if (mounted) {
        Navigator.pop(context, true);
        showSnackBar(context, 'تم نشر المنشور');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'حدث خطأ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = CacheManager.getUser();
    final photoUrl = userData?['photoUrl'] ?? '';
    final name = userData?['name'] ?? '';
    final username = userData?['username'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        surfaceTintColor: const Color(0xFF0F0E17),
        elevation: 0,
        leading: TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ),
        leadingWidth: 70,
        title: const Text(
          'منشور جديد',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : ElevatedButton(
                    onPressed: _publish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF74E278),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text(
                      'نشر',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(color: Color(0xFF2A293D), thickness: 0.5, height: 0),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: photoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photoUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            color: const Color(0xFF2A293D),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '@$username',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _textController,
                          maxLines: null,
                          maxLength: 500,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'ماذا يحدث؟',
                            hintStyle: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            counterStyle: TextStyle(color: Colors.grey),
                          ),
                        ),
                        if (_selectedImage != null) ...[
                          const SizedBox(height: 12),
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _selectedImage!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: _removeImage,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A293D), thickness: 0.5, height: 0),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _selectedImage == null ? _pickImage : null,
                    icon: Icon(
                      Icons.image_outlined,
                      color: _selectedImage == null
                          ? const Color(0xFF74E278)
                          : Colors.grey,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
