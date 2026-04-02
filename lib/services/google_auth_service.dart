import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoogleAuthService {
  static final _googleSignIn = GoogleSignIn();

  static const String resultLogin    = 'login';   
  static const String resultRegister = 'register'; 
  static const String resultCancelled = 'cancelled';

  static String? newUserEmail;
  static String? newUserName;

  static Future<String> handle() async {
    await _googleSignIn.signOut();

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return resultCancelled;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );

    final userCredential = await FirebaseAuth.instance
        .signInWithCredential(credential);

    final uid = userCredential.user!.uid;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists) {
      return resultLogin;
    } else {
      newUserEmail = googleUser.email;
      newUserName  = userCredential.user?.displayName
                  ?? googleUser.displayName
                  ?? '';
      return resultRegister;
    }
  }
}