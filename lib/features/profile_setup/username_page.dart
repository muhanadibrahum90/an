import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aan/services/upload_service.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aan/features/auth/verify_email_page.dart';
import 'package:aan/features/home/home_page.dart';

class UsernamePage extends StatefulWidget {
  final String email;
  final String password;
  final String name;
  final bool isGoogleSignIn;
  final File? profileImage; // ✅ أضف هذا

  const UsernamePage({
    super.key,
    required this.email,
    required this.password,
    required this.name,
    this.isGoogleSignIn = false,
    this.profileImage, // ✅ أضف هذا
  });

  @override
  State<UsernamePage> createState() => _UsernamePageState();
}

class _UsernamePageState extends State<UsernamePage> {
  final TextEditingController usernameController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _debounce;
  bool isLoading = false;
  bool? isAvailable;

  Future<void> _checkUsername(String username) async {
    _debounce?.cancel();

    final validFormat = RegExp(r'^[a-z0-9_]+$');
    if (username.length < 3 || !validFormat.hasMatch(username)) {
      setState(() => isAvailable = null);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final doc = await _firestore
            .collection('usernames')
            .doc(username)
            .get();
        if (mounted) setState(() => isAvailable = !doc.exists);
      } catch (e) {
        if (mounted) setState(() => isAvailable = null);
      }
    });
  }

  Future<void> _createAccount() async {
    final username = usernameController.text.trim().toLowerCase();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسم المستخدم')),
      );
      return;
    }

    if (isAvailable != true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اسم المستخدم غير متاح')));
      return;
    }

    setState(() => isLoading = true);

    try {
      late String uid;
      late String email;

      if (widget.isGoogleSignIn) {
        uid = FirebaseAuth.instance.currentUser!.uid;
        // ✅ يأخذ البريد من widget أولاً ثم من currentUser كبديل
        email = widget.email.isNotEmpty
            ? widget.email
            : FirebaseAuth.instance.currentUser!.email ?? '';
      } else {
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: widget.email,
              password: widget.password,
            );
        uid = userCredential.user!.uid;
        email = widget.email;
      }
      // ✅ رفع الصورة إذا اختار المستخدم صورة
      // ✅ رفع الصورة - إذا لم يختر صورة استخدم الافتراضية
      String photoUrl = '';
      if (widget.profileImage != null) {
        final url = await UploadService.uploadProfileImage(
          widget.profileImage!,
          uid,
        );
        photoUrl = url ?? '';
      } else {
        // ✅ رفع الصورة الافتراضية من assets
        final byteData = await rootBundle.load(
          'assets/images/default_avatar.png',
        );
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/default_avatar.png');
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());

        final url = await UploadService.uploadProfileImage(tempFile, uid);
        photoUrl = url ?? '';
      }
      final batch = FirebaseFirestore.instance.batch();

      batch.set(FirebaseFirestore.instance.collection('users').doc(uid), {
        'name': widget.name,
        'username': username,
        'email': email,
        'photoUrl': photoUrl,
        'bio': '',
        'followersCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(
        FirebaseFirestore.instance.collection('usernames').doc(username),
        {'uid': uid},
      );

      await batch.commit();

      // أرسل التحقق فقط إذا لم يكن Google
      if (!widget.isGoogleSignIn) {
        try {
          await FirebaseAuth.instance.currentUser?.sendEmailVerification();
        } catch (e) {
        }

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const VerifyEmailPage()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      String message = switch (e.code) {
        'email-already-in-use' => 'البريد الإلكتروني مستخدم بالفعل',
        'weak-password' => 'كلمة المرور ضعيفة',
        'network-request-failed' => 'تحقق من اتصالك بالإنترنت', // ← أضف هذا
        _ => e.message ?? 'حدث خطأ',
      };
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(backgroundColor: const Color(0xFF0F0E17), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            const Text(
              'اختر اسم مستخدم',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك تغييره لاحقاً من الإعدادات',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: usernameController,
              style: const TextStyle(color: Colors.white),
              maxLength: 20,
              cursorColor: Colors.white,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[a-z0-9_]'),
                ), // ← يمنع أي شيء غير مسموح
              ],
              onChanged: (value) => _checkUsername(value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'اسم_المستخدم',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixText: '@  ',
                prefixStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A293D),
                counterStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: isAvailable == null
                    ? null
                    : Icon(
                        isAvailable! ? Icons.check_circle : Icons.cancel,
                        color: isAvailable! ? Colors.green : Colors.red,
                      ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'يُسمح فقط بالأحرف الإنجليزية الصغيرة والأرقام و _',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),

            if (isAvailable != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  isAvailable! ? 'اسم المستخدم متاح ✓' : 'اسم المستخدم مأخوذ',
                  style: TextStyle(
                    color: isAvailable! ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
              ),

            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : _createAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(230, 255, 255, 255),
                  foregroundColor: const Color(0xFF0F0E17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white, // ✅ دائرة بيضاء
                        strokeWidth: 2.5,
                      )
                    : const Text(
                        'إنشاء الحساب',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
