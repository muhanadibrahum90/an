// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'features/onboarding/welcome_page.dart';
import 'features/home/home_page.dart';
import 'services/cache_manager.dart';
import 'features/auth/verify_email_page.dart';


@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}


final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/logo_not');
  const ios = DarwinInitializationSettings();
  await _localNotifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'default',
          'الإشعارات',
          importance: Importance.high,
        ),
      );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'messages',
          'الرسائل',
          importance: Importance.high,
        ),
      );
}

void _showLocalNotification(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;

  if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
    return;

  final isMessage = message.data['type'] == 'message';

  _localNotifications.show(
    notification.hashCode,
    notification.title,
    notification.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        isMessage ? 'messages' : 'default',
        isMessage ? 'الرسائل' : 'الإشعارات',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/logo_not',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

Future<void> _saveFcmToken() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await FirebaseFirestore.instance.collection('users').doc(uid).update({
    'fcmToken': token,
  });

  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': newToken,
    });
  });
}

// Main
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await _initLocalNotifications();

  FirebaseMessaging.onMessage.listen(_showLocalNotification);

  await CacheManager.init();
  await CacheManager.clearOldSeenPosts();

  await _saveFcmToken();

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  runApp(const AanApp());
}

// AanApp
class AanApp extends StatefulWidget {
  const AanApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<AanApp> createState() => _AanAppState();
}

class _AanAppState extends State<AanApp> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _setupNotificationTap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSession();
    }
  }

  Future<void> _checkSession() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {}
  }

  void _setupNotificationTap() {
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message.data);
    });
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';

    if (type == 'message') {
      AanApp.navigatorKey.currentState?.pushNamed('/messages');
    } else if (type == 'follow' ||
        type == 'like_milestone' ||
        type == 'comment') {
      AanApp.navigatorKey.currentState?.pushNamed('/notifications');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AanApp.navigatorKey,

      debugShowCheckedModeBanner: false,
      title: 'Aan',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        useMaterial3: true,
        textTheme: GoogleFonts.tajawalTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F0E17),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image(
                      image: AssetImage('assets/images/logo.png'),
                      width: 120,
                      height: 120,
                    ),
                    SizedBox(height: 24),
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            if (snapshot.hasError) {
              FirebaseAuth.instance.signOut();
            }
            return const WelcomePage();
          }

          final user = snapshot.data!;

          if (!snapshot.hasData) return const WelcomePage();

          if (!user.emailVerified) {
            final isGoogle = user.providerData.any(
              (p) => p.providerId == 'google.com',
            );
            final isApple = user.providerData.any(
              (p) => p.providerId == 'apple.com',
            );

            if (!isGoogle && !isApple) return const VerifyEmailPage();
          }

          return const HomePage();
        },
      ),
    );
  }
}

