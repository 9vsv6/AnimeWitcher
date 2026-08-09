enum AnimeWitcherSignInMethod { email, google }

class AnimeWitcherSession {
  const AnimeWitcherSession({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.signInMethod,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AnimeWitcherSignInMethod signInMethod;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  bool get needsRefresh =>
      DateTime.now().add(const Duration(minutes: 2)).isAfter(expiresAt);

  AnimeWitcherSession copyWith({
    String? uid,
    String? idToken,
    String? refreshToken,
    DateTime? expiresAt,
    AnimeWitcherSignInMethod? signInMethod,
    String? email,
    String? displayName,
    String? photoUrl,
  }) {
    return AnimeWitcherSession(
      uid: uid ?? this.uid,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      signInMethod: signInMethod ?? this.signInMethod,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'uid': uid,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'signInMethod': signInMethod.name,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory AnimeWitcherSession.fromJson(Map<String, dynamic> json) {
    return AnimeWitcherSession(
      uid: (json['uid'] ?? '').toString(),
      idToken: (json['idToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      expiresAt:
          DateTime.tryParse((json['expiresAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      signInMethod:
          (json['signInMethod'] ?? '').toString().toLowerCase() == 'google'
          ? AnimeWitcherSignInMethod.google
          : AnimeWitcherSignInMethod.email,
      email: _optionalString(json['email']),
      displayName: _optionalString(json['displayName']),
      photoUrl: _optionalString(json['photoUrl']),
    );
  }
}

class AnimeWitcherProfile {
  const AnimeWitcherProfile({
    required this.documentId,
    required this.uid,
    required this.signInMethod,
    this.email,
    this.userName,
    this.photoUrl,
  });

  final String documentId;
  final String uid;
  final AnimeWitcherSignInMethod signInMethod;
  final String? email;
  final String? userName;
  final String? photoUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'documentId': documentId,
    'uid': uid,
    'signInMethod': signInMethod.name,
    'email': email,
    'userName': userName,
    'photoUrl': photoUrl,
  };

  factory AnimeWitcherProfile.fromJson(Map<String, dynamic> json) {
    return AnimeWitcherProfile(
      documentId: (json['documentId'] ?? '').toString(),
      uid: (json['uid'] ?? '').toString(),
      signInMethod:
          (json['signInMethod'] ?? '').toString().toLowerCase() == 'google'
          ? AnimeWitcherSignInMethod.google
          : AnimeWitcherSignInMethod.email,
      email: _optionalString(json['email']),
      userName: _optionalString(json['userName']),
      photoUrl: _optionalString(json['photoUrl']),
    );
  }
}

class AnimeWitcherAccountSnapshot {
  const AnimeWitcherAccountSnapshot({
    this.profile,
    this.lastSyncAt,
  });

  final AnimeWitcherProfile? profile;
  final DateTime? lastSyncAt;

  bool get isSignedIn => profile != null;

  AnimeWitcherAccountSnapshot copyWith({
    AnimeWitcherProfile? profile,
    DateTime? lastSyncAt,
    bool clearProfile = false,
  }) {
    return AnimeWitcherAccountSnapshot(
      profile: clearProfile ? null : (profile ?? this.profile),
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class AnimeWitcherAccountException implements Exception {
  const AnimeWitcherAccountException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

String? _optionalString(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}
