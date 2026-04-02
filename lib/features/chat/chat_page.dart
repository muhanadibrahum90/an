// lib/features/chat/chat_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aan/features/profile/profile_page.dart';
import 'package:aan/features/posts/post_detail_page.dart';
import 'package:aan/services/snack_bar_service.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String otherName;
  final String otherPhotoUrl;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.otherUid,
    required this.otherName,
    required this.otherPhotoUrl,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseDatabase.instance.ref();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _isSending = false;
  List<File> _selectedImages = [];

  static const int _pageSize = 20;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _oldestKey;
  bool _isInitialLoading = true;
  bool _isBlocked = false;
  String _blockedByName = '';
  bool _iBlockedThem = false;

  String get _chatRef => 'chats/${widget.chatId}';

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _loadInitialMessages();
    _scrollCtrl.addListener(_onScroll);
    _listenToBlockStatus();
  }

  @override
  void dispose() {
    _markAsRead();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels <= 100 && !_isLoadingMore && _hasMore) {
      _loadMoreMessages();
    }
  }

void _listenToBlockStatus() {
  _db.child('$_chatRef/info/blockedBy').onValue.listen((event) {
    if (!mounted) return;
    final data = event.snapshot.value;
    if (data == null) {
      setState(() {
        _isBlocked = false;
        _iBlockedThem = false;
      });
      return;
    }
    final map = Map<String, dynamic>.from(data as Map);
    setState(() {
      _iBlockedThem = map[_uid] == true;              // أنا من حظر
      _isBlocked = map[widget.otherUid] == true;      // الطرف الآخر حظرني
    });
  });
}

  Future<void> _markAsRead() async {
    await _db.child('$_chatRef/info/unreadCount/$_uid').set(0);

    final snap = await _db.child('$_chatRef/info/lastSender').get();
    final lastSender = snap.value as String? ?? '';
    if (lastSender != _uid) {
      await _db.child('$_chatRef/info/lastIsRead').set(true);
    }

    final messagesSnap = await _db
        .child('$_chatRef/messages')
        .orderByChild('senderId')
        .equalTo(widget.otherUid)
        .get();

    if (messagesSnap.value != null) {
      final map = Map<String, dynamic>.from(messagesSnap.value as Map);
      final updates = <String, dynamic>{};
      for (final entry in map.entries) {
        final msg = Map<String, dynamic>.from(entry.value as Map);
        if (msg['isRead'] == false) {
          updates['$_chatRef/messages/${entry.key}/isRead'] = true;
        }
      }
      if (updates.isNotEmpty) {
        await _db.update(updates);
      }
    }
  }

  // تحميل اخر 20 رسالة
  Future<void> _loadInitialMessages() async {
    final snap = await _db
        .child('$_chatRef/messages')
        .orderByChild('createdAt')
        .limitToLast(_pageSize)
        .get();

    if (!mounted) return;

    if (snap.value == null) {
      setState(() {
        _hasMore = false;
        _isInitialLoading = false;
      });
      return;
    }

    final map = Map<String, dynamic>.from(snap.value as Map);
    final list =
        map.entries.map((e) {
          final msg = Map<String, dynamic>.from(e.value as Map);
          return {'id': e.key, ...msg};
        }).toList()..sort(
          (a, b) => (a['createdAt'] as int).compareTo(b['createdAt'] as int),
        );

    if (list.isNotEmpty) _oldestKey = list.first['id'] as String;
    if (list.length < _pageSize) _hasMore = false;

    setState(() {
      _messages = list;
      _isInitialLoading = false; // ✅
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });

    _listenToNewMessages();
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _oldestKey == null) return;
    setState(() => _isLoadingMore = true);

    final snap = await _db
        .child('$_chatRef/messages')
        .orderByKey()
        .endBefore(_oldestKey)
        .limitToLast(_pageSize)
        .get();

    if (!mounted) return;

    if (snap.value == null) {
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
      return;
    }

    final map = Map<String, dynamic>.from(snap.value as Map);
    final list =
        map.entries.map((e) {
          final msg = Map<String, dynamic>.from(e.value as Map);
          return {'id': e.key, ...msg};
        }).toList()..sort(
          (a, b) => (a['createdAt'] as int).compareTo(b['createdAt'] as int),
        );

    if (list.isNotEmpty) _oldestKey = list.first['id'] as String;
    if (list.length < _pageSize) _hasMore = false;

    final oldOffset = _scrollCtrl.position.pixels;
    final oldMax = _scrollCtrl.position.maxScrollExtent;

    setState(() {
      _messages = [...list, ..._messages];
      _isLoadingMore = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        final newMax = _scrollCtrl.position.maxScrollExtent;
        _scrollCtrl.jumpTo(oldOffset + (newMax - oldMax));
      }
    });
  }

  void _listenToNewMessages() {
    final lastTime = _messages.isNotEmpty
        ? _messages.last['createdAt'] as int
        : 0;

    _db
        .child('$_chatRef/messages')
        .orderByChild('createdAt')
        .startAfter(lastTime)
        .onChildAdded
        .listen((event) {
          if (!mounted) return;

          final alreadyExists = _messages.any(
            (m) => m['id'] == event.snapshot.key,
          );
          if (alreadyExists) return;

          final msg = Map<String, dynamic>.from(event.snapshot.value as Map);
          final newMsg = {'id': event.snapshot.key, ...msg};

          setState(() => _messages.add(newMsg));
          _scrollToBottom();
        });
  }

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 3) return; // ← حد أقصى 3

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _selectedImages.add(File(picked.path)));
  }

  // رفع الصورة
  Future<String?> _uploadImage(File image) async {
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      final bytes = await image.readAsBytes();
      final base64 = base64Encode(bytes);
      final ext = image.path.split('.').last;
      final fileName = '${_uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final response = await http.post(
        Uri.parse('https://aan-upload.aan52907394.workers.dev/upload-chat'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'file': base64,
          'fileName': fileName,
          'contentType': 'image/$ext',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      }
    } catch (e) {}
    return null;
  }

  Future<void> _sendMessage() async {
    final text = _textCtrl.text.trim();
    if ((text.isEmpty && _selectedImages.isEmpty) || _isSending) return;

    setState(() => _isSending = true);
    _textCtrl.clear();

    final imagesToSend = List<File>.from(_selectedImages);
    setState(() => _selectedImages.clear());

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final hasImages = imagesToSend.isNotEmpty;

      if (imagesToSend.isNotEmpty) {
        for (final image in imagesToSend) {
          final url = await _uploadImage(image);
          if (url != null) {
            final msgRef = _db.child('$_chatRef/messages').push();
            final msgId = msgRef.key!;
            final imageCreatedAt = DateTime.now().millisecondsSinceEpoch;
            final newMsg = {
              'id': msgId,
              'senderId': _uid,
              'text': '',
              'imageUrl': url,
              'type': 'image',
              'isRead': false,
              'createdAt': imageCreatedAt,
            };

            if (mounted) setState(() => _messages.add(newMsg));
            await msgRef.set({
              'senderId': _uid,
              'text': '',
              'imageUrl': url,
              'type': 'image',
              'isRead': false,
              'createdAt': imageCreatedAt,
            });
          }
        }
      }

      if (text.isNotEmpty) {
        final msgRef = _db.child('$_chatRef/messages').push();
        final msgId = msgRef.key!;
        final newMsg = {
          'id': msgId,
          'senderId': _uid,
          'text': text,
          'imageUrl': '',
          'type': 'text',
          'isRead': false,
          'createdAt': now,
        };

        if (mounted) setState(() => _messages.add(newMsg));
        await msgRef.set({
          'senderId': _uid,
          'text': text,
          'imageUrl': '',
          'type': 'text',
          'isRead': false,
          'createdAt': now,
        });
      }

      await _db.child('$_chatRef/info').update({
        'lastMessage': hasImages ? '📷 صورة' : text,
        'lastMessageTime': now,
        'lastSender': _uid,
        'lastIsRead': false,
        'lastType': hasImages ? 'image' : 'text',
        'unreadCount/${widget.otherUid}': ServerValue.increment(1),
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'خطأ في الإرسال: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);

    int hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');

    String period = hour >= 12 ? 'م' : 'ص';

    hour = hour % 12;
    if (hour == 0) hour = 12;

    final h = hour.toString().padLeft(2, '0');

    return '$h:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0E17),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildMessagesList()),

            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0F0E17),
      surfaceTintColor: const Color(0xFF0F0E17),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfilePage(uid: widget.otherUid)),
        ),
        child: Row(
          children: [
            ClipOval(
              child: widget.otherPhotoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.otherPhotoUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      color: const Color(0xFF2A293D),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.otherName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: SvgPicture.asset(
            'assets/icons/Ellipsis.svg',
            width: 22,
            height: 22,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          onPressed: _showOptionsMenu,
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(0.5),
        child: Divider(color: Color(0xFF2A293D), height: 0.5),
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (!_iBlockedThem)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text(
                  'حظر',
                  style: TextStyle(color: Colors.red, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),

                title: const Text(
                  'إلغاء الحظر',
                  style: TextStyle(color: Colors.red, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _unblockUser();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _unblockUser() async {
    try {
      await _db.child('$_chatRef/info/blockedBy/$_uid').remove();
      if (mounted) showSnackBar(context, 'تم إلغاء الحظر');
    } catch (e) {
      if (mounted) showSnackBar(context, 'فشل إلغاء الحظر', isError: true);
    }
  }

  Future<void> _blockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B2E),
        title: const Text(
          'حظر المستخدم',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'هل تريد حظر ${widget.otherName}؟ لن يتمكن من إرسال رسائل إليك.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حظر', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _db.child('$_chatRef/info/blockedBy/$_uid').set(true);
      if (mounted) showSnackBar(context, 'تم الحظر');
    } catch (e) {
      if (mounted) showSnackBar(context, 'فشل الحظر', isError: true);
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      final snap = await _db.child('$_chatRef/messages/$messageId').get();

      if (snap.value != null) {
        final msg = Map<String, dynamic>.from(snap.value as Map);
        final imageUrl = msg['imageUrl'] as String? ?? '';
        final type = msg['type'] as String? ?? 'text';

        if (type == 'image' && imageUrl.isNotEmpty) {
          final key = _extractR2Key(imageUrl);
          if (key != null) await _deleteFromR2(key);
        }
      }

      await _db.child('$_chatRef/messages/$messageId').remove();

      if (mounted) {
        setState(() => _messages.removeWhere((msg) => msg['id'] == messageId));
      }

      await _updateLastMessage();
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'فشل الحذف', isError: true);
      }
    }
  }

  Future<void> _updateLastMessage() async {
    final snap = await _db
        .child('$_chatRef/messages')
        .orderByChild('createdAt')
        .limitToLast(1)
        .get();

    if (snap.value == null) {
      await _db.child('$_chatRef/info').update({
        'lastMessage': '',
        'lastMessageTime': 0,
        'lastSender': '',
        'lastType': 'text',
        'lastIsRead': false,
      });
      return;
    }

    final map = Map<String, dynamic>.from(snap.value as Map);
    final lastMsg = Map<String, dynamic>.from(map.values.first as Map);
    final type = lastMsg['type'] as String? ?? 'text';
    final sender = lastMsg['senderId'] as String? ?? '';

    await _db.child('$_chatRef/info').update({
      'lastMessage': type == 'image' ? '📷 صورة' : (lastMsg['text'] ?? ''),
      'lastMessageTime': lastMsg['createdAt'] ?? 0,
      'lastSender': sender,
      'lastType': type,
      'lastIsRead': lastMsg['isRead'] ?? false,
    });
  }

  String? _extractR2Key(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      return path.startsWith('/') ? path.substring(1) : path;
    } catch (_) {
      return null;
    }
  }

  Widget _buildProfileCard(Map<String, dynamic> info) {
    final name = info['displayName'] as String? ?? widget.otherName;
    final photo = info['photoUrl'] as String? ?? widget.otherPhotoUrl;
    final followersCount = info['followersCount'] as int? ?? 0;
    final followingCount = info['followingCount'] as int? ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfilePage(uid: widget.otherUid),
                ),
              ),
              child: ClipOval(
                child: photo.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photo,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 110,
                        height: 110,
                        color: const Color(0xFF2A293D),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),

            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              '@${info['username'] ?? ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatItem(followersCount, 'متابعون'),
                const SizedBox(width: 28),
                _buildStatItem(followingCount, 'متابَع'),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(int count, String label) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Future<void> _deleteFromR2(String key) async {
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      await http.post(
        Uri.parse(
          'https://aan-upload.aan52907394.workers.dev/delete-chat-image',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'key': key}),
      );
    } catch (e) {}
  }

  Widget _buildMessagesList() {
    if (_isInitialLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF74E278)),
      );
    }

    if (_messages.isEmpty) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUid)
            .get(),
        builder: (context, userSnap) {
          if (!userSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF74E278)),
            );
          }
          final info = userSnap.data?.data() as Map<String, dynamic>? ?? {};
          return _buildProfileCard(info);
        },
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoadingMore && index == 0) {
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

        final msgIndex = _isLoadingMore ? index - 1 : index;
        final msg = _messages[msgIndex];
        final isMe = msg['senderId'] == _uid;

        return _MessageBubble(
          isMe: isMe,
          text: msg['text'] as String? ?? '',
          imageUrl: msg['imageUrl'] as String? ?? '',
          type: msg['type'] as String? ?? 'text',
          time: _formatTime(msg['createdAt'] as int? ?? 0),
          messageId: msg['id'] as String? ?? '',
          createdAt: msg['createdAt'] as int? ?? 0,
          onDelete: () => _deleteMessage(msg['id'] as String? ?? ''),
          postId: msg['postId'] as String? ?? '',
        );
      },
    );
  }

  Widget _buildInputBar() {
    if (_isBlocked || _iBlockedThem) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0E17),
          border: Border(top: BorderSide(color: Color(0xFF2A293D), width: 0.5)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          top: 16,
        ),
        child: Text(
          _isBlocked
              ? 'قام $_blockedByName بحظرك، لا يمكنك إرسال الرسائل'
              : 'قمت بحظر ${widget.otherName}',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0E17),
        border: Border(top: BorderSide(color: Color(0xFF2A293D), width: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_selectedImages.isEmpty) ...[
            GestureDetector(
              onTap: _textCtrl.text.trim().isEmpty ? _pickImage : null,
              child: SvgPicture.asset(
                'assets/icons/Upimage.svg',
                width: 26,
                height: 26,
                colorFilter: ColorFilter.mode(
                  _textCtrl.text.trim().isEmpty
                      ? const Color(0xFF74E278)
                      : Colors.grey,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (_selectedImages.isEmpty)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1B2E),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: TextField(
                  controller: _textCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 2,
                  minLines: 1,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    hintText: 'اكتب رسالة...',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),

          if (_selectedImages.isNotEmpty) ...[
            Expanded(
              child: Row(
                children: [
                  ..._selectedImages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final image = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedImages.removeAt(index)),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                image,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  if (_selectedImages.length < 3)
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 52,
                        height: 52,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1B2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Color(0xFF74E278),
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(width: 8),

          GestureDetector(
            onTap:
                (_textCtrl.text.trim().isNotEmpty || _selectedImages.isNotEmpty)
                ? _sendMessage
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    (_textCtrl.text.trim().isNotEmpty ||
                        _selectedImages.isNotEmpty)
                    ? const Color(0xFF74E278)
                    : const Color(0xFF2A293D),
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(10),
                      child: SvgPicture.asset(
                        'assets/icons/send.svg',
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String text;
  final String imageUrl;
  final String type;
  final String time;
  final String messageId;
  final int createdAt;
  final VoidCallback onDelete;
  final String postId;

  const _MessageBubble({
    required this.isMe,
    required this.text,
    required this.imageUrl,
    required this.type,
    required this.time,
    required this.messageId,
    required this.createdAt,
    required this.onDelete,
    this.postId = '',
  });

  @override
  Widget build(BuildContext context) {
    final canDelete =
        isMe &&
        (DateTime.now().millisecondsSinceEpoch - createdAt.toInt()) <
            const Duration(hours: 1).inMilliseconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMe) ...[
            Text(
              time,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(width: 6),
          ],

          GestureDetector(
            onLongPress: canDelete ? () => _showDeleteDialog(context) : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color(0xFF74E278)
                      : const Color(0xFF1C1B2E),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (type == 'post') _PostPreview(postId: postId),

                    if (type == 'image' && imageUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            opaque: false,
                            barrierColor: Colors.black,
                            pageBuilder: (context, _, __) =>
                                _FullScreenImage(imageUrl: imageUrl),
                            transitionsBuilder:
                                (context, animation, _, child) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 220,
                            height: 220,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 220,
                              height: 220,
                              color: const Color(0xFF2A293D),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF74E278),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.black : Colors.white,
                            fontSize: 15,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          if (!isMe) ...[
            const SizedBox(width: 6),
            Text(
              time,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'حذف الرسالة',
                style: TextStyle(color: Colors.red, fontSize: 15),
              ),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatefulWidget {
  final String imageUrl;
  const _FullScreenImage({required this.imageUrl});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage> {
  final _transformController = TransformationController();
  bool _isDownloading = false;

  Future<void> _downloadImage() async {
    setState(() => _isDownloading = true);
    try {
      final response = await Dio().get(
        widget.imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/aan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(filePath);
      await file.writeAsBytes(response.data);
      await Gal.putImage(filePath);

      if (mounted) {
        showSnackBar(context, 'تم حفظ الصورة');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'فشل الحفظ', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),

                  GestureDetector(
                    onTap: _isDownloading ? null : _downloadImage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: _isDownloading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  final String postId;
  const _PostPreview({required this.postId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: 220,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF2A293D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF74E278),
                strokeWidth: 2,
              ),
            ),
          );
        }

        final post = snap.data?.data() as Map<String, dynamic>? ?? {};
        final text = post['text'] as String? ?? '';
        final media = List<String>.from(post['media'] as List? ?? []);
        final displayName = post['displayName'] as String? ?? '';
        final userPhoto = post['userPhoto'] as String? ?? '';

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailPage(
                post: {...post, 'postId': postId},
                isLiked: false,
                likeCount: post['likeCount'] ?? 0,
              ),
            ),
          ),
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0E17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A293D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipOval(
                      child: userPhoto.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: userPhoto,
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 24,
                              height: 24,
                              color: const Color(0xFF2A293D),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                if (text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    text,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                if (media.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: media.first,
                      width: double.infinity,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
