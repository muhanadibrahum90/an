// lib/features/posts/edit_post_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/services/snack_bar_service.dart';

class EditPostPage extends StatefulWidget {
  final Map<String, dynamic> post;
  const EditPostPage({super.key, required this.post});

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  late TextEditingController _textController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.post['text'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _textController.text.trim();

    if (text.isEmpty) {
      showSnackBar(context, 'النص لا يمكن أن يكون فارغاً');
      return;
    }

    if (text == (widget.post['text'] as String? ?? '').trim()) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final postId = widget.post['postId'] as String? ?? '';

      await FirebaseFirestore.instance.collection('posts').doc(postId).update({
        'text': text,
        'editedAt': FieldValue.serverTimestamp(),
      });

      await _syncToAlgolia(postId, text);

      if (mounted) {
        Navigator.pop(context, true);
        showSnackBar(context, 'تم تعديل المنشور');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'حدث خطأ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncToAlgolia(String postId, String text) async {
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      await http.post(
        Uri.parse('https://aan-upload.aan52907394.workers.dev/algolia-add'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'objectID': postId, 'text': text}),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final userData = CacheManager.getUser();
    final photoUrl = userData?['photoUrl'] ?? '';
    final name = userData?['name'] ?? '';
    final username = userData?['username'] ?? '';
    final media = List<String>.from(widget.post['media'] as List? ?? []);

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
          'تعديل المنشور',
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
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF74E278),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text(
                      'حفظ',
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
                        // الاسم
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

                        if (media.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: media.first,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'لا يمكن تعديل الصورة',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ],
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
