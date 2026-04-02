// lib/services/cache_manager.dart

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CacheManager {
  static const String userBox       = 'user_cache';
  static const String _seenPostsBox = 'seen_posts';

  static const String _profileKey   = 'profile';
  static const String _timestampKey = 'profile_timestamp';

  static const Duration _cacheDuration = Duration(minutes: 10);



  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(userBox);
    await Hive.openBox<int>(_seenPostsBox);
  }

  static Box get _box          => Hive.box(userBox);
  static Box<int> get _seenBox => Hive.box<int>(_seenPostsBox);

 

  static dynamic _sanitize(dynamic value) {
    if (value is Timestamp) {
      return {
        '__type': 'Timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
      };
    } else if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
    } else if (value is List) {
      return value.map(_sanitize).toList();
    }
    return value;
  }

  static dynamic _restore(dynamic value) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map['__type'] == 'Timestamp') {
        return Timestamp(map['seconds'] as int, map['nanoseconds'] as int);
      }
      return map.map((k, v) => MapEntry(k, _restore(v)));
    } else if (value is List) {
      return value.map(_restore).toList();
    }
    return value;
  }

  static Future<void> saveUser(Map<String, dynamic> data) async {
    final cleanData = _sanitize(data) as Map<String, dynamic>;
    await _box.put(_profileKey, jsonEncode(cleanData));
    await _box.put(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Map<String, dynamic>? getUser() {
    final savedAt = _box.get(_timestampKey);
    if (savedAt != null) {
      final age = DateTime.now().millisecondsSinceEpoch - (savedAt as int);
      if (age > _cacheDuration.inMilliseconds) {
        clearUser();
        return null;
      }
    }

    final raw = _box.get(_profileKey);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      return _restore(decoded) as Map<String, dynamic>;
    } catch (e) {
      clearUser();
      return null;
    }
  }

  static Future<void> clearUser() async {
    await _box.delete(_profileKey);
    await _box.delete(_timestampKey);
  }

  static Future<void> updateField(String key, dynamic value) async {
    final data = getUser();
    if (data == null) return;
    data[key] = value;
    await saveUser(data);
  }


  static Future<void> markPostSeen(String postId) async {
    await _seenBox.put(postId, DateTime.now().millisecondsSinceEpoch);
  }

  static Set<String> getSeenPostIds() {
    return _seenBox.keys.cast<String>().toSet();
  }


  static Future<void> clearOldSeenPosts() async {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;

    final toDelete = _seenBox.keys
        .cast<String>()
        .where((k) => (_seenBox.get(k) ?? 0) < cutoff)
        .toList();

    if (toDelete.isNotEmpty) await _seenBox.deleteAll(toDelete);
  }



  static Future<void> clearAll() async {
    await clearUser();
    await _seenBox.clear();
  }
}