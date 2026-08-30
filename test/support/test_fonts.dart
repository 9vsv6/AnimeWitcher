import 'dart:io';

import 'package:flutter/services.dart';

/// Shared font helpers for the golden-ish walkthrough tests.
///
/// These tests render real Arabic text, so they need the system Noto Arabic
/// faces plus the Material fonts shipped inside the Flutter SDK cache. The
/// SDK location differs per machine (`/opt/flutter` on the original CI image,
/// a repo-local SDK in the sandbox, `~/fltr` for many contributors), so the
/// paths are resolved at runtime instead of being hardcoded. Every loader is
/// best-effort: when a face is missing the test still runs with the default
/// test font rather than throwing a PathNotFoundException.
class TestFonts {
  TestFonts._();

  static const String _arabicRegular =
      '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf';
  static const String _arabicBold =
      '/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf';

  /// Root of the Flutter SDK running this test, derived from the resolved
  /// Dart executable (`<sdk>/bin/cache/dart-sdk/bin/dart`).
  static Directory? get _flutterRoot {
    var dir = File(Platform.resolvedExecutable).parent;
    // Walk up looking for the directory that owns `bin/cache`.
    for (var i = 0; i < 8; i++) {
      final candidate = Directory('${dir.path}/bin/cache/artifacts');
      if (candidate.existsSync()) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Absolute path of a font inside the SDK's `material_fonts` cache, or
  /// `null` when this SDK has not populated that artifact.
  static String? materialFont(String fileName) {
    final root = _flutterRoot;
    if (root == null) return null;
    final path = '${root.path}/bin/cache/artifacts/material_fonts/$fileName';
    return File(path).existsSync() ? path : null;
  }

  static Future<ByteData> _bytes(String path) async {
    return ByteData.sublistView(await File(path).readAsBytes());
  }

  /// Registers a font family from an absolute path when the file exists.
  static Future<void> loadFamily(String family, List<String?> paths) async {
    final present = paths.whereType<String>().where(
      (path) => File(path).existsSync(),
    );
    if (present.isEmpty) return;
    final loader = FontLoader(family);
    for (final path in present) {
      loader.addFont(_bytes(path));
    }
    await loader.load();
  }

  /// True when the Arabic system faces the walkthrough shots rely on exist.
  static bool get hasArabicFaces => File(_arabicRegular).existsSync();

  /// Loads Arabic + Material faces used by the walkthrough screenshot tests.
  ///
  /// Returns `false` when the Arabic faces are unavailable, letting a test
  /// skip its screenshot assertions instead of failing on a missing font.
  static Future<bool> loadWalkthroughFonts() async {
    if (!hasArabicFaces) return false;
    await loadFamily('NotoSansArabic', <String?>[_arabicRegular, _arabicBold]);
    await loadFamily('Roboto', <String?>[
      materialFont('Roboto-Regular.ttf'),
      materialFont('Roboto-Bold.ttf'),
    ]);
    await loadFamily('MaterialIcons', <String?>[
      materialFont('MaterialIcons-Regular.otf'),
    ]);
    return true;
  }
}
