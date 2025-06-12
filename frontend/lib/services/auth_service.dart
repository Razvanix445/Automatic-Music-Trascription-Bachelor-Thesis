import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential?> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Adresa de email nu este validă.';
      case 'user-disabled':
        return 'Acest cont a fost dezactivat.';
      case 'user-not-found':
        return 'Nu există un cont cu acest email.';
      case 'wrong-password':
        return 'Parola este incorectă.';
      case 'email-already-in-use':
        return 'Există deja un cont cu acest email.';
      case 'operation-not-allowed':
        return 'Această operațiune nu este permisă.';
      case 'weak-password':
        return 'Parola este prea slabă.';
      default:
        return 'A apărut o eroare: ${e.message}';
    }
  }
}