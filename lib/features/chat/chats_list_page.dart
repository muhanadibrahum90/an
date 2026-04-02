import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/features/chat/chat_page.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:async';

class ChatsListPage extends StatefulWidget {
  const ChatsListPage({super.key});

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseDatabase.instance.ref();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<StreamSubscription> _subscriptions = [];

  static const int _pageSize = 20;
  List<Map<String, dynamic>> _allChats = [];
  List<Map<String, dynamic>> _filteredChats = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadChats();
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
        _applyFilter();
      });
    });
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 100 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreChats();
    }
  }

  List<Map<String, dynamic>> _parseChats(Map rawMap) {
    return rawMap.entries.map((e) {
      final chatData = Map<String, dynamic>.from(e.value as Map);
      final info = Map<String, dynamic>.from(chatData['info'] as Map? ?? {});
      final participants = Map<String, dynamic>.from(
        chatData['participants'] as Map? ?? {},
      );
      return {'chatId': e.key, 'participants': participants, ...info};
    }).toList()..sort((a, b) {
      final aTime = a['lastMessageTime'] as int? ?? 0;
      final bTime = b['lastMessageTime'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _loadChats() async {
    setState(() => _isLoading = true);

    final snap = await _db.child('userChats/$_uid').get();

    if (!mounted) return;

    if (snap.value == null) {
      setState(() {
        _isLoading = false;
        _hasMore = false;
      });
      return;
    }

    final chatIds = Map<String, dynamic>.from(snap.value as Map).keys.toList();

    final List<Map<String, dynamic>> chats = [];
    for (final chatId in chatIds) {
      final chatSnap = await _db.child('chats/$chatId/info').get();

      final participantsSnap = await _db
          .child('chats/$chatId/participants')
          .get();

      if (chatSnap.value != null) {
        final info = Map<String, dynamic>.from(chatSnap.value as Map);
        final participants = Map<String, dynamic>.from(
          participantsSnap.value as Map? ?? {},
        );
        chats.add({'chatId': chatId, 'participants': participants, ...info});
      } else {}
    }

    chats.sort((a, b) {
      final aTime = a['lastMessageTime'] as int? ?? 0;
      final bTime = b['lastMessageTime'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });

    if (!mounted) return;
    setState(() {
      _allChats = chats;
      _isLoading = false;
      _applyFilter();
    });

    _listenToUpdates();
  }

  Future<void> _loadMoreChats() async {
    if (_isLoadingMore || !_hasMore || _allChats.isEmpty) {
      return;
    }
    setState(() => _isLoadingMore = true);

    final snap = await _db.child('userChats/$_uid').get();

    if (!mounted) return;

    if (snap.value == null) {
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }

    final allIds = Map<String, dynamic>.from(snap.value as Map).keys.toList();

    final existingIds = _allChats.map((c) => c['chatId']).toSet();

    final remainingIds = allIds
        .where((id) => !existingIds.contains(id))
        .toList();

    if (remainingIds.isEmpty) {
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }

    final idsToLoad = remainingIds.take(_pageSize).toList();
    if (remainingIds.length <= _pageSize) _hasMore = false;

    final List<Map<String, dynamic>> more = [];
    for (final chatId in idsToLoad) {
      final chatSnap = await _db.child('chats/$chatId/info').get();
      final participantsSnap = await _db
          .child('chats/$chatId/participants')
          .get();
      if (chatSnap.value != null) {
        final info = Map<String, dynamic>.from(chatSnap.value as Map);
        final participants = Map<String, dynamic>.from(
          participantsSnap.value as Map? ?? {},
        );
        more.add({'chatId': chatId, 'participants': participants, ...info});
      }
    }

    if (!mounted) return;
    setState(() {
      _allChats.addAll(more);
      _allChats.sort((a, b) {
        final aTime = a['lastMessageTime'] as int? ?? 0;
        final bTime = b['lastMessageTime'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
      _isLoadingMore = false;
      _applyFilter();
    });
  }

  void _listenToUpdates() {
    for (final chat in _allChats) {
      final chatId = chat['chatId'] as String;

      final sub = _db.child('chats/$chatId/info').onValue.listen((event) {
        if (!mounted || event.snapshot.value == null) return;
        final info = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          final index = _allChats.indexWhere((c) => c['chatId'] == chatId);
          if (index != -1) {
            _allChats[index] = {..._allChats[index], ...info};
            _allChats.sort((a, b) {
              final aTime = a['lastMessageTime'] as int? ?? 0;
              final bTime = b['lastMessageTime'] as int? ?? 0;
              return bTime.compareTo(aTime);
            });
            _applyFilter();
          }
        });
      });

      _subscriptions.add(sub);
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredChats = List.from(_allChats);
    } else {
      _filteredChats = _allChats.where((chat) {
        final usersInfo = Map<String, dynamic>.from(
          chat['usersInfo'] as Map? ?? {},
        );
        final participants = Map<String, dynamic>.from(
          chat['participants'] as Map? ?? {},
        );
        final otherUid = participants.keys.firstWhere(
          (k) => k != _uid,
          orElse: () => '',
        );
        final otherInfo = Map<String, dynamic>.from(
          usersInfo[otherUid] as Map? ?? {},
        );
        final name = (otherInfo['displayName'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }
  }

  String _formatTime(int timestamp) {
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return '${diff.inMinutes}د';
    if (diff.inHours < 24) return '${diff.inHours}س';
    if (diff.inDays < 7) return '${diff.inDays}ي';
    return '${time.day}/${time.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1B2E),
                borderRadius: BorderRadius.circular(99),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  prefixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 18,
                          ),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : const Icon(Icons.search, color: Colors.grey, size: 20),
                ),
              ),
            ),
          ),

          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF74E278)),
      );
    }

    if (_filteredChats.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF74E278),
        backgroundColor: const Color(0xFF1C1B2E),
        onRefresh: _loadChats,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/messages.svg',
                      color: Colors.grey,
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'لا توجد نتائج'
                          : 'لا توجد محادثات',
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    if (_searchQuery.isEmpty) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'ابدأ محادثة من صفحة أي مستخدم',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF74E278),
      backgroundColor: const Color(0xFF1C1B2E),
      onRefresh: _loadChats,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredChats.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _filteredChats.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF74E278),
                  strokeWidth: 2,
                ),
              ),
            );
          }
          return _ChatTile(
            chat: _filteredChats[index],
            currentUid: _uid,
            formatTime: _formatTime,
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final String currentUid;
  final String Function(int) formatTime;

  const _ChatTile({
    required this.chat,
    required this.currentUid,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final chatId = chat['chatId'] as String? ?? '';
    final lastMessage = chat['lastMessage'] as String? ?? '';
    final lastTime = chat['lastMessageTime'] as int? ?? 0;
    final lastSender = chat['lastSender'] as String? ?? '';
    final lastType = chat['lastType'] as String? ?? 'text';

    final participants = Map<String, dynamic>.from(
      chat['participants'] as Map? ?? {},
    );
    final otherUid = participants.keys.firstWhere(
      (k) => k != currentUid,
      orElse: () => '',
    );

    final usersInfo = Map<String, dynamic>.from(
      chat['usersInfo'] as Map? ?? {},
    );
    final otherInfo = Map<String, dynamic>.from(
      usersInfo[otherUid] as Map? ?? {},
    );

    final otherName = otherInfo['displayName'] as String? ?? 'مستخدم';
    final otherPhoto = otherInfo['photoUrl'] as String? ?? '';

    final unreadRaw = chat['unreadCount'];
    int unreadCount = 0;
    if (unreadRaw is Map) {
      unreadCount = (unreadRaw[currentUid] as int? ?? 0);
    } else if (unreadRaw is int) {
      unreadCount = unreadRaw;
    }

    String lastMessageText;
    final isRead = (chat['lastIsRead'] as bool? ?? false);

    if (lastMessage.isEmpty && lastTime == 0) {
      lastMessageText = 'ابدأ المحادثة الآن 👋';
    } else if (lastSender == currentUid) {
      if (isRead) {
        lastMessageText = 'تمت المشاهدة';
      } else if (lastType == 'image') {
        lastMessageText = 'أرسلت صورة';
      } else {
        lastMessageText = lastMessage;
      }
    } else {
      if (lastType == 'image') {
        lastMessageText = 'أرسل صورة';
      } else {
        lastMessageText = lastMessage;
      }
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            otherUid: otherUid,
            otherName: otherName,
            otherPhotoUrl: otherPhoto,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF2A293D), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipOval(
                  child: otherPhoto.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: otherPhoto,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 54,
                          height: 54,
                          color: const Color(0xFF2A293D),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF74E278),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          otherName,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastTime > 0)
                        Text(
                          formatTime(lastTime),
                          style: TextStyle(
                            color: unreadCount > 0
                                ? const Color(0xFF74E278)
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastMessageText,
                    style: TextStyle(
                      color: unreadCount > 0 ? Colors.white70 : Colors.grey,
                      fontSize: 13,
                      fontWeight: unreadCount > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
