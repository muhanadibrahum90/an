// lib/features/profile/edit_profile_page.dart

import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/services/upload_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:aan/services/snack_bar_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _firestore = FirebaseFirestore.instance;
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _hasChanges = false;

  File? _newProfileImage;
  File? _newCoverImage;
  bool _isLoading = false;
  bool? _isUsernameAvailable;
  Timer? _debounce;
  String _originalUsername = '';

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.userData['name'] ?? '';
    _usernameController.text = widget.userData['username'] ?? '';
    _bioController.text = widget.userData['bio'] ?? '';
    _originalUsername = widget.userData['username'] ?? '';

    _nameController.addListener(_checkChanges);
    _usernameController.addListener(_checkChanges);
    _bioController.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _checkUsername(String username) async {
    _debounce?.cancel();

    final cleaned = username.trim().toLowerCase();

    if (cleaned == _originalUsername) {
      setState(() => _isUsernameAvailable = null);
      return;
    }

    final validFormat = RegExp(r'^[a-z0-9_]+$');
    if (cleaned.length < 3 || !validFormat.hasMatch(cleaned)) {
      setState(() => _isUsernameAvailable = null);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final doc = await _firestore.collection('usernames').doc(cleaned).get();

        if (mounted) {
          setState(() => _isUsernameAvailable = !doc.exists);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUsernameAvailable = null);
        }
      }
    });
  }

  Future<void> _pickImage(bool isProfile) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() {
      if (isProfile) {
        _newProfileImage = File(picked.path);
      } else {
        _newCoverImage = File(picked.path);
      }
    });
    _checkChanges();
  }

  Future<void> _updatePostsUserData(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    try {
      final posts = await _firestore
          .collection('posts')
          .where('uid', isEqualTo: uid)
          .get();

      if (posts.docs.isEmpty) return;

      final batch = _firestore.batch();

      for (final doc in posts.docs) {
        batch.update(doc.reference, {
          if (updates.containsKey('name')) 'displayName': updates['name'],
          if (updates.containsKey('username')) 'username': updates['username'],
          if (updates.containsKey('photoUrl')) 'userPhoto': updates['photoUrl'],
        });
      }

      await batch.commit();
    } catch (e) {}
  }

  Future<void> _saveChanges() async {
    final username = _usernameController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      showSnackBar(context, 'الاسم لا يمكن أن يكون فارغاً');
      return;
    }

    if (username != _originalUsername && _isUsernameAvailable != true) {
      showSnackBar(context, 'اسم المستخدم غير متاح');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final updates = <String, dynamic>{
        'name': name,
        'username': username,
        'bio': _bioController.text.trim(),
      };

      if (_newProfileImage != null) {
        final url = await UploadService.uploadProfileImage(
          _newProfileImage!,
          uid,
        );
        if (url != null) {
          updates['photoUrl'] =
              '$url?v=${DateTime.now().millisecondsSinceEpoch}';
        }
      }

      if (_newCoverImage != null) {
        final url = await UploadService.uploadCoverImage(_newCoverImage!, uid);
        if (url != null) {
          updates['coverUrl'] =
              '$url?v=${DateTime.now().millisecondsSinceEpoch}';
        }
      }

      final batch = _firestore.batch();

      batch.update(_firestore.collection('users').doc(uid), updates);

      if (username != _originalUsername) {
        batch.delete(_firestore.collection('usernames').doc(_originalUsername));
        batch.set(_firestore.collection('usernames').doc(username), {
          'uid': uid,
        });
      }

      await batch.commit();

      await _updatePostsUserData(uid, updates);
      await _updateChatsUserData(uid, updates);

      await CacheManager.clearUser();
      final newData = {...widget.userData, ...updates};
      await CacheManager.saveUser(newData);

      if (mounted) {
        Navigator.pop(context, newData);
        showSnackBar(context, 'تم تحديث الملف الشخصي ');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'حدث خطأ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateChatsUserData(
    String uid,
    Map<String, dynamic> updates,
  ) async {
    try {
      final db = FirebaseDatabase.instance.ref();

      final chatsSnap = await db.child('userChats/$uid').get();
      if (chatsSnap.value == null) return;

      final chatIds = Map<String, dynamic>.from(chatsSnap.value as Map).keys;

      final Map<String, dynamic> dbUpdates = {};

      for (final chatId in chatIds) {
        if (updates.containsKey('name')) {
          dbUpdates['chats/$chatId/info/usersInfo/$uid/displayName'] =
              updates['name'];
        }
        if (updates.containsKey('photoUrl')) {
          dbUpdates['chats/$chatId/info/usersInfo/$uid/photoUrl'] =
              updates['photoUrl'];
        }
      }

      if (dbUpdates.isNotEmpty) {
        await db.update(dbUpdates);
      }
    } catch (e) {}
  }

  void _checkChanges() {
    final changed =
        _nameController.text.trim() != (widget.userData['name'] ?? '') ||
        _usernameController.text.trim() !=
            (widget.userData['username'] ?? '') ||
        _bioController.text.trim() != (widget.userData['bio'] ?? '') ||
        _newProfileImage != null ||
        _newCoverImage != null;

    if (changed != _hasChanges) {
      setState(() {
        _hasChanges = changed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.userData['photoUrl'] ?? '';
    final coverUrl = widget.userData['coverUrl'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        surfaceTintColor: const Color(0xFF0F0E17),
        elevation: 0,
        title: const Text(
          'تعديل الملف الشخصي',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    onPressed: (_hasChanges && !_isLoading)
                        ? _saveChanges
                        : null,
                    child: Text(
                      'حفظ',
                      style: TextStyle(
                        color: _hasChanges
                            ? const Color(0xFF74E278)
                            : Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              children: [
                GestureDetector(
                  onTap: () => _pickImage(false),
                  child: Container(
                    width: double.infinity,
                    height: 150,
                    color: const Color(0xFF74E278),
                    child: _newCoverImage != null
                        ? Image.file(_newCoverImage!, fit: BoxFit.cover)
                        : coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 150,
                          )
                        : const Center(
                            child: Icon(
                              Icons.add_a_photo,
                              color: Colors.white54,
                              size: 32,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _pickImage(false),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            Transform.translate(
              offset: const Offset(0, -40),
              child: Center(
                child: GestureDetector(
                  onTap: () => _pickImage(true),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: const Color(0xFF0F0E17),
                        child: ClipOval(
                          child: _newProfileImage != null
                              ? Image.file(
                                  _newProfileImage!,
                                  width: 82,
                                  height: 82,
                                  fit: BoxFit.cover,
                                )
                              : photoUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photoUrl,
                                  width: 82,
                                  height: 82,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 44,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0xFF74E278),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 4),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildField('الاسم', _nameController, maxLength: 30),
                  const SizedBox(height: 16),
                  _buildUsernameField(),
                  const SizedBox(height: 16),
                  _buildField('السيرة الذاتية', _bioController, maxLines: 3),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          cursorColor: const Color(0xFF74E278),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2A293D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            counterStyle: const TextStyle(color: Colors.grey), // ✅ لون العداد
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اسم المستخدم',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _usernameController,

          cursorColor: const Color(0xFF74E278),
          style: const TextStyle(color: Colors.white),
          maxLength: 20, // نفس الحد
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
          ],
          onChanged: _checkUsername,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2A293D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            prefixText: '@',
            prefixStyle: const TextStyle(color: Colors.grey),
            suffixIcon: _isUsernameAvailable == null
                ? null
                : Icon(
                    _isUsernameAvailable! ? Icons.check_circle : Icons.cancel,
                    color: _isUsernameAvailable!
                        ? const Color(0xFF74E278)
                        : Colors.red,
                  ),
          ),
        ),
        if (_isUsernameAvailable == false)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'اسم المستخدم مستخدم بالفعل',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        if (_isUsernameAvailable == true)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'اسم المستخدم متاح ✓',
              style: TextStyle(color: Color(0xFF74E278), fontSize: 12),
            ),
          ),
      ],
    );
  }
}
