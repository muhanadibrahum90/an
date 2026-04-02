// lib/features/notifications/notifications_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/features/profile/profile_page.dart';
import 'package:aan/features/posts/post_detail_page.dart';
import 'package:flutter_svg/svg.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _showAllOlder = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(_uid)
          .collection('items')
          .orderBy('createdAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _notifications = snapshot.docs.map((d) => d.data()).toList();
          _isLoading = false;
        });
      }
      _markAllAsRead();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openPost(String postId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PostDetailPage(post: doc.data()!)),
        );
      }
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    final batch = FirebaseFirestore.instance.batch();
    final unread = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(_uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .get();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Map<String, List<Map<String, dynamic>>> _groupNotifications() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final Map<String, List<Map<String, dynamic>>> groups = {
      'جديد': [],
      'اليوم': [],
      'الأمس': [],
      'سابقاً': [],
    };

    for (final notif in _notifications) {
      final isRead = notif['isRead'] ?? true;
      final createdAt = (notif['createdAt'] as Timestamp?)?.toDate();

      if (!isRead) {
        groups['جديد']!.add(notif);
      } else if (createdAt != null && createdAt.isAfter(todayStart)) {
        groups['اليوم']!.add(notif);
      } else if (createdAt != null && createdAt.isAfter(yesterdayStart)) {
        groups['الأمس']!.add(notif);
      } else {
        groups['سابقاً']!.add(notif);
      }
    }

    return groups;
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final time = timestamp.toDate();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}د';
    if (diff.inHours < 24) return '${diff.inHours}س';
    if (diff.inDays < 7) return '${diff.inDays}ي';
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : RefreshIndicator(
              color: const Color(0xFF74E278),
              backgroundColor: const Color(0xFF1C1B2E),
              onRefresh: _loadNotifications,
              child: _notifications.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'assets/icons/notifications.svg',
                                color: Colors.grey,
                                width: 40,
                                height: 40,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'لا توجد إشعارات بعد',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _buildGroupedList(),
            ),
    );
  }

  Widget _buildGroupedList() {
    final groups = _groupNotifications();
    final List<Widget> items = [];

    for (final section in ['جديد', 'اليوم', 'الأمس', 'سابقاً']) {
      final list = groups[section]!;
      if (list.isEmpty) continue;

      items.add(_buildSectionHeader(section));

      if (section == 'سابقاً' && !_showAllOlder) {
        final limited = list.take(5).toList();
        items.addAll(limited.map((n) => _buildNotification(n)));

        if (list.length > 5) {
          items.add(_buildShowMoreButton(list.length - 5));
        }
      } else {
        items.addAll(list.map((n) => _buildNotification(n)));
      }
    }

    return ListView(children: items);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildShowMoreButton(int remaining) {
    return GestureDetector(
      onTap: () => setState(() => _showAllOlder = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'رؤية $remaining إشعار أقدم',
          style: const TextStyle(
            color: Color(0xFF74E278),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildNotification(Map<String, dynamic> notif) {
    final type = notif['type'] ?? '';
    final fromUsername = notif['fromUsername'] ?? '';
    final fromPhoto = notif['fromPhoto'] ?? '';
    final fromUid = notif['fromUid'] ?? '';
    final isRead = notif['isRead'] ?? true;
    final createdAt = notif['createdAt'] as Timestamp?;
    final postText = notif['postText'] ?? '';
    final count = notif['count'] ?? 0;

    Widget content;

    if (type == 'follow') {
      content = RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '@$fromUsername ',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const TextSpan(
              text: 'بدأ في متابعتك',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    } else if (type == 'like_milestone') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حصل منشورك على $count إعجاب',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (postText.isNotEmpty)
            Text(
              postText,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    } else if (type == 'comment') {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '@$fromUsername ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const TextSpan(
                  text: 'أضاف رداً على منشورك',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
          if (postText.isNotEmpty)
            Text(
              postText,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    } else if (type == 'post_deleted_by_reports') {
      content = const Text(
        'تم حذف منشورك بسبب تجاوزه البلاغات التي تلقيناها',
        style: TextStyle(color: Colors.white, fontSize: 14),
      );
    } else {
      content = const SizedBox.shrink();
    }

    Widget avatar;
    if (type == 'like_milestone') {
      avatar = Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF2A293D),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.favorite, color: Color(0xFFE0245E), size: 24),
      );
    } else if (type == 'post_deleted_by_reports') {
      avatar = Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF2A293D),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
      );
    // ✅ بعد
} else {
  avatar = ClipOval(
    child: fromPhoto.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: fromPhoto,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => Container(
              width: 44,
              height: 44,
              color: const Color(0xFF2A293D),
              child: const Icon(Icons.person, color: Colors.white),
            ),
          )
        : Container(
            width: 44,
            height: 44,
            color: const Color(0xFF2A293D),
            child: const Icon(Icons.person, color: Colors.white),
          ),
  );
}

    return GestureDetector(
      onTap: () {
        if (type == 'follow') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfilePage(uid: fromUid)),
          );
        } else if (type == 'like_milestone' || type == 'comment') {
          final postId = notif['postId'] ?? '';
          if (postId.isNotEmpty) _openPost(postId);
        }
      },
      child: Container(
        color: isRead ? Colors.transparent : const Color(0xFF1C1B2E),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isRead
                          ? Colors.transparent
                          : const Color(0xFF74E278),
                    ),
                  ),
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: content),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(createdAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A293D), thickness: 0.5, height: 0),
          ],
        ),
      ),
    );
  }
}
