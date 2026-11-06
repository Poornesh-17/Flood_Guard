import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Future<void> addUser({
    required String uid,
    required String name,
    required String email,
    String? phoneNumber,
    String? password,
    String loginType = 'email',
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .set(
      {
        'uid': uid,
        'name': name.trim(),
        'email': email.trim().toLowerCase(),

        // User's own phone number
        'phoneNumber':
        phoneNumber?.trim() ?? '',

        'loginType': loginType,

        'createdAt':
        FieldValue.serverTimestamp(),

        'lastLogin':
        FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateLastLogin(
      String uid,
      ) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .set(
      {
        'lastLogin':
        FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}