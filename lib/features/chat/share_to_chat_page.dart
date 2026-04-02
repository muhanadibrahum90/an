import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/services/snack_bar_service.dart';

class ShareToChatPage extends StatefulWidget {
  final String postId;
  const ShareToChatPage({super.key, required this.postId});

  @override
  State<ShareToChatPage> createState() => _ShareToChatPageState();
}

class _ShareToChatPageState extends State<ShareToChatPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseDatabase.instance.ref();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allChats = [];
  List<Map<String, dynamic>> _filteredChats = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _sendingChatId;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
        _applyFilter();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final snap = await _db.child('userChats/$_uid').get();
    if (!mounted) return;

    if (snap.value == null) {
      setState(() => _isLoading = false);
      return;
    }

    final chatIds = Map<String, dynamic>.from(snap.value as Map).keys.toList();
    final List<Map<String, dynamic>> chats = [];

    final idsToLoad = chatIds.take(10).toList();

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
        chats.add({'chatId': chatId, 'participants': participants, ...info});
      }
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

  Future<void> _sendPost(Map<String, dynamic> chat) async {
    final chatId = chat['chatId'] as String;
    final participants = Map<String, dynamic>.from(
      chat['participants'] as Map? ?? {},
    );
    final otherUid = participants.keys.firstWhere(
      (k) => k != _uid,
      orElse: () => '',
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final msgRef = _db.child('chats/$chatId/messages').push();

    if (_sendingChatId != null) return;
    setState(() => _sendingChatId = chatId);

    await msgRef.set({
      'senderId': _uid,
      'text': '',
      'imageUrl': '',
      'type': 'post',
      'postId': widget.postId,
      'isRead': false,
      'createdAt': now,
    });

    await _db.child('chats/$chatId/info').update({
      'lastMessage': '📎 منشور',
      'lastMessageTime': now,
      'lastSender': _uid,
      'lastIsRead': false,
      'lastType': 'post',
      'unreadCount/$otherUid': ServerValue.increment(1),
    });
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .update({'shareCount': FieldValue.increment(1)});

    if (mounted) {
      setState(() => _sendingChatId = null);

      Navigator.pop(context);
      showSnackBar(context, 'تم الإرسال ');
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'مشاركة في محادثة',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
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

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF74E278)),
                  )
                : _filteredChats.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد محادثات',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = _filteredChats[index];

                      final chatId = chat['chatId'] as String;

                      final participants = Map<String, dynamic>.from(
                        chat['participants'] as Map? ?? {},
                      );
                      final otherUid = participants.keys.firstWhere(
                        (k) => k != _uid,
                        orElse: () => '',
                      );
                      final usersInfo = Map<String, dynamic>.from(
                        chat['usersInfo'] as Map? ?? {},
                      );
                      final otherInfo = Map<String, dynamic>.from(
                        usersInfo[otherUid] as Map? ?? {},
                      );
                      final name =
                          otherInfo['displayName'] as String? ?? 'مستخدم';
                      final photo = otherInfo['photoUrl'] as String? ?? '';

                      return ListTile(
                        leading: ClipOval(
                          child: photo.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: photo,
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 46,
                                  height: 46,
                                  color: const Color(0xFF2A293D),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: GestureDetector(
                          onTap: _sendingChatId != null
                              ? null
                              : () => _sendPost(chat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF74E278),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: _sendingChatId == chatId
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'إرسال',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
