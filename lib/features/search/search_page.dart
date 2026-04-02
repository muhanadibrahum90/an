// lib/features/search/search_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:aan/features/profile/profile_page.dart';
import 'package:aan/features/posts/post_card.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  Map<String, dynamic>? _foundUser;
  List<Map<String, dynamic>> _userPosts = [];
  bool _isLoading = false;
  bool _searched = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSuggesting = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final text = _searchController.text;
      final selection = _searchController.selection;

      if (selection.start > text.length) {
        _searchController.selection = TextSelection.collapsed(
          offset: text.length,
        );
      }
    });
  }

  void _getSuggestions(String input) {
    if (_searched) setState(() => _searched = false);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchSuggestions(input);
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    final query = input.replaceAll('@', '').trim().toLowerCase();

    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSuggesting = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThan: '${query}z')
          .limit(10)
          .get();

      if (mounted) {
        setState(() {
          _suggestions = snapshot.docs.map((d) {
            final data = d.data();
            data['uid'] = d.id;
            return data;
          }).toList();
          _isSuggesting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  Future<void> _search(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isLoading = true;
      _searched = true;
      _suggestions = [];
      _foundUser = null;
      _userPosts = [];
    });

    final hasAt = raw.startsWith('@');
    final hasSpaces = raw.contains(' ');
    final query = raw.replaceAll('@', '').trim().toLowerCase();

    try {
      if (hasAt || !hasSpaces) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isGreaterThanOrEqualTo: query)
            .where('username', isLessThan: '${query}z')
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final userData = snapshot.docs.first.data();
          final uid = snapshot.docs.first.id;
          userData['uid'] = uid;

          final postsSnap = await FirebaseFirestore.instance
              .collection('posts')
              .where('uid', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .get();

          if (mounted) {
            setState(() {
              _foundUser = userData;
              _userPosts = postsSnap.docs.map((d) => d.data()).toList();
            });
          }
          return;
        }

        if (hasAt) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      await _searchPosts(raw);
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchPosts(String query) async {
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdToken();
      final response = await http.post(
        Uri.parse('https://aan-upload.aan52907394.workers.dev/algolia-search'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hits = List<Map<String, dynamic>>.from(data['hits'] ?? []);

        if (hits.isEmpty) return;

        final postIds = hits.map((h) => h['objectID'] as String).toList();

        final postsSnap = await FirebaseFirestore.instance
            .collection('posts')
            .where(FieldPath.documentId, whereIn: postIds)
            .get();

        if (mounted) {
          setState(() {
            _userPosts = postsSnap.docs.map((d) => d.data()).toList();
          });
        }
      }
    } catch (e) {}
  }

  Widget _buildSuggestionCard(Map<String, dynamic> user) {
    final name = user['name'] ?? '';
    final username = user['username'] ?? '';
    final photoUrl = user['photoUrl'] ?? '';
    final uid = user['uid'] ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(uid: uid)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                ClipOval(
                  child: photoUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 46,
                          height: 46,
                          color: const Color(0xFF2A293D),
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 14,
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A293D), thickness: 0.5, height: 0),
        ],
      ),
    );
  }

  String formatCount(int count) {
    if (count >= 1000000) {
      double r = count / 1000000;
      return '${r.toStringAsFixed(r.truncateToDouble() == r ? 0 : 1)}م';
    } else if (count >= 1000) {
      double r = count / 1000;
      return '${r.toStringAsFixed(r.truncateToDouble() == r ? 0 : 1)}ك';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        surfaceTintColor: const Color(0xFF0F0E17),
        elevation: 0,
        title: Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1B2E),
            borderRadius: BorderRadius.circular(99),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: _getSuggestions,
            cursorColor: const Color(0xFF74E278),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: 'ابحث عن الترند..',
              hintStyle: TextStyle(color: Colors.grey),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: SvgPicture.asset(
                  'assets/icons/search.svg',
                  color: Colors.grey,
                  width: 14,
                  height: 14,
                ),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : !_searched && _suggestions.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/icons/search.svg',
                    color: Colors.grey,
                    width: 40,
                    height: 40,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'ابحث عن مستخدم أو منشور',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : !_searched && _suggestions.isNotEmpty
          ? ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (context, index) =>
                  _buildSuggestionCard(_suggestions[index]),
            )
          : _foundUser != null
          ? ListView(
              children: [
                _buildUserCard(_foundUser!),
                const Divider(color: Color(0xFF2A293D), thickness: 0.5),
                if (_userPosts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'لا توجد منشورات',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ..._userPosts.map((post) => PostCard(post: post)),
              ],
            )
          : _userPosts.isNotEmpty
          ? ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'نتائج البحث',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
                ..._userPosts.map((post) => PostCard(post: post)),
              ],
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, color: Colors.grey, size: 48),
                  SizedBox(height: 12),
                  Text('لا توجد نتائج', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = user['name'] ?? '';
    final username = user['username'] ?? '';
    final photoUrl = user['photoUrl'] ?? '';
    final followersCount = user['followersCount'] ?? 0;
    final followingCount = user['followingCount'] ?? 0;
    final postsCount = user['postsCount'] ?? 0;
    final uid = user['uid'] ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(uid: uid)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipOval(
              child: photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF2A293D),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStat(followersCount, 'متابعون'),
                      const SizedBox(width: 16),
                      _buildStat(followingCount, 'متابع'),
                      const SizedBox(width: 16),
                      _buildStat(postsCount, 'منشور'),
                    ],
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
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
              fontSize: 13,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
