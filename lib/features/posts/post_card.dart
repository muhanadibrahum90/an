// lib/features/posts/post_card.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:visibility_detector/visibility_detector.dart';
import 'package:aan/features/posts/post_detail_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:aan/features/profile/profile_page.dart';
import 'package:aan/services/notification_service.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:aan/features/posts/edit_post_page.dart';
import '../chat/share_to_chat_page.dart';
import 'package:aan/services/snack_bar_service.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onVisible;
  const PostCard({super.key, required this.post, this.onVisible});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late int _likeCount;
  bool _isLiked = false;
  bool _isLikeLoading = false;
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  int _commentCount = 0;
  bool _hasCalledOnVisible = false;

  bool _hasRecordedView = false;
  bool _isLikeCheckLoading = true;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post['likeCount'] ?? 0;
    _commentCount = widget.post['commentCount'] ?? 0;
    _checkIfLiked();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['likeCount'] != widget.post['likeCount'] ||
        oldWidget.post['commentCount'] != widget.post['commentCount']) {
      setState(() {
        _likeCount = widget.post['likeCount'] ?? 0;
        _commentCount = widget.post['commentCount'] ?? 0;
      });
      _checkIfLiked();
    }
  }

  Future<void> _recordView() async {
    final postId = widget.post['postId'] as String? ?? '';
    final ownerUid = widget.post['uid'] as String? ?? '';

    if (postId.isEmpty) return;

    if (_uid == ownerUid) return;

    await CacheManager.markPostSeen(postId);

    await CacheManager.markPostSeen(postId);

    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).update({
        'viewCount': FieldValue.increment(1),
      });
    } catch (e) {}
  }

  void showPostOptions(
    BuildContext context, {
    required String postId,
    required String postOwnerId,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

    final bool isOwnerOrAdmin = currentUserId == postOwnerId;

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

            if (isOwnerOrAdmin) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white),
                title: const Text(
                  'تعديل المنشور',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onEdit();
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'حذف المنشور',
                  style: TextStyle(color: Colors.red, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                title: const Text(
                  'إبلاغ عن المنشور',
                  style: TextStyle(color: Colors.orange, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleReport(
                    context,
                    postId: postId,
                    reporterId: currentUserId,
                  );
                },
              ),
            ],

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

  Future<void> _handleReport(
    BuildContext context, {
    required String postId,
    required String reporterId,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;

    final reportRef = db
        .collection('posts')
        .doc(postId)
        .collection('reports')
        .doc(reporterId);

    final existing = await reportRef.get();

    if (existing.exists) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لقد أبلغت عن هذا المنشور من قبل'),
            backgroundColor: Colors.grey,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final batch = db.batch();

    batch.set(reportRef, {
      'reporterId': reporterId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.update(db.collection('posts').doc(postId), {
      'reportCount': FieldValue.increment(1),
    });

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم الإبلاغ عن المنشور، شكرًا لك'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'حذف المنشور',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل أنت متأكد؟ لا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            child: const Text(
              'حذف',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    final postId = widget.post['postId'] as String? ?? '';
    if (postId.isEmpty) return;

    try {
      final media = List<String>.from(widget.post['media'] as List? ?? []);
      if (media.isNotEmpty) {
        await _deleteImageFromR2(media.first);
      }

      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();

      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'postsCount': FieldValue.increment(-1),
      });

      await CacheManager.updateField(
        'postsCount',
        (CacheManager.getUser()?['postsCount'] ?? 1) - 1,
      );

      if (mounted) {
        showSnackBar(context, 'تم حذف المنشور');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'فشل الحذف: $e', isError: true);
      }
    }
  }

  String? _extractPostImageKey(String url) {
    try {
      final path = Uri.parse(url).path;
      return path.startsWith('/') ? path.substring(1) : path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteImageFromR2(String imageUrl) async {
    final key = _extractPostImageKey(imageUrl);
    if (key == null) return;
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      await http.post(
        Uri.parse(
          'https://aan-upload.aan52907394.workers.dev/delete-post-image',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'key': key}),
      );
    } catch (e) {}
  }

  void _editPost(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditPostPage(post: widget.post)),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  TextDirection _getTextDirection(String text) {
    final arabicRegex = RegExp(r'[\u0600-\u06FF]');
    return arabicRegex.hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  void _openImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, __) => _FullScreenImage(imageUrl: imageUrl),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _checkIfLiked() async {
    final postId = widget.post['postId'];
    final doc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(_uid)
        .get();
    if (mounted) {
      setState(() {
        _isLiked = doc.exists;
        _isLikeCheckLoading = false; // ← أطلق القفل بعد التحقق
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_isLikeLoading || _isLikeCheckLoading) return;

    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
      _isLikeLoading = true;
    });

    final postId = widget.post['postId'];
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);
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
        await NotificationService.sendLikeMilestone(
          postOwnerUid: widget.post['uid'],
          postId: widget.post['postId'],
          postText: widget.post['text'] ?? '',
          totalLikeCount: _likeCount,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
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

  String formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}مليون';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}ألف';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final userPhoto = widget.post['userPhoto'] ?? '';
    final displayName = widget.post['displayName'] ?? '';
    final username = widget.post['username'] ?? '';
    final text = widget.post['text'] ?? '';
    final media = List<String>.from(widget.post['media'] ?? []);
    final shareCount = widget.post['shareCount'] ?? 0;
    final createdAt = widget.post['createdAt'] as Timestamp?;
    final postId = widget.post['postId'] ?? '';

    return VisibilityDetector(
      key: Key('post-$postId'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction >= 0.5 && mounted) {
          if (!_hasRecordedView) {
            _hasRecordedView = true;
            _recordView();
          }
          if (!_hasCalledOnVisible) {
            _hasCalledOnVisible = true;
            widget.onVisible?.call();
          }
        }
      },

      child: GestureDetector(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailPage(
                post: widget.post,
                isLiked: _isLiked,
                likeCount: _likeCount,
              ),
            ),
          );
          if (result != null && mounted) {
            setState(() {
              _isLiked = result['isLiked'];
              _likeCount = result['likeCount'];
              _commentCount = result['commentCount'];
            });
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(uid: widget.post['uid']),
                      ),
                    ),
                    child: ClipOval(
                      child: userPhoto.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: userPhoto,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 44,
                              height: 44,
                              color: const Color(0xFF2A293D),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // ─── محتوى المنشور ───
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الاسم + الوقت
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
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
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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
                            ),
                            GestureDetector(
                              onTap: () => showPostOptions(
                                context,
                                postId: widget.post['postId'] ?? '',
                                postOwnerId: widget.post['uid'] ?? '',
                                onEdit: () => _editPost(context),
                                onDelete: () => _confirmDelete(context),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: SvgPicture.asset(
                                  'assets/icons/Ellipsis.svg',
                                  width: 18,
                                  height: 18,
                                  colorFilter: const ColorFilter.mode(
                                    Colors.grey,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Align(
                            //  محاذاة حسب اتجاه النص
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
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],

                        // الصورة
                        if (media.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => _openImage(context, media[0]),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: CachedNetworkImage(
                                imageUrl: media[0],
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  height: 200,
                                  color: const Color(0xFF2A293D),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  height: 200,
                                  color: const Color(0xFF2A293D),
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        //أزرار التفاعل
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Row(
                            children: [
                              // لايك
                              Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _isLikeCheckLoading
                                        ? null
                                        : _toggleLike, // ← معطّل فقط
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SvgPicture.asset(
                                          _isLiked
                                              ? 'assets/icons/likeT.svg'
                                              : 'assets/icons/like.svg',
                                          width: 16,
                                          height: 16,
                                          colorFilter: _isLiked
                                              ? null
                                              : const ColorFilter.mode(
                                                  Colors.grey,
                                                  BlendMode.srcIn,
                                                ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _likeCount > 0
                                              ? formatCount(_likeCount)
                                              : '',
                                          style: TextStyle(
                                            color: _isLiked
                                                ? const Color(0xFFE0245E)
                                                : Colors.grey,
                                            fontSize: 12,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // تعليق
                              Expanded(
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/reply.svg',
                                        width: 17,
                                        height: 17,
                                        colorFilter: const ColorFilter.mode(
                                          Colors.grey,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _commentCount > 0
                                            ? formatCount(_commentCount)
                                            : '',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // شير
                              Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ShareToChatPage(postId: postId),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SvgPicture.asset(
                                          'assets/icons/share.svg',
                                          width: 17,
                                          height: 17,
                                          colorFilter: const ColorFilter.mode(
                                            Colors.grey,
                                            BlendMode.srcIn,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          shareCount > 0
                                              ? formatCount(shareCount)
                                              : '',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                            height: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A293D), thickness: 0.5),
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
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
