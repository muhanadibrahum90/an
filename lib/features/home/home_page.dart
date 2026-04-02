import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:aan/features/profile/profile_page.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/features/home/feed_page.dart';
import 'package:aan/features/posts/create_post_page.dart';
import 'package:aan/features/notifications/notifications_page.dart';
import 'package:aan/features/search/search_page.dart';
import 'package:aan/features/chat/chats_list_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:aan/features/banned/banned_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  Stream<int>? _unreadStream;
  Stream<int>? _unreadMessagesStream;
  bool _isBannedNavigating = false;

  @override
  void initState() {
    super.initState();
    _checkBanned();

    final uid = FirebaseAuth.instance.currentUser!.uid;
    _unreadStream = FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
    _unreadMessagesStream = FirebaseDatabase.instance
        .ref('userChats/$uid')
        .onValue
        .asBroadcastStream()
        .asyncMap((event) async {
          final data = event.snapshot.value;
          if (data == null) return 0;

          final chatIds = Map<String, dynamic>.from(data as Map).keys.toList();
          int total = 0;

          for (final chatId in chatIds) {
            final snap = await FirebaseDatabase.instance
                .ref('chats/$chatId/info/unreadCount/$uid')
                .get();
            total += (snap.value as int? ?? 0);
          }

          return total;
        });
  }

  Future<void> _checkBanned() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;


    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((
      doc,
    ) {
      final data = doc.data();
      final isBanned = data?['isBanned'] as bool? ?? false;
      if (isBanned && mounted && !_isBannedNavigating) {
        _isBannedNavigating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const BannedPage()),
            (route) => false,
          );
        });
      }
    });
  }

  Widget _buildAvatar(BuildContext context, String photoUrl) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        ),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Colors.transparent,
          child: photoUrl.isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const Icon(Icons.person, size: 18, color: Colors.white),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.person, size: 18, color: Colors.white),
                  ),
                )
              : const Icon(Icons.person, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadPhoto(String uid) async {
    final cached = CacheManager.getUser();
    if (cached != null) return cached;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = Map<String, dynamic>.from(doc.data() ?? {});
    if (data.isNotEmpty) await CacheManager.saveUser(data);

    return data;
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context, String uid) {
    if (_currentIndex == 1) return null;

    if (_currentIndex == 2) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0F0E17),
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: FutureBuilder<Map<String, dynamic>>(
          future: _loadPhoto(uid),
          builder: (context, snapshot) {
            final photoUrl = snapshot.data?['photoUrl'] ?? '';
            return _buildAvatar(context, photoUrl);
          },
        ),
        title: const Text(
          'التنبيهات',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      );
    }

    if (_currentIndex == 3) {
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0F0E17),
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: FutureBuilder<Map<String, dynamic>>(
          future: _loadPhoto(uid),
          builder: (context, snapshot) {
            final photoUrl = snapshot.data?['photoUrl'] ?? '';
            return _buildAvatar(context, photoUrl);
          },
        ),
        title: const Text(
          'الرسائل',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      );
    }

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: const Color(0xFF0F0E17),
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 60,
      leadingWidth: 60,
      leading: FutureBuilder<Map<String, dynamic>>(
        future: _loadPhoto(uid),
        builder: (context, snapshot) {
          final photoUrl = snapshot.data?['photoUrl'] ?? '';
          return _buildAvatar(context, photoUrl);
        },
      ),
      title: Image.asset(
        'assets/images/logoAppbar.png',
        height: 34,
        fit: BoxFit.contain,
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add, size: 28, color: Colors.white),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreatePostPage()),
            );
            if (result == true) setState(() {});
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: _buildAppBar(context, uid),

      body: IndexedStack(
        index: _currentIndex,
        children: const [
          FeedPage(),
          SearchPage(),
          NotificationsPage(),
          ChatsListPage(),
        ],
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A293D), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF0F0E17),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/home.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
              activeIcon: SvgPicture.asset(
                'assets/icons/home.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              label: 'الرئيسية',
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/search.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
              activeIcon: SvgPicture.asset(
                'assets/icons/search.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              label: 'البحث',
            ),
            BottomNavigationBarItem(
              icon: StreamBuilder<int>(
                stream: _unreadStream,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/notifications.svg',
                        width: 26,
                        colorFilter: const ColorFilter.mode(
                          Colors.grey,
                          BlendMode.srcIn,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -7,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF74E278),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              activeIcon: SvgPicture.asset(
                'assets/icons/notifications.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              label: 'الإشعارات',
            ),
            BottomNavigationBarItem(
              icon: StreamBuilder<int>(
                stream: _unreadMessagesStream,
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/messages.svg',
                        width: 26,
                        colorFilter: const ColorFilter.mode(
                          Colors.grey,
                          BlendMode.srcIn,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -7,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF74E278),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              activeIcon: SvgPicture.asset(
                'assets/icons/messages.svg',
                width: 26,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
              label: 'الرسائل',
            ),
          ],
        ),
      ),
    );
  }
}
