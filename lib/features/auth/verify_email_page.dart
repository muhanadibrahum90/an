import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aan/features/home/home_page.dart';
import 'package:aan/features/onboarding/welcome_page.dart';
import 'package:http/http.dart' as http;
import 'package:aan/services/snack_bar_service.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  Timer? _timer;
  Timer? _cooldownTimer;

  bool _canResend = true;
  int _seconds = 30;

  Future<void> _checkEmailVerified() async {
    if (!mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.reload();

      if (!mounted) return;
      final verified =
          FirebaseAuth.instance.currentUser?.emailVerified ?? false;

      if (verified && mounted) {
        _cooldownTimer?.cancel();
        showSnackBar(context, 'تم التحقق من بريدك بنجاح!');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      } else if (mounted) {
        showSnackBar(
          context,
          'لم يتم التحقق بعد، تحقق من بريدك الإلكتروني',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'حدث خطأ، حاول مجدداً', isError: true);
      }
    }
  }

  Future<void> _resendEmail() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();

      setState(() {
        _canResend = false;
        _seconds = 30;
      });

      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _seconds--);

        if (_seconds == 0) {
          timer.cancel();
          setState(() => _canResend = true);
        }
      });

      if (mounted) {
        showSnackBar(context, 'تم إعادة إرسال رابط التحقق');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          context,
          'فشل الإرسال، تحقق من اتصال الإنترنت',
          isError: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_unread_outlined,
              size: 80,
              color: Colors.white,
            ),

            const SizedBox(height: 24),

            const Text(
              'تحقق من بريدك الإلكتروني',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'أرسلنا رابط التحقق إلى\n$email\nتحقق من صندوق الوارد أو مجلد Spam',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canResend ? _resendEmail : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(230, 255, 255, 255),
                  foregroundColor: const Color(0xFF0F0E17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: Text(
                  _canResend ? 'إعادة إرسال الرابط' : 'انتظر $_seconds ثانية',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: _checkEmailVerified,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF74E278),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: const Text(
                'تحققت بالفعل',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 16),

            TextButton(
              onPressed: () async {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    final uid = user.uid;
                    final token = await user.getIdToken();

                    //حذف الصوره من R2
                    try {
                      await http.post(
                        Uri.parse(
                          'https://aan-upload.aan52907394.workers.dev/delete-profile-image',
                        ),
                        headers: {
                          'Authorization': 'Bearer $token',
                          'Content-Type': 'application/json',
                        },
                      );
                    } catch (e) {}

                    // ٢. حذف username من Firestore
                    final userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .get();

                    if (userDoc.exists) {
                      final username = userDoc.data()?['username'];
                      if (username != null) {
                        await FirebaseFirestore.instance
                            .collection('usernames')
                            .doc(username)
                            .delete();
                      }
                      await userDoc.reference.delete();
                    }

                    // ٣. حذف الحساب من Auth
                    await user.delete();
                  }
                } catch (e) {}

                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const WelcomePage()),
                    (route) => false,
                  );
                }
              },
              child: const Text(
                'استخدام حساب آخر',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
