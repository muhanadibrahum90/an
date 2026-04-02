import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:aan/features/onboarding/welcome_page.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:aan/services/snack_bar_service.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _reauthenticated = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _deleteAccount() async {
  setState(() => _isLoading = true);

  try {
    final user = FirebaseAuth.instance.currentUser!;

    final providerIds = user.providerData.map((p) => p.providerId).toList();
    final isGoogle = providerIds.contains('google.com');
    final isEmail = providerIds.contains('password');


    if (isEmail) {
      final password = _passwordController.text.trim();
      if (password.isEmpty) {
        setState(() => _isLoading = false);
        showSnackBar(context, 'أدخل كلمة المرور');
        return;
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      _reauthenticated = true;

    } else if (isGoogle) {
      final inputUsername = _passwordController.text.trim();

      if (inputUsername.isEmpty) {
        setState(() => _isLoading = false);
        showSnackBar(context, 'أدخل اسم المستخدم');
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final realUsername = userDoc.data()?['username'] ?? '';

      if (inputUsername != realUsername) {
        setState(() => _isLoading = false);
        showSnackBar(context, 'اسم المستخدم غير صحيح', isError: true);
        return;
      }

      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      _reauthenticated = true;
    }

    if (!_reauthenticated) {
      setState(() => _isLoading = false);
      return;
    }
      final postsSnap = await FirebaseFirestore.instance
          .collection('posts')
          .where('uid', isEqualTo: user.uid)
          .get();

      final postIds = postsSnap.docs
          .map((d) => d.data()['postId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      try {
        final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
        await functions
            .httpsCallable(
              'deleteUserData',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 60),
              ),
            )
            .call();
      } catch (e) {
      }

      try {
        final token = await user.getIdToken();
        await http.post(
          Uri.parse(
            'https://aan-upload.aan52907394.workers.dev/delete-account-user',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'postIds': postIds}),
        );
      } catch (e) {
      }

      await CacheManager.clearAll();

      try {
        await user.delete();
      } catch (e) {
        await FirebaseAuth.instance.signOut();
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      final message = e.code == 'wrong-password'
          ? 'كلمة المرور غير صحيحة'
          : 'حدث خطأ، حاول مرة أخرى';
      if (mounted) {
        showSnackBar(context, (message));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showSnackBar(context, 'حدث خطأ: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGoogle =
        user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _deleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'حذف حسابي نهائياً',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  247,
                  240,
                  240,
                ).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_outlined,
                color: Color.fromARGB(255, 240, 240, 240),
                size: 32,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'حذف الحساب',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'هذا الإجراء لا يمكن التراجع عنه، سيتم حذف حسابك وجميع بياناتك نهائياً.',
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),

            const SizedBox(height: 32),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1B2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  _DeleteItem(text: 'ملفك الشخصي وصورتك'),
                  _DeleteItem(text: 'جميع منشوراتك'),
                  _DeleteItem(text: 'رسائلك ومحادثاتك'),
                  _DeleteItem(text: 'متابعيك ومن تتابعهم', isLast: true),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ✅ بدل if (!isGoogle)
            const Text(
              'أدخل اسم المستخدم او كلمة المرور للتأكيد',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController, // نفس الـ controller
              cursorColor: Colors.red,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: isGoogle ? 'اسم المستخدم' : 'كلمة المرور',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1C1B2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: isGoogle
                    ? null
                    : IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
              ),
              obscureText: isGoogle ? false : _obscurePassword,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DeleteItem extends StatelessWidget {
  final String text;
  final bool isLast;

  const _DeleteItem({required this.text, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.remove_circle_outline,
              color: Colors.red,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(text, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        if (!isLast) const Divider(color: Color(0xFF2A293D), height: 20),
      ],
    );
  }
}
