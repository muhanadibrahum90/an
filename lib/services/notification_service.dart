// lib/services/notification_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aan/services/cache_manager.dart';

class NotificationService {
  static final _firestore = FirebaseFirestore.instance;
  static final _milestones = [
    1,
    10,
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
    200000,
    500000,
    1000000,
  ];


  static Future<void> sendLikeMilestone({
  required String postOwnerUid,
  required String postId,
  required String postText,
  required int totalLikeCount,
}) async {
  final currentUid = FirebaseAuth.instance.currentUser!.uid;
  if (currentUid == postOwnerUid) return;

  try {
    final ownerLikeDoc = await _firestore
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(postOwnerUid)
        .get();

    final realCount = ownerLikeDoc.exists ? totalLikeCount - 1 : totalLikeCount;

    if (!_milestones.contains(realCount)) return;

    final notifRef = _firestore
        .collection('notifications')
        .doc(postOwnerUid)
        .collection('items')
        .doc('like_${postId}_$realCount');

    await notifRef.set({
      'type': 'like_milestone',
      'postId': postId,
      'postText': postText,
      'count': realCount,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}
  static Future<void> sendCommentNotification({
    required String postOwnerUid,
    required String postId,
    required String postText,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    if (currentUid == postOwnerUid) return;

    try {
      final userData = CacheManager.getUser();
      final notifRef = _firestore
          .collection('notifications')
          .doc(postOwnerUid)
          .collection('items')
          .doc();

      await notifRef.set({
        'type': 'comment',
        'fromUid': currentUid,
        'fromUsername': userData?['username'] ?? '',
        'fromPhoto': userData?['photoUrl'] ?? '',
        'postId': postId,
        'postText': postText,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
