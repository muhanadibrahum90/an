// lib/features/posts/post_detail_page.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/services/notification_service.dart';
import 'package:aan/features/chat/share_to_chat_page.dart';
import 'package:aan/services/snack_bar_service.dart';

class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isLiked;
  final int likeCount;

  const PostDetailPage({
    super.key,
    required this.post,
    this.isLiked = false,
    this.likeCount = 0,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _commentController = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isSending = false;
  late int _likeCount;
  bool _isLiked = false;
  late int _commentCount;
  static const int _commentPageSize = 15;
  bool _isLoadingMoreComments = false;
  bool _hasMoreComments = true;
  DocumentSnapshot? _lastCommentDoc;
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _commentsLoading = true;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likeCount = widget.likeCount;
    _commentCount = widget.post['commentCount'] ?? 0;
    _loadComments();
    _refreshPostStats();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollCtrl.dispose();

    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 100 &&
        !_isLoadingMoreComments &&
        _hasMoreComments) {
      _loadMoreComments();
    }
  }

  Future<void> _refreshPostStats() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post['postId'])
          .get();

      if (!mounted) return;

      final data = doc.data();
      if (data == null) return;

      final likeDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post['postId'])
          .collection('likes')
          .doc(_uid)
          .get();

      if (!mounted) return;

      setState(() {
        _likeCount = data['likeCount'] ?? _likeCount;
        _commentCount = data['commentCount'] ?? _commentCount;
        _isLiked = likeDoc.exists;
      });
    } catch (_) {}
  }

  Future<void> _checkIfLiked() async {
    final doc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post['postId'])
        .collection('likes')
        .doc(_uid)
        .get();
    if (mounted) setState(() => _isLiked = doc.exists);
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);

    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post['postId'])
        .collection('comments')
        .orderBy('likeCount', descending: true)
        .orderBy('createdAt', descending: false)
        .limit(_commentPageSize)
        .get();

    if (!mounted) return;

    final comments = await _attachLikeStatus(
      snapshot.docs.map((d) => {'commentId': d.id, ...d.data()}).toList(),
    );

    if (snapshot.docs.isNotEmpty) {
      _lastCommentDoc = snapshot.docs.last;
    }
    if (snapshot.docs.length < _commentPageSize) _hasMoreComments = false;

    setState(() {
      _comments = comments;
      _commentsLoading = false;
    });
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMoreComments || !_hasMoreComments || _lastCommentDoc == null)
      return;
    setState(() => _isLoadingMoreComments = true);

    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post['postId'])
        .collection('comments')
        .orderBy('likeCount', descending: true)
        .orderBy('createdAt', descending: false)
        .startAfterDocument(_lastCommentDoc!)
        .limit(_commentPageSize)
        .get();

    if (!mounted) return;

    final more = await _attachLikeStatus(
      snapshot.docs.map((d) => {'commentId': d.id, ...d.data()}).toList(),
    );

    if (snapshot.docs.isNotEmpty) _lastCommentDoc = snapshot.docs.last;
    if (snapshot.docs.length < _commentPageSize) _hasMoreComments = false;

    setState(() {
      _comments.addAll(more);
      _isLoadingMoreComments = false;
    });
  }

  Future<List<Map<String, dynamic>>> _attachLikeStatus(
    List<Map<String, dynamic>> comments,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (final comment in comments) {
      final likeDoc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post['postId'])
          .collection('comments')
          .doc(comment['commentId'])
          .collection('likes')
          .doc(_uid)
          .get();
      result.add({...comment, 'isLiked': likeDoc.exists});
    }
    return result;
  }

  Future<void> _toggleCommentLike(Map<String, dynamic> comment) async {
    final commentId = comment['commentId'] as String;
    final index = _comments.indexWhere((c) => c['commentId'] == commentId);
    if (index == -1) return;

    final isLiked = comment['isLiked'] as bool? ?? false;

    setState(() {
      _comments[index] = {
        ..._comments[index],
        'isLiked': !isLiked,
        'likeCount': (comment['likeCount'] as int? ?? 0) + (isLiked ? -1 : 1),
      };
    });

    final commentRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post['postId'])
        .collection('comments')
        .doc(commentId);

    try {
      if (isLiked) {
        await commentRef.collection('likes').doc(_uid).delete();
        await commentRef.update({'likeCount': FieldValue.increment(-1)});
      } else {
        await commentRef.collection('likes').doc(_uid).set({
          'uid': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await commentRef.update({'likeCount': FieldValue.increment(1)});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _comments[index] = {
            ..._comments[index],
            'isLiked': isLiked,
            'likeCount': comment['likeCount'],
          };
        });
      }
    }
  }

  Future<void> _toggleLike() async {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    final postRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.post['postId']);
    final likeRef = postRef.collection('likes').doc(_uid);

    try {
      if (!_isLiked) {
        await likeRef.delete();
        await postRef.update({'likeCount': FieldValue.increment(-1)});
      } else {
        await likeRef.set({
          'uid': _uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await postRef.update({'likeCount': FieldValue.increment(1)});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
      }
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    final postOwnerId = widget.post['uid'] as String? ?? '';

    if (_uid == postOwnerId) {
      final userCommentsSnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post['postId'])
          .collection('comments')
          .where('uid', isEqualTo: _uid)
          .count()
          .get();

      final userCommentCount = userCommentsSnapshot.count ?? 0;

      if (userCommentCount >= 3) {
        if (mounted) {
          showSnackBar(
            context,
            'لا يمكنك إضافة أكثر من 3 تعليقات على منشورك',
            isError: true,
          );
        }
        return;
      }
    }

    setState(() => _isSending = true);

    try {
      final userData = CacheManager.getUser();
      final postId = widget.post['postId'];
      final postRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(postId);
      final commentRef = postRef.collection('comments').doc();

      final comment = {
        'commentId': commentRef.id,
        'uid': _uid,
        'username': userData?['username'] ?? '',
        'userPhoto': userData?['photoUrl'] ?? '',
        'displayName': userData?['name'] ?? '',
        'text': text,
        'likeCount': 0,
        'createdAt': Timestamp.now(),
      };

      setState(() {
        _comments.add(comment);
        _commentController.clear();
        _commentCount++;
      });
      FocusScope.of(context).unfocus();

      await commentRef.set({
        ...comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await postRef.update({'commentCount': FieldValue.increment(1)});
      await NotificationService.sendCommentNotification(
        postOwnerUid: widget.post['uid'],
        postId: widget.post['postId'],
        postText: widget.post['text'] ?? '',
      );
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'حدث خطأ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  TextDirection _getTextDirection(String text) {
    final arabicRegex = RegExp(r'[\u0600-\u06FF]');
    return arabicRegex.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;
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

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}مليون';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}ألف';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final userPhoto = post['userPhoto'] ?? '';
    final displayName = post['displayName'] ?? '';
    final username = post['username'] ?? '';
    final text = post['text'] ?? '';
    final media = List<String>.from(post['media'] ?? []);
    final shareCount = post['shareCount'] ?? 0;
    final createdAt = post['createdAt'] as Timestamp?;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, {
          'isLiked': _isLiked,
          'likeCount': _likeCount,
          'commentCount': _commentCount,
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0E17),

        appBar: AppBar(
          backgroundColor: const Color(0xFF0F0E17),
          surfaceTintColor: const Color(0xFF0F0E17),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context, {
              'isLiked': _isLiked,
              'likeCount': _likeCount,
              'commentCount': _commentCount,
            }),
          ),
          title: const Text(
            'المنشور',
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          centerTitle: true,
        ),

        body: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // الهيدر
                          Row(
                            children: [
                              ClipOval(
                                child: userPhoto.isNotEmpty
                                    ? Image.network(
                                        userPhoto,
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
                              const SizedBox(width: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '@$username',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '· ${_formatTime(createdAt)}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (text.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment:
                                  _getTextDirection(text) == TextDirection.rtl
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Text(
                                text,
                                textDirection: _getTextDirection(text),
                                textAlign:
                                    _getTextDirection(text) == TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],

                          // الصورة
                          if (media.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: CachedNetworkImage(
                                imageUrl: media[0],
                                width: double.infinity,
                                fit: BoxFit.cover,
                                fadeInDuration: Duration.zero,
                                placeholderFadeInDuration: Duration.zero,
                              ),
                            ),
                          ],

                          // الوقت
                          const SizedBox(height: 12),
                          Text(
                            createdAt != null
                                ? '${createdAt.toDate().hour}:${createdAt.toDate().minute.toString().padLeft(2, '0')} · ${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
                                : '',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 12),
                          const Divider(
                            color: Color(0xFF2A293D),
                            thickness: 0.5,
                          ),

                          //  شريط التفاعل
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                // لايك
                                GestureDetector(
                                  onTap: _toggleLike,
                                  child: Row(
                                    children: [
                                      SvgPicture.asset(
                                        _isLiked
                                            ? 'assets/icons/likeT.svg'
                                            : 'assets/icons/like.svg',
                                        width: 20,
                                        height: 20,
                                        colorFilter: _isLiked
                                            ? null
                                            : const ColorFilter.mode(
                                                Colors.grey,
                                                BlendMode.srcIn,
                                              ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _likeCount > 0
                                            ? _formatCount(_likeCount)
                                            : '',
                                        style: TextStyle(
                                          color: _isLiked
                                              ? const Color(0xFFE0245E)
                                              : Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // تعليق
                                Row(
                                  children: [
                                    SvgPicture.asset(
                                      'assets/icons/reply.svg',
                                      width: 20,
                                      height: 20,
                                      colorFilter: const ColorFilter.mode(
                                        Colors.grey,
                                        BlendMode.srcIn,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _commentCount > 0
                                          ? _formatCount(_commentCount)
                                          : '',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 24),
                                // شير
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ShareToChatPage(
                                        postId: widget.post['postId'] ?? '',
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/share.svg',
                                        width: 20,
                                        height: 20,
                                        colorFilter: const ColorFilter.mode(
                                          Colors.grey,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        shareCount > 0
                                            ? _formatCount(shareCount)
                                            : '',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(
                            color: Color(0xFF2A293D),
                            thickness: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ),

                  //  التعليقات
                  _commentsLoading
                      ? const SliverFillRemaining(
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        )
                      : _comments.isEmpty
                      ? const SliverFillRemaining(
                          child: Center(
                            child: Text(
                              'لا توجد تعليقات بعد',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            // في الأسفل
                            if (index == _comments.length) {
                              return _isLoadingMoreComments
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF74E278),
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }
                            return _buildComment(_comments[index]);
                          }, childCount: _comments.length + 1),
                        ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 24,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0E17),
                border: Border(
                  top: BorderSide(color: Color(0xFF2A293D), width: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (MediaQuery.of(context).viewInsets.bottom > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.reply, color: Colors.grey, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'ردًا على ',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '@${widget.post['username'] ?? ''}',
                            style: const TextStyle(
                              color: Color(0xFF74E278),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // حقل التعليق
                  Row(
                    children: [
                      ClipOval(
                        child: () {
                          final photo =
                              CacheManager.getUser()?['photoUrl'] ?? '';
                          return photo.isNotEmpty
                              ? Image.network(
                                  photo,
                                  width: 34,
                                  height: 34,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 34,
                                  height: 34,
                                  color: const Color(0xFF2A293D),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                );
                        }(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          maxLines: null,
                          decoration: const InputDecoration(
                            hintText: 'أضف تعليقاً...',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _sendComment,
                        child: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Color(0xFF74E278),
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Color(0xFF74E278),
                                size: 26,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComment(Map<String, dynamic> comment) {
    final photo = comment['userPhoto'] as String? ?? '';
    final name = comment['displayName'] as String? ?? '';
    final username = comment['username'] as String? ?? '';
    final text = comment['text'] as String? ?? '';
    final likeCount = comment['likeCount'] as int? ?? 0;
    final isLiked = comment['isLiked'] as bool? ?? false;
    final createdAt = comment['createdAt'] as Timestamp?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── صورة ───
          ClipOval(
            child: photo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photo,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      color: const Color(0xFF2A293D),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  )
                : Container(
                    width: 36,
                    height: 36,
                    color: const Color(0xFF2A293D),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
          ),
          const SizedBox(width: 10),

          // ─── المحتوى ───
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الاسم + الوقت
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '@$username',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '· ${_formatTime(createdAt)}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    //  زر الإعجاب
                    GestureDetector(
                      onTap: () => _toggleCommentLike(comment),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            isLiked
                                ? 'assets/icons/likeT.svg'
                                : 'assets/icons/like.svg',
                            width: 14,
                            height: 14,
                            colorFilter: isLiked
                                ? null
                                : const ColorFilter.mode(
                                    Colors.grey,
                                    BlendMode.srcIn,
                                  ),
                          ),
                          if (likeCount > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              _formatCount(likeCount),
                              style: TextStyle(
                                color: isLiked
                                    ? const Color(0xFFE0245E)
                                    : Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // النص
                const SizedBox(height: 4),
                Align(
                  alignment: _getTextDirection(text) == TextDirection.rtl
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    text,
                    textDirection: _getTextDirection(text),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
