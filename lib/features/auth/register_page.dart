import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aan/features/profile_setup/name_page.dart';
import 'package:aan/services/google_auth_service.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aan/services/snack_bar_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool isLoading = false;
  bool _obscurePassword = true;

  Future<void> _signInWithGoogle() async {
    setState(() => isLoading = true);
    try {
      final result = await GoogleAuthService.handle();

      if (!mounted) return;

      switch (result) {
        case GoogleAuthService.resultLogin:
          await FirebaseAuth.instance.signOut();
          showSnackBar(context, 'هذا البريد مسجل بالفعل');
          break;

        case GoogleAuthService.resultRegister:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NamePage(
                email: GoogleAuthService.newUserEmail ?? '',
                password: '',
                name: GoogleAuthService.newUserName ?? '',
                isGoogleSignIn: true,
              ),
            ),
          );
          break;

        case GoogleAuthService.resultCancelled:
          break;
      }
    } catch (e) {
      showSnackBar(context, 'فشل: $e', isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        elevation: 0,
        title: const Text("إنشاء حساب"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: "البريد الإلكتروني",
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
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: "كلمة المرور",
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
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
                onPressed: () {
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();
                  if (email.isEmpty || password.isEmpty) {
                    showSnackBar(context, 'الرجاء ملء جميع الحقول');

                    return;
                  }
                  if (password.length < 6) {
                    showSnackBar(
                      context,
                      'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
                    );

                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NamePage(email: email, password: password),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(230, 255, 255, 255),
                  foregroundColor: const Color(0xFF1F1E2C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: const Text(
                  "التالي",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider(color: Colors.white24)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text("أو", style: TextStyle(color: Colors.white38)),
                ),
                const Expanded(child: Divider(color: Colors.white24)),
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
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/google.svg',
                            height: 20,
                            width: 20,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            "المتابعة باستخدام Google",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ✅ نص الموافقة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    height: 1.6,
                  ),
                  children: [
                    const TextSpan(text: 'بالمتابعة فإنك توافق على '),
                    TextSpan(
                      text: 'شروط الاستخدام',
                      style: const TextStyle(
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => launchUrl(
                          Uri.parse('https://aansocial.me/terms'),
                          mode: LaunchMode.externalApplication,
                        ),
                    ),
                    const TextSpan(text: ' و'),
                    TextSpan(
                      text: 'سياسة الخصوصية',
                      style: const TextStyle(
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => launchUrl(
                          Uri.parse('https://aansocial.me/privacy'),
                          mode: LaunchMode.externalApplication,
                        ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
