import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/features/profile/edit_profile_page.dart';
import 'package:aan/features/settings/settings_page.dart';
import 'package:aan/features/posts/create_post_page.dart';
import 'package:aan/features/posts/post_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:aan/features/chat/chat_page.dart';

class ProfilePage extends StatefulWidget {
  final String? uid;
  const ProfilePage({super.key, this.uid});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<Map<String, dynamic>>? _userDataFuture;
  Future<List<Map<String, dynamic>>>? _postsFuture;
  bool _isRefreshing = false;
  double _pullOffset = 0;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  int _followersCount = 0;
  bool _followersCountInitialized = false;
  String _profilePhotoUrl = '';
  String _messagePrivacy = 'followers';

  late String _profileUid;
  late bool _isMe;
  late Stream<DocumentSnapshot> _userStream;

  @override
  void initState() {
    super.initState();
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    _profileUid = widget.uid ?? currentUid;
    _isMe = _profileUid == currentUid;
    _userDataFuture = loadUserData(_profileUid);
    _postsFuture = _loadPosts(_profileUid);

    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(_profileUid)
        .snapshots();

    if (!_isMe) _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(_profileUid)
        .get();
    if (mounted) setState(() => _isFollowing = doc.exists);
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading) return;
    setState(() {
      _isFollowing = !_isFollowing;
      _isFollowLoading = true;
      _followersCount += _isFollowing ? 1 : -1;
    });

    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUid)
        .collection('following')
        .doc(_profileUid);
    final followerRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_profileUid)
        .collection('followers')
        .doc(currentUid);

    try {
      final batch = FirebaseFirestore.instance.batch();
      if (_isFollowing) {
        batch.set(followingRef, {'createdAt': FieldValue.serverTimestamp()});
        batch.set(followerRef, {'createdAt': FieldValue.serverTimestamp()});
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(_profileUid),
          {'followersCount': FieldValue.increment(1)},
        );
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(currentUid),
          {'followingCount': FieldValue.increment(1)},
        );

        final notifRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc(_profileUid)
            .collection('items')
            .doc(currentUid);

        final myDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .get();
        final myData = myDoc.data() ?? {};

        batch.set(notifRef, {
          'type': 'follow',
          'fromUid': currentUid,
          'fromUsername': myData['username'] ?? '',
          'fromPhoto': myData['photoUrl'] ?? '',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.delete(followingRef);
        batch.delete(followerRef);
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(_profileUid),
          {'followersCount': FieldValue.increment(-1)},
        );
        batch.update(
          FirebaseFirestore.instance.collection('users').doc(currentUid),
          {'followingCount': FieldValue.increment(-1)},
        );
        final notifRef = FirebaseFirestore.instance
            .collection('notifications')
            .doc(_profileUid)
            .collection('items')
            .doc(currentUid);

        batch.delete(notifRef);
      }
      await batch.commit();
    } catch (e) {
      if (mounted)
        setState(() {
          _isFollowing = !_isFollowing;
          _followersCount += _isFollowing ? 1 : -1; // ✅
        });
    } finally {
      if (mounted) setState(() => _isFollowLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadPosts(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Widget _buildActionBtn(String assetPath, VoidCallback onTap) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(9),
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          child: SvgPicture.asset(
            assetPath,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfo(
    String name,
    String username,
    String bio,
    int followersCount,
    int followingCount,
    int postsCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '@$username',
                style: const TextStyle(color: Colors.grey, fontSize: 15),
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  bio,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildStat(followersCount, 'متابعون'),
              const SizedBox(width: 20),
              _buildStat(followingCount, 'متابع'),
              const SizedBox(width: 20),
              _buildStat(postsCount, 'منشور'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_isMe) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (_isFollowing && _messagePrivacy != 'nobody') ...[
                  Expanded(
                    flex: 7,
                    child: GestureDetector(
                      onTap: () async {
                        final myData = CacheManager.getUser();
                        final myName = myData?['name'] ?? '';
                        final myPhoto = myData?['photoUrl'] ?? '';

                        final sorted = [
                          FirebaseAuth.instance.currentUser!.uid,
                          _profileUid,
                        ]..sort();
                        final chatId = '${sorted[0]}_${sorted[1]}';

                        final currentUid =
                            FirebaseAuth.instance.currentUser!.uid;

                        await FirebaseDatabase.instance.ref().update({
                          'chats/$chatId/participants/$currentUid': true,
                          'chats/$chatId/participants/$_profileUid': true,
                          'chats/$chatId/info/usersInfo/$currentUid/displayName':
                              myName,
                          'chats/$chatId/info/usersInfo/$currentUid/photoUrl':
                              myPhoto,
                          'chats/$chatId/info/usersInfo/$_profileUid/displayName':
                              name,
                          'chats/$chatId/info/usersInfo/$_profileUid/photoUrl':
                              _profilePhotoUrl,
                          'chats/$chatId/info/lastMessage': '',
                          'chats/$chatId/info/lastMessageTime': 0,
                          'userChats/$currentUid/$chatId': true,
                          'userChats/$_profileUid/$chatId': true,
                        });

                        debugPrint('✅ update done');

                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              chatId: chatId,
                              otherUid: _profileUid,
                              otherName: name,
                              otherPhotoUrl: _profilePhotoUrl,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF74E278),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/messages.svg',
                              color: const Color.fromARGB(255, 19, 18, 18),
                              width: 16,
                              height: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'مراسلة',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                Expanded(
                  flex: _isFollowing ? 3 : 10,
                  child: GestureDetector(
                    onTap: () async {
                      if (_isFollowing) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1C1B2E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            title: Text(
                              'إلغاء متابعة @$username',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Text(
                              'لن ترى منشورات @$username في موجزك بعد الآن.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text(
                                  'إلغاء',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'إلغاء المتابعة',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) _toggleFollow();
                      } else {
                        _toggleFollow();
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 38,
                      decoration: BoxDecoration(
                        color: _isFollowing
                            ? Colors.transparent
                            : const Color(0xFF74E278),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isFollowing
                              ? Colors.grey
                              : const Color(0xFF74E278),
                        ),
                      ),
                      child: Center(
                        child: _isFollowLoading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _isFollowing
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              )
                            : Text(
                                _isFollowing ? 'متابَع' : 'متابعة',
                                style: TextStyle(
                                  color: _isFollowing
                                      ? Colors.grey
                                      : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Divider(color: Color(0xFF2A293D), thickness: 0.5),
      ],
    );
  }

  Future<Map<String, dynamic>> loadUserData(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    if (_isMe && data.isNotEmpty) await CacheManager.saveUser(data);
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _userDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final data = snapshot.data ?? {};

          final name = data?['name'] ?? '';
          final username = data?['username'] ?? '';
          final bio = data?['bio'] ?? '';
          final photoUrl = data['photoUrl'] as String? ?? '';
          final coverUrl = data?['coverUrl'] ?? '';
          final followersCount = data?['followersCount'] ?? 0;
          final followingCount = data?['followingCount'] ?? 0;
          final postsCount = data?['postsCount'] ?? 0;
          _messagePrivacy = data['messagePrivacy'] as String? ?? 'followers';

          _profilePhotoUrl = photoUrl;

          return NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                backgroundColor: const Color(0xFF0F0E17),
                surfaceTintColor: const Color(0xFF0F0E17),
                elevation: 0,
                pinned: true,
                expandedHeight: 140,

                leadingWidth: 70,
                leading: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                actions: _isMe
                    ? [
                        _buildActionBtn('assets/icons/edit.svg', () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditProfilePage(userData: data),
                            ),
                          );
                          if (updated != null) {
                            setState(() {
                              _userDataFuture = loadUserData(uid);
                            });
                          }
                        }),
                        const SizedBox(width: 8),
                        _buildActionBtn('assets/icons/settings.svg', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsPage(),
                            ),
                          );
                        }),
                        const SizedBox(width: 12),
                      ]
                    : [],

                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 150,
                        color: const Color(0xFF74E278),
                        child: coverUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 150,
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                              )
                            : null,
                      ),
                      Positioned(
                        top: 130,
                        left: 0,
                        right: 0,
                        bottom: -1,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F0E17),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(30),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        top: 94,
                        right: 18,
                        child: CircleAvatar(
                          radius: 38,
                          backgroundColor: const Color(0xFF0F0E17),
                          child: photoUrl.isNotEmpty
                              ? ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: photoUrl,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.white,
                                    ),

                                    errorWidget: (context, url, error) =>
                                        const Icon(
                                          Icons.person,
                                          size: 40,
                                          color: Colors.white,
                                        ),
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 42,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: FutureBuilder<List<Map<String, dynamic>>>(
              future: _postsFuture,
              builder: (context, postsSnapshot) {
                if (postsSnapshot.connectionState == ConnectionState.waiting) {
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildProfileInfo(
                          name,
                          username,
                          bio,
                          followersCount,
                          followingCount,
                          postsCount,
                        ),
                      ),

                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ],
                  );
                }

                final posts = postsSnapshot.data ?? [];

                return RefreshIndicator(
                  color: const Color(0xFF74E278),
                  backgroundColor: const Color(0xFF1C1B2E),
                  onRefresh: () async {
                    setState(() {
                      _postsFuture = _loadPosts(_profileUid);
                    });
                    await _postsFuture;
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildProfileInfo(
                          name,
                          username,
                          bio,
                          followersCount,
                          followingCount,
                          postsCount,
                        ),
                      ),
                      posts.isEmpty
                          ? SliverFillRemaining(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'لا توجد منشورات بعد',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'أضف أول منشور لك الآن',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.only(bottom: 80),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) =>
                                      PostCard(post: posts[index]),
                                  childCount: posts.length,
                                ),
                              ),
                            ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _isMe
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreatePostPage()),
                );
                if (result == true) {
                  setState(() {
                    _postsFuture = _loadPosts(uid);
                  });
                }
              },
              backgroundColor: const Color(0xFF74E278),
              shape: const CircleBorder(),
              child: const Icon(
                Icons.add,
                color: Color.fromARGB(204, 255, 255, 255),
                size: 30,
              ),
            )
          : null,
    );
  }

  Widget _buildStat(int count, String label) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${formatCount(count)} ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              color: Color.fromARGB(197, 224, 224, 224),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

String formatCount(int count) {
  if (count >= 1000000) {
    double result = count / 1000000;
    return result.toStringAsFixed(result.truncateToDouble() == result ? 0 : 1) +
        " مليون";
  } else if (count >= 1000) {
    double result = count / 1000;
    return result.toStringAsFixed(result.truncateToDouble() == result ? 0 : 1) +
        " ألف";
  } else {
    return count.toString();
  }
}
