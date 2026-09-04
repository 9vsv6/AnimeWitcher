/// Requests catalog artwork at the size it was actually uploaded at.
///
/// The catalog serves its images through Storyblok, whose URLs carry both the
/// dimensions of the stored image and a directive asking for a resized copy:
///
/// ```
/// https://a.storyblok.com/f/178900/1460x821/<hash>/<name>.jpg/m/576x0/filters:…
///                                 ^ stored                     ^ requested
/// ```
///
/// The requested width is often far smaller than the stored one — 576px is
/// common — which is invisible on a card and obvious on a hero banner drawn
/// the full width of a desktop window. Asking for the stored width costs
/// nothing extra to serve and is the difference between a sharp banner and an
/// upscaled one.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

final RegExp _storyblokRender = RegExp(
  r'^(https?://a\.storyblok\.com/f/[^/]+/(\d+)x(\d+)/.*?)/m/(\d+)x(\d+)/(.*)$',
);

/// Rewrites a Storyblok URL to ask for the stored width, up to [maxWidth].
///
/// Storyblok never upscales, so asking beyond the stored width would silently
/// return the stored one anyway; the cap only exists so a caller that knows it
/// paints small can still ask small. Anything that is not a Storyblok render
/// URL is returned untouched.
String storyblokAtStoredWidth(String url, {int maxWidth = 1920}) {
  final match = _storyblokRender.firstMatch(url);
  if (match == null) return url;

  final storedWidth = int.tryParse(match.group(2) ?? '');
  final requestedWidth = int.tryParse(match.group(4) ?? '');
  if (storedWidth == null || requestedWidth == null || storedWidth <= 0) {
    return url;
  }

  final wanted = storedWidth < maxWidth ? storedWidth : maxWidth;
  // Already asking for as much as it is worth requesting.
  if (requestedWidth >= wanted) return url;

  // The height stays 0 so Storyblok keeps the aspect ratio it was uploaded at.
  return '${match.group(1)}/m/${wanted}x0/${match.group(6)}';
}

/// How wide a banner render to ask for on this device.
///
/// A desktop hero runs the full width of the window, so it is worth the whole
/// stored image. A phone draws the same hero about a quarter that wide, where
/// asking for the stored width would download several times the pixels it can
/// show and decode them into memory it has less of.
int get storyblokBannerWidth =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? 1080 : 1920;
