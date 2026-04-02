// lib/features/settings/message_privacy_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aan/services/snack_bar_service.dart';

class MessagePrivacyPage extends StatefulWidget {
  const MessagePrivacyPage({super.key});

  @override
  State<MessagePrivacyPage> createState() => _MessagePrivacyPageState();
}

class _MessagePrivacyPageState extends State<MessagePrivacyPage> {
  String _messagePrivacy = 'followers';
  bool _isLoading = true;
  bool _isSaving = false;
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();
    final value = doc.data()?['messagePrivacy'] as String? ?? 'followers';
    if (mounted) {
      setState(() {
        _messagePrivacy = value;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePrivacy(String value) async {
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('users').doc(_uid).update({
      'messagePrivacy': value,
    });
    if (mounted) {
      setState(() {
        _messagePrivacy = value;
        _isSaving = false;
      });
      showSnackBar(context, 'تم حفظ الإعداد');
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
        title: const Text(
          'إرسال الرسائل',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'من يمكنه مراسلتك؟',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),

                // ─── الخيارات ───
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1B2E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildOption(
                        value: 'followers',
                        title: 'المتابعون فقط',
                        subtitle: 'فقط من يتابعك يمكنه مراسلتك',
                        icon: Icons.people_outline,
                      ),
                      const Divider(
                        color: Color(0xFF2A293D),
                        height: 0,
                        thickness: 0.5,
                      ),
                      _buildOption(
                        value: 'nobody',
                        title: 'لا أحد',
                        subtitle: 'لن يتمكن أحد من مراسلتك',
                        icon: Icons.block_outlined,
                      ),
                    ],
                  ),
                ),

                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF74E278),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _messagePrivacy == value;

    return GestureDetector(
      onTap: _isSaving ? null : () => _savePrivacy(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF74E278) : Colors.grey,
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFF74E278)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
