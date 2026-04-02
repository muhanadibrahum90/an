import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aan/features/auth/register_page.dart';
import 'package:aan/features/home/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aan/features/settings/reset_password_page.dart';
import 'package:aan/services/google_auth_service.dart';
import 'package:aan/services/snack_bar_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController loginController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  bool isLoading = false;
  bool isGoogleLoading = false;  // زر Google

  //دالة تسجيل  الدخول باليوزر
  Future<String> _resolveEmail(String input) async {
    if (input.contains('@')) return input;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: input.toLowerCase().trim())
        .limit(1)
        .get();

    if (snap.docs.isEmpty) throw Exception('اسم المستخدم غير موجود');
    return snap.docs.first.data()['email'] as String? ?? '';
  }

  Future<void> _login() async {
    final input = loginController.text.trim();
    final password = passwordController.text.trim();

    if (input.isEmpty || password.isEmpty) {
      showSnackBar(context, ' يرجى ملء جميع الحقول');
      return;
    }

    setState(() => isLoading = true);
    try {
      final email = await _resolveEmail(input);

      await _auth.signInWithEmailAndPassword(email: email, password: password);

      // ✅ تحديث البريد في Firestore إذا تغيّر
      final user = FirebaseAuth.instance.currentUser!;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.data()?['email'] != user.email) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'email': user.email});
      }

      final data = doc.data();
      if (data != null &&
          (data.containsKey('pendingEmail') ||
              data.containsKey('pendingPassword'))) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'pendingEmail': FieldValue.delete()});
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = switch (e.code) {
        'user-not-found' => 'الحساب غير موجود',
        'wrong-password' => 'كلمة المرور خاطئة',
        'invalid-credential' => 'البريد أو كلمة المرور غير صحيحة',
        'user-disabled' => 'هذا الحساب معطل',
        'too-many-requests' => 'محاولات كثيرة، حاول لاحقاً',
        _ => e.message ?? 'حدث خطأ',
      };
      if (mounted) showSnackBar(context, message, isError: true);
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context,
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => isGoogleLoading = true);
    try {
      final result = await GoogleAuthService.handle();

      if (!mounted) return;

      switch (result) {
        case GoogleAuthService.resultLogin:
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
          );
          break;

        case GoogleAuthService.resultRegister:
          await FirebaseAuth.instance.signOut();
          showSnackBar(context, 'هذا الحساب غير مسجل');
          break;

        case GoogleAuthService.resultCancelled:
          break;
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'فشل: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        elevation: 0,
        title: const Text("تسجيل الدخول"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),

            TextField(
              controller: loginController,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'البريد الإلكتروني أو اسم المستخدم',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A293D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'كلمة المرور',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2A293D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(230, 255, 255, 255),
                  foregroundColor: const Color(0xFF1F1E2C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'تسجيل الدخول',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider(color: Colors.white24)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('أو', style: TextStyle(color: Colors.white38)),
                ),
                Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: isLoading ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Color.fromARGB(230, 255, 255, 255),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/google.svg',
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'المتابعة باستخدام Google',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResetPasswordPage(),
                    ),
                  ),
                  child: const Text(
                    'نسيت كلمة المرور؟',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
