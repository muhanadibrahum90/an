import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../settings/verify_new_email_page.dart';
import 'package:aan/services/snack_bar_service.dart';

class ChangeEmailPage extends StatefulWidget {
  const ChangeEmailPage({super.key});

  @override
  State<ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<ChangeEmailPage> {
  final _newEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String _currentEmail = '';

  late final bool _isGoogleUser;

  @override
  void initState() {
    super.initState();
    _isGoogleUser =
        FirebaseAuth.instance.currentUser?.providerData.any(
          (p) => p.providerId == 'google.com',
        ) ??
        false;
    _loadCurrentEmail();
  }

  Future<void> _loadCurrentEmail() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseAuth.instance.currentUser?.reload();
    final authEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    if (authEmail.isNotEmpty) {
      if (mounted) setState(() => _currentEmail = authEmail);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (mounted) {
      setState(() {
        _currentEmail = doc.data()?['email'] as String? ?? '';
      });
    }
  }

  @override
  void dispose() {
    _newEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailController.text.trim();

    if (newEmail.isEmpty) {
      showSnackBar(context, 'أدخل البريد الجديد');
      return;
    }

    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      showSnackBar(context, 'البريد الإلكتروني غير صحيح');

      return;
    }

    if (newEmail == _currentEmail) {
      showSnackBar(context, 'البريد الجديد نفس البريد الحالي');

      return;
    }

    if (!_isGoogleUser && _passwordController.text.trim().isEmpty) {
      showSnackBar(context, 'أدخل كلمة المرور');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      if (_isGoogleUser) {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        final credential = EmailAuthProvider.credential(
          email: _currentEmail,
          password: _passwordController.text.trim(),
        );
        await user.reauthenticateWithCredential(credential);
      }

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: newEmail)
          .get();

      if (query.docs.isNotEmpty) {
        if (mounted) {
          showSnackBar(context, 'هذا البريد مرتبط بحساب آخر');

          setState(() => _isLoading = false);
        }
        return;
      }

      await FirebaseAuth.instance.currentUser!.verifyBeforeUpdateEmail(
        newEmail,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyNewEmailPage(newEmail: newEmail),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _isLoading = false);
      final message = switch (e.code) {
        'email-already-in-use' => 'البريد مستخدم بالفعل',
        'wrong-password' => 'كلمة المرور غير صحيحة',
        'invalid-credential' => 'كلمة المرور غير صحيحة',
        'invalid-email' => 'البريد الإلكتروني غير صحيح',
        'requires-recent-login' => 'يرجى تسجيل الخروج والدخول مجدداً',
        _ => 'حدث خطأ، حاول مرة أخرى',
      };
      if (mounted) {
        showSnackBar(context, (message));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        showSnackBar(context, 'حدث خطأ', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _changeEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(230, 255, 255, 255),
                foregroundColor: const Color(0xFF0F0E17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text(
                      'تغيير البريد الإلكتروني',
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
        child: _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.email_outlined, size: 54, color: Colors.white),
        const SizedBox(height: 20),
        const Text(
          'تغيير البريد الإلكتروني',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'بريدك الحالي: $_currentEmail',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 32),
        const Text(
          'البريد الجديد',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _newEmailController,
          cursorColor: const Color(0xFF74E278),
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'البريد الإلكتروني الجديد',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF1C1B2E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (!_isGoogleUser) ...[
          const SizedBox(height: 20),
          const Text(
            'كلمة المرور للتأكيد',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            cursorColor: const Color(0xFF74E278),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'كلمة المرور',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFF1C1B2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
        ],
        if (_isGoogleUser) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم فصل حسابك عن Google وتحويله لحساب بريد إلكتروني',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
