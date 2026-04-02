import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../onboarding/welcome_page.dart';
import '../../services/cache_manager.dart';
import '../../features//settings/delete_account_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'reset_password_page.dart';
import '../profile/edit_profile_page.dart';
import 'change_email_page.dart';
import '../../features/settings/unlink_google_page.dart';
import '../../features/settings/message_privacy_page.dart';
import 'package:aan/services/snack_bar_service.dart';
import '../profile/profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _privateAccount = false;
  bool _notifyMessages = true;
  bool _notifyComments = true;
  bool _notifyFollowers = true;
  bool _darkMode = true;
  late final bool _isGoogleUser;

  late final List<_SettingsItem> _allItems;

  @override
  void initState() {
    super.initState();
    _isGoogleUser =
        FirebaseAuth.instance.currentUser?.providerData.any(
          (p) => p.providerId == 'google.com',
        ) ??
        false;
    _allItems = [
      _SettingsItem(title: 'تعديل الملف الشخصي', section: 'الحساب'),
      _SettingsItem(title: 'تعديل البريد الإلكتروني', section: 'الحساب'),
      _SettingsItem(title: 'تغيير كلمة المرور', section: 'الحساب'),
      _SettingsItem(title: 'حذف الحساب', section: 'الحساب'),
      _SettingsItem(title: 'حساب خاص', section: 'الخصوصية'),
      _SettingsItem(title: 'إشعارات الرسائل', section: 'الإشعارات'),
      _SettingsItem(title: 'إشعارات التعليقات', section: 'الإشعارات'),
      _SettingsItem(title: 'إشعارات المتابعين', section: 'الإشعارات'),
      _SettingsItem(title: 'الوضع الداكن', section: 'المظهر'),
      _SettingsItem(title: 'سياسة الخصوصية', section: 'الدعم'),
      _SettingsItem(title: 'شروط الاستخدام', section: 'الدعم'),
      _SettingsItem(title: 'تواصل معنا', section: 'الدعم'),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        surfaceTintColor: const Color(0xFF0F0E17),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'الإعدادات',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: isSearching ? _buildSearchResults() : _buildFullList(),
    );
  }

  Widget _buildSearchResults() {
    final results = _allItems
        .where((item) => item.title.contains(_searchQuery))
        .toList();

    if (results.isEmpty) {
      return const Center(
        child: Text('لا توجد نتائج', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return _buildSearchResultTile(item);
      },
    );
  }

  Widget _buildSearchResultTile(_SettingsItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A293D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(item.title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          item.section,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.grey,
          size: 14,
        ),
        onTap: () {},
      ),
    );
  }

  Widget _buildFullList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: TextField(
            controller: _searchController,
            cursorColor: const Color(0xFF74E278),
            style: const TextStyle(color: Colors.white),
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'البحث',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF1C1B2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        _buildSectionTitle('الحساب', 'assets/icons/user.svg'),
        _buildSection([
          _buildNavTile(
            icon: 'assets/icons/edit.svg',
            title: 'تعديل الملف الشخصي',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EditProfilePage(userData: {}),
              ),
            ),
          ),
          _buildDivider(),
          _buildNavTile(
            icon: 'assets/icons/messages.svg',
            title: 'تعديل البريد الإلكتروني',
            titleColor: _isGoogleUser ? Colors.grey : Colors.white,
            onTap: () {
              if (_isGoogleUser) {
                showSnackBar(
                  context,
                  'أنت مسجل بـ Google — لا يمكنك تغيير البريد الإلكتروني',
                );

                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangeEmailPage()),
              );
            },
          ),
          _buildDivider(),
          _buildNavTile(
            icon: 'assets/icons/lock.svg',
            title: 'تغيير كلمة المرور',
            titleColor: _isGoogleUser ? Colors.grey : Colors.white,
            onTap: () {
              if (_isGoogleUser) {
                showSnackBar(
                  context,
                  'أنت مسجل بـ Google — لا يمكنك تغيير كلمة السر',
                );

                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
              );
            },
          ),
          _buildDivider(),
          _buildNavTile(
            title: 'حذف الحساب',
            titleColor: Colors.red,
            iconColor: Colors.red,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
            ),
          ),
        ]),

        const SizedBox(height: 24),

        _buildSectionTitle('الخصوصية', 'assets/icons/privacy.svg'),
        _buildSection([
          _buildNavTile(
            icon: 'assets/icons/lock.svg',
            title: 'إرسال الرسائل',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MessagePrivacyPage()),
            ),
          ),
        ]),

        const SizedBox(height: 24),

        const SizedBox(height: 24),

        // ─── الدعم ───
        _buildSectionTitle('الدعم', 'assets/icons/support.svg'),
        _buildSection([
          _buildNavTile(
            title: 'سياسة الخصوصية',
            onTap: () => launchUrl(Uri.parse('https://aansocial.me/privacy')),
          ),
          _buildDivider(),
          _buildNavTile(
            title: 'شروط الاستخدام',
            onTap: () => launchUrl(Uri.parse('https://aansocial.me/terms')),
          ),
          _buildDivider(),
          _buildNavTile(
            title: 'تواصل معنا',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  uid: 'w6QxgnMxuAbfjYWQERGgmBGRqfE3',
                ), // ← ضع الـ uid هنا
              ),
            ),
          ),
        ]),

        const SizedBox(height: 24),

        _buildSection([
          _buildNavTile(
            icon: 'assets/icons/logout.svg',
            title: 'تسجيل الخروج',
            titleColor: Colors.red,
            iconColor: Colors.red,
            showArrow: false,
            onTap: () => _showLogoutDialog(),
          ),
        ]),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionTitle(String title, String iconPath) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4),
      child: Row(
        children: [
          SvgPicture.asset(
            iconPath,
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildNavTile({
    String? icon,
    required String title,
    required VoidCallback onTap,
    Color titleColor = Colors.white,
    Color iconColor = Colors.white,
    bool showArrow = true,
  }) {
    return ListTile(
      onTap: onTap,
      leading: icon != null
          ? Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2A293D),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: SvgPicture.asset(
                  icon,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
              ),
            )
          : null,
      title: Text(title, style: TextStyle(color: titleColor, fontSize: 15)),
      trailing: showArrow
          ? const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14)
          : null,
    );
  }

  Widget _buildSwitchTile({
    String? icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: icon != null
          ? Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2A293D),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: SvgPicture.asset(
                  icon,
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF74E278),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: const Color(0xFF2A293D),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      color: Color(0xFF2A293D),
      thickness: 0.5,
      indent: 60,
      height: 0,
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'تسجيل الخروج',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'هل أنت متأكد أنك تريد تسجيل الخروج؟',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({'fcmToken': null});
              }

              await FirebaseAuth.instance.signOut();
              await CacheManager.clearUser();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                  (route) => false,
                );
              }
            },
            child: const Text('خروج', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
    );
  }
}

class _SettingsItem {
  final String title;
  final String section;
  const _SettingsItem({required this.title, required this.section});
}
