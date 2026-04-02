import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aan/services/cache_manager.dart';
import '../onboarding/welcome_page.dart';
import 'package:aan/services/snack_bar_service.dart';

class UnlinkGooglePage extends StatefulWidget {
  const UnlinkGooglePage({super.key});

  @override
  State<UnlinkGooglePage> createState() => _UnlinkGooglePageState();
}

class _UnlinkGooglePageState extends State<UnlinkGooglePage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newEmail = _emailController.text.trim();
    final newPassword = _passwordController.text;

    if (newEmail.isEmpty) {
      showSnackBar(context, 'ادخل البريد الإلكتروني');
      return;
    }
    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      showSnackBar(context, 'البريد الإلكتروني غير صحيح');
      return;
    }
    if (newPassword.isEmpty) {
      showSnackBar(context, 'ادخل كلمة المرور');
      return;
    }
    if (newPassword.length < 6) {
      showSnackBar(context, 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      final googleSignIn = GoogleSignIn();
      final googleUser =
          await googleSignIn.signInSilently() ?? await googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final googleCred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(googleCred);

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: newEmail)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        if (mounted) {
          showSnackBar(context, 'هذا البريد مستخدم بالفعل في حساب آخر');
          setState(() => _isLoading = false);
        }
        return;
      }

      final emailCred = EmailAuthProvider.credential(
        email: newEmail,
        password: newPassword,
      );
      await user.linkWithCredential(emailCred);
      debugPrint('✅ Email/Password provider linked');

      await user.unlink('google.com');
      debugPrint('✅ Google provider unlinked');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'email': newEmail});

      await CacheManager.clearUser();
      await FirebaseAuth.instance.signOut();
      await googleSignIn.signOut(); 

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
        showSnackBar(
          context,
          'تم الفصل بنجاح! سجّل الدخول بالبريد وكلمة المرور',
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ FirebaseAuthException: ${e.code} — ${e.message}');
      final message = switch (e.code) {
        'email-already-in-use' => 'البريد مستخدم بالفعل في حساب آخر',
        'invalid-email' => 'البريد غير صحيح',
        'weak-password' => 'كلمة المرور ضعيفة جداً (6 أحرف على الأقل)',
        'requires-recent-login' => 'يرجى تسجيل الخروج والدخول مجدداً',
        'provider-already-linked' =>
          'هذا البريد مربوط بالفعل، جرب بريداً آخر',
        'credential-already-in-use' =>
          'هذا البريد مستخدم في حساب آخر',
        _ => 'حدث خطأ: ${e.code}',
      };
      if (mounted) {
        showSnackBar(context, message);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        showSnackBar(context, 'حدث خطأ غير متوقع، حاول مرة أخرى');
        setState(() => _isLoading = false);
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Icon(Icons.link_off, size: 54, color: Colors.white),
                  const SizedBox(height: 20),
                  const Text(
                    'فصل حساب Google',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'أدخل البريد الإلكتروني وكلمة المرور الجديدة\nسيتم فصل حسابك عن Google فوراً',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Email ──
                  const Text(
                    'البريد الإلكتروني الجديد',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF74E278),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'example@email.com',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1C1B2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Password ──
                  const Text(
                    'كلمة المرور الجديدة',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF74E278),
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1C1B2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Warning ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'بعد الفصل لن تتمكن من الدخول بحساب Google — ستستخدم البريد وكلمة المرور فقط',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Button ──
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color.fromARGB(230, 255, 255, 255),
                    foregroundColor: const Color(0xFF0F0E17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'فصل الحساب',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}