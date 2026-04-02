import 'dart:async';
import 'package:aan/features/onboarding/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/services/snack_bar_service.dart';

class VerifyNewEmailPage extends StatefulWidget {
  final String newEmail;

  const VerifyNewEmailPage({super.key, required this.newEmail});

  @override
  State<VerifyNewEmailPage> createState() => _VerifyNewEmailPageState();
}

class _VerifyNewEmailPageState extends State<VerifyNewEmailPage> {
  Timer? _cooldownTimer;
  bool _canResend = false;
  int _seconds = 30;
  bool _isVerifying = false;
  bool _isCancelling = false;

  late final String _savedUid;
  late final String _savedOldEmail;

  @override
  void initState() {
    super.initState();
    _savedUid = FirebaseAuth.instance.currentUser!.uid;
    _savedOldEmail = FirebaseAuth.instance.currentUser!.email ?? '';
    _startCooldown();
  }

  void _startCooldown() {
    if (!mounted) return;
    setState(() {
      _canResend = false;
      _seconds = 30;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds <= 0) {
        timer.cancel();
        if (mounted) setState(() => _canResend = true);
      }
    });
  }

  Future<void> _onVerified() async {
    setState(() => _isVerifying = true);
    try {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {}

      final user = FirebaseAuth.instance.currentUser;
      final currentEmail = user?.email;

      debugPrint('user: ${user?.uid}');
      debugPrint('currentEmail: $currentEmail');
      debugPrint('newEmail: ${widget.newEmail}');

      if (currentEmail == widget.newEmail) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .update({'email': widget.newEmail});
        } catch (e) {
          debugPrint('Firestore error: $e');
        }
        await CacheManager.clearUser();
        await FirebaseAuth.instance.signOut();
      } else if (user == null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_savedUid)
              .update({'email': widget.newEmail});
        } catch (e) {
          debugPrint('Firestore error: $e');
        }
        await CacheManager.clearUser();
      } else {
        if (mounted) {
          setState(() => _isVerifying = false);
          showSnackBar(
            context,
            'لم يتم التحقق بعد، افتح الرابط في بريدك أولاً',
          );
        }
        return;
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('error: $e');
      if (mounted) {
        setState(() => _isVerifying = false);
        showSnackBar(context, 'حدث خطأ، حاول مرة أخرى');
      }
    }
  }

  Future<void> _resend() async {
    try {
      await FirebaseAuth.instance.currentUser?.verifyBeforeUpdateEmail(
        widget.newEmail,
      );
      _startCooldown();
      if (mounted) {
        showSnackBar(context, 'تم إعادة الإرسال');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'فشل الإرسال');
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
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'تحقق من بريدك!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'أرسلنا رابط تأكيد إلى\n${widget.newEmail}\nافتح البريد واضغط على الرابط ثم ارجع هنا',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_isVerifying || _isCancelling) ? null : _onVerified,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF74E278),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'تم التحقق ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),

            const SizedBox(height: 24),

            TextButton(
              onPressed: _canResend ? _resend : null,
              child: Text(
                _canResend
                    ? 'إعادة إرسال الرابط'
                    : 'إعادة الإرسال بعد $_seconds ثانية',
                style: TextStyle(
                  color: _canResend ? Colors.white70 : Colors.grey,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
