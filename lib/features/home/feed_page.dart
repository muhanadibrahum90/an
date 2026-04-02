import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aan/features/posts/post_card.dart';
import 'package:aan/services/cache_manager.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({Key? key}) : super(key: key);

  static FeedPageState? of(BuildContext context) =>
      context.findAncestorStateOfType<FeedPageState>();

  @override
  State<FeedPage> createState() => FeedPageState();
}

class FeedPageState extends State<FeedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF74E278),
          indicatorWeight: 2.5,
          labelColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorPadding: const EdgeInsets.symmetric(horizontal: -25),
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 15),
          dividerColor: const Color(0xFF2A293D),
          tabs: const [
            Tab(text: 'ترند'),
            Tab(text: 'متابع'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [_TrendingFeed(), _FollowingFeed()],
          ),
        ),
      ],
    );
  }
}

class _TrendingFeed extends StatefulWidget {
  const _TrendingFeed();

  @override
  State<_TrendingFeed> createState() => _TrendingFeedState();
}

class _TrendingFeedState extends State<_TrendingFeed>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  DocumentSnapshot? _lastDoc;
  final _scrollController = ScrollController();
  final Set<String> _recordedBoostViews = {};

  // ─── إعلانات ────────────────────────────────────
  final Map<int, NativeAd> _nativeAds = {};
  final Map<int, bool> _adsLoaded = {};

  static final _adUnitId = Platform.isAndroid
      ? 'ca-app-pub-1730889840880138/2069555984' // ← Android حقيقي
      : 'ca-app-pub-1730889840880138/2069555984'; // ← iOS حقيقي
  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final ad in _nativeAds.values) {
      ad.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  bool _isAdPosition(int index) => (index + 1) % 8 == 0;

  int _postIndexFromListIndex(int listIndex) {
    final chunk = listIndex ~/ 8;
    final position = listIndex % 8;
    return chunk * 7 + position;
  }

  int get _totalItemCount {
    final adCount = _posts.length ~/ 7;
    return _posts.length + adCount + (_isLoadingMore ? 1 : 0);
  }

  void _loadAdForIndex(int adIndex) {
    if (_nativeAds.containsKey(adIndex)) return;

    final ad = NativeAd(
      adUnitId: _adUnitId,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _adsLoaded[adIndex] = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _nativeAds.remove(adIndex);
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF1C1B2E),
        cornerRadius: 0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF74E278),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF1C1B2E),
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          backgroundColor: const Color(0xFF1C1B2E),
          style: NativeTemplateFontStyle.normal,
          size: 13,
        ),
      ),
    )..load();

    _nativeAds[adIndex] = ad;
  }

  Future<void> _recordBoostView(Map<String, dynamic> post) async {
    final postId = post['postId'] as String? ?? '';
    final isBoosted = post['isBoosted'] as bool? ?? false;
    final ownerUid = post['uid'] as String? ?? '';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (!isBoosted || postId.isEmpty) return;
    if (ownerUid == currentUid) return;
    if (_recordedBoostViews.contains(postId)) return;

    _recordedBoostViews.add(postId);

    await FirebaseFirestore.instance.collection('posts').doc(postId).update({
      'boostViewCount': FieldValue.increment(1),
    });
  }

  List<Map<String, dynamic>> _applyDiversity(List<Map<String, dynamic>> posts) {
    final result = <Map<String, dynamic>>[];
    final deferred = <Map<String, dynamic>>[];
    final userCount = <String, int>{};

    for (final post in posts) {
      final uid = post['uid'] as String? ?? '';
      final count = userCount[uid] ?? 0;
      if (count < 2) {
        result.add(post);
        userCount[uid] = count + 1;
      } else {
        deferred.add(post);
      }
    }

    result.addAll(deferred);
    return result;
  }

  List<Map<String, dynamic>> _mergeFeed(
    List<Map<String, dynamic>> trend,
    List<Map<String, dynamic>> boosted,
  ) {
    if (boosted.isEmpty) return trend;
    if (trend.isEmpty) return boosted;

    final result = <Map<String, dynamic>>[];
    int bIdx = 0;

    for (int i = 0; i < trend.length; i++) {
      result.add(trend[i]);
      if ((i + 1) % 6 == 0 && bIdx < boosted.length) {
        result.add(boosted[bIdx++]);
      }
    }

    while (bIdx < boosted.length) {
      result.add(boosted[bIdx++]);
    }

    return result;
  }

  Future<void> _loadPosts() async {
    if (mounted) setState(() => _isLoading = true);
    _lastDoc = null;
    _hasMore = true;

    for (final ad in _nativeAds.values) ad.dispose();
    _nativeAds.clear();
    _adsLoaded.clear();

    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where('trendScore', isGreaterThan: 0)
          .orderBy('trendScore', descending: true)
          .limit(20)
          .get();

      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
      _hasMore = snap.docs.length == 20;

      final posts = snap.docs.map((d) => d.data()).toList();

      if (mounted) {
        setState(() {
          _posts = _applyDiversity(posts);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_lastDoc == null || !_hasMore || _isLoadingMore) return;
    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where('trendScore', isGreaterThan: 0)
          .orderBy('trendScore', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(20)
          .get();

      if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
      _hasMore = snap.docs.length == 20;

      if (mounted) {
        setState(() {
          _posts.addAll(snap.docs.map((d) => d.data()));
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF74E278)),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF74E278),

        backgroundColor: const Color(0xFF1C1B2E),
        onRefresh: _loadPosts,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.35),

            const SizedBox(height: 12),
            const Text(
              'لا توجد منشورات حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'اسحب للأسفل لتحديث',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF74E278),
      backgroundColor: const Color(0xFF1C1B2E),
      onRefresh: _loadPosts,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _totalItemCount,
        itemBuilder: (context, listIndex) {
          if (listIndex == _totalItemCount - 1 && _isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF74E278)),
              ),
            );
          }

          if (_isAdPosition(listIndex)) {
            final adIndex = listIndex ~/ 8;
            _loadAdForIndex(adIndex);

            return _adsLoaded[adIndex] == true
                ? ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 100,
                      maxHeight: 400,
                    ),
                    child: Stack(
                      children: [
                        AdWidget(ad: _nativeAds[adIndex]!),
                        Positioned(
                          top: 10,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'إعلان',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(height: 0);
          }

          final postIndex = _postIndexFromListIndex(listIndex);
          if (postIndex >= _posts.length) return const SizedBox.shrink();

          final post = _posts[postIndex];

          return PostCard(post: post, onVisible: () => _recordBoostView(post));
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
// متابع — بدون تغيير في المنطق
// ─────────────────────────────────────────
class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed();

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadFollowingPosts();
  }

  Future<void> _loadFollowingPosts() async {
    setState(() => _isLoading = true);

    final followingSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('following')
        .get();

    final followingUids = followingSnap.docs.map((d) => d.id).toList();

    if (followingUids.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final List<Map<String, dynamic>> allPosts = [];

    for (int i = 0; i < followingUids.length; i += 30) {
      final chunk = followingUids.sublist(i, min(i + 30, followingUids.length));

      final postsSnap = await FirebaseFirestore.instance
          .collection('posts')
          .where('uid', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .limit(15)
          .get();

      allPosts.addAll(postsSnap.docs.map((d) => d.data()));
    }

    allPosts.sort((a, b) {
      final aTime = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bTime = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    if (mounted) {
      setState(() {
        _posts = allPosts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF74E278)),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF74E278),
        backgroundColor: const Color(0xFF1C1B2E),
        onRefresh: _loadFollowingPosts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), // مهم جداً
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Icon(Icons.people_outline, color: Colors.grey, size: 48),
            const SizedBox(height: 12),
            const Text(
              'تابع أصدقائك لترى منشوراتهم هنا',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF74E278),
      backgroundColor: const Color(0xFF1C1B2E),
      onRefresh: _loadFollowingPosts,
      child: ListView.builder(
        itemCount: _posts.length,
        itemBuilder: (context, index) => PostCard(post: _posts[index]),
      ),
    );
  }
}
