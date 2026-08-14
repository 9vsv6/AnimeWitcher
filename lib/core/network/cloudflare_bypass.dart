import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cross-platform Cloudflare JS challenge bypass.
class CloudflareBypass {
  CloudflareBypass._();
  static final instance = CloudflareBypass._();

  static const _tag = '[CF Bypass]';
  static const _cfErrorCodes = [403, 429, 503];
  static const _cfServers = ['cloudflare-nginx', 'cloudflare'];
  static const _timeout = Duration(seconds: 60);
  static const _navTimeout = Duration(seconds: 20);
  static const _pollInterval = Duration(milliseconds: 200);

  // ---------------------------------------------------------------------------
  // State Management
  // ---------------------------------------------------------------------------

  /// Active background WebView sessions indexed by `(callerId, host)` so a
  /// solve performed by plugin A can't be reused by plugin B — that would
  /// hand B the cookies / session state A established (audit H6 / PR-08d).
  /// Legacy callers without a callerId share the implicit `'_global_'`
  /// namespace; this only matters during the rollout, since every code
  /// path going through the JS bridge now threads a real namespace.
  final Map<String, _HostWebView> _hostWebViews = {};

  /// Per-`(callerId, host)` deduplication: if we're already solving CF for
  /// a `(callerId, host)` pair, new callers for the same pair share the
  /// same Future instead of spawning a second WebView.
  final Map<String, Future<CfResult?>> _activeByHost = {};

  /// Composite key for cache buckets — keeps the map shape unchanged while
  /// making the scope explicit.
  static String _scopeKey(String? callerId, String host) {
    final scope = (callerId == null || callerId.isEmpty)
        ? '_global_'
        : callerId;
    return '$scope::$host';
  }

  /// Limits concurrent WebView spawns to prevent GPU/RAM exhaustion.
  /// Each HeadlessInAppWebView spawn triggers a full Vulkan/GPU context init
  /// on Android — doing two simultaneously causes severe frame drops (40+
  /// skipped frames). Reusing existing cached sessions bypasses this limit.
  static const _maxConcurrentSpawns = 1;
  int _spawningCount = 0;
  final _spawnQueue = <Completer<void>>[];

  Future<void> _acquireSpawnSlot() async {
    if (_spawningCount < _maxConcurrentSpawns) {
      _spawningCount++;
      return;
    }
    final waiter = Completer<void>();
    _spawnQueue.add(waiter);
    await waiter.future;
  }

  void _releaseSpawnSlot() {
    if (_spawnQueue.isNotEmpty) {
      _spawnQueue.removeAt(0).complete();
    } else {
      _spawningCount--;
    }
  }

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  bool _looksLikeBrowserChallenge(String body) {
    final source = body.toLowerCase();
    if (source.isEmpty) return false;

    return source.contains('just a moment') ||
        source.contains('checking your browser') ||
        source.contains('browser verification') ||
        source.contains('verify you are human') ||
        source.contains('verifying you are human') ||
        source.contains('making sure you are not a bot') ||
        source.contains("making sure you're not a bot") ||
        source.contains('enable javascript and cookies to continue') ||
        source.contains('attention required') ||
        source.contains('cf-mitigated') ||
        source.contains('_cf_chl_opt') ||
        source.contains('challenge-platform') ||
        source.contains('challenge-form') ||
        source.contains('cf-turnstile');
  }

  bool isCloudflareChallenge(
    int? statusCode,
    Map<String, dynamic> headers,
    String body,
  ) {
    // Managed browser challenges can return HTTP 200, as Animerco does.
    // Detect the challenge HTML first, then use status/headers as support.
    if (!_looksLikeBrowserChallenge(body)) return false;

    final server = (_headerValue(headers, 'server') ?? '').toLowerCase();
    final hasCloudflareHeaders =
        _cfServers.any(server.contains) ||
        _headerValue(headers, 'cf-ray') != null ||
        _headerValue(headers, 'cf-mitigated') != null;

    final code = statusCode ?? 0;
    return hasCloudflareHeaders || _cfErrorCodes.contains(code) || code == 200;
  }

  // ---------------------------------------------------------------------------
  // Solver
  // ---------------------------------------------------------------------------

  /// Solves the CF challenge and returns the actual page HTML.
  ///
  /// Different hosts solve concurrently. Same-host calls share one in-flight
  /// Future. At most [_maxConcurrentSpawns] WebViews are spawned at once to
  /// avoid GPU/RAM exhaustion; cached sessions are reused for free.
  Future<CfResult?> solveAndFetch(
    String url, {
    String? callerId,
    Future<void> Function(String host)? onSolved,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final rawHost = uri.host;
    if (rawHost.isEmpty) return null;
    final host = _normalizeHost(rawHost);
    // Per-caller cache key: plugin A's solved session is no longer
    // visible to plugin B, so B can't reuse A's cookies / fingerprint.
    // Audit H6 / PR-08d.
    final scopeKey = _scopeKey(callerId, host);

    // 1. Deduplicate: share an already-running solve for the same scope.
    final inFlight = _activeByHost[scopeKey];
    if (inFlight != null) {
      if (kDebugMode) debugPrint('$_tag Joining in-flight solve for $scopeKey');
      return inFlight;
    }

    // 2. Try reusing a cached solved session (free — no spawn slot needed).
    final cachedView = _hostWebViews[scopeKey];
    if (cachedView != null) {
      if (kDebugMode) {
        debugPrint('$_tag Reusing cached WebView for $scopeKey → $url');
      }
      try {
        final html = await cachedView.navigate(url);
        if (html != null && !_looksLikeBrowserChallenge(html)) {
          return CfResult(body: html, statusCode: 200, finalUrl: url);
        }
        if (kDebugMode) {
          debugPrint('$_tag Cached session stale for $scopeKey, disposing');
        }
        await _disposeHostSession(scopeKey);
      } catch (e) {
        if (kDebugMode) debugPrint('$_tag Cached WebView error: $e');
        await _disposeHostSession(scopeKey);
      }
    }

    // 3. Fresh solve — register future before any await so concurrent callers
    //    for this scope share it rather than spawning duplicate WebViews.
    final future = _freshSolve(url, host, scopeKey, onSolved: onSolved);
    _activeByHost[scopeKey] = future;
    try {
      return await future;
    } finally {
      final orphan = _activeByHost.remove(scopeKey);
      if (orphan != null) unawaited(orphan);
    }
  }

  /// Acquires a spawn slot, runs a fresh WebView solve, then releases the slot.
  /// [host] is the real hostname (used for the `onSolved` callback, which is
  /// where cookie injection per-host happens). [cacheKey] is the composite
  /// `"$caller::$host"` used to index the cache so plugin A's session can't
  /// be reused by plugin B (audit H6 / PR-08d).
  Future<CfResult?> _freshSolve(
    String url,
    String host,
    String cacheKey, {
    Future<void> Function(String host)? onSolved,
  }) async {
    await _acquireSpawnSlot();
    try {
      final result = await _fetchViaWebView(url, cacheKey);
      if (result != null && onSolved != null) await onSolved(host);
      return result;
    } finally {
      _releaseSpawnSlot();
    }
  }

  Future<void> _disposeHostSession(String cacheKey) async {
    final view = _hostWebViews.remove(cacheKey);
    if (view != null) {
      await view.dispose();
    }
  }

  static const _maxCachedWebViews = 2;

  Future<CfResult?> _fetchViaWebView(String url, String cacheKey) async {
    if (kDebugMode) debugPrint('$_tag Starting fresh solve for $url');

    // Evict oldest cached WebViews to prevent GPU memory exhaustion.
    while (_hostWebViews.length >= _maxCachedWebViews) {
      final oldest = _hostWebViews.keys.first;
      if (kDebugMode) debugPrint('$_tag Evicting cached WebView for $oldest');
      await _disposeHostSession(oldest);
    }

    final holder = _ViewHolder();
    CfResult? result;
    bool solved = false;
    bool checking = false;
    InAppWebViewController? capturedController;

    // SKYSTREAM_MEDIAFIRE_READY_V2
// Do not serialize MediaFire while its post-challenge document is still
// incomplete. The final CDN URL is placed in #downloadButton[href].
// This function is also used by cached WebView navigations, so it must
// continue completing holder.hostView after the initial solve.
Future<void> checkSolved(
  InAppWebViewController controller,
  String? currentUrl,
) async {
  if (checking) return;

  // During the tiny interval after the first capture and before the
  // cached _HostWebView is installed, ignore duplicate callbacks.
  if (solved && holder.hostView == null) return;

  checking = true;
  try {
    const readinessScript = r'''
    (function(){
      var t = (document.title || '').toLowerCase();
      var bodyText = (
        document.body && document.body.innerText
          ? document.body.innerText
          : ''
      ).toLowerCase();

      var titleChallenge =
          t.indexOf('just a moment') !== -1 ||
          t.indexOf('checking your browser') !== -1 ||
          t.indexOf('browser verification') !== -1 ||
          t.indexOf('attention required') !== -1 ||
          t.indexOf('verify you are human') !== -1 ||
          t.indexOf('verifying you are human') !== -1 ||
          t.indexOf('cloudflare') !== -1;

      var bodyChallenge =
          bodyText.indexOf('checking your browser') !== -1 ||
          bodyText.indexOf('browser verification') !== -1 ||
          bodyText.indexOf('enable javascript and cookies to continue') !== -1 ||
          bodyText.indexOf('verify you are human') !== -1 ||
          bodyText.indexOf('verifying you are human') !== -1 ||
          bodyText.indexOf('making sure you are not a bot') !== -1 ||
          bodyText.indexOf("making sure you're not a bot") !== -1;

      var domChallenge =
          !!document.getElementById('challenge-form') ||
          !!document.querySelector('[data-translate="checking_browser"]') ||
          !!document.querySelector('.cf-mitigated-content') ||
          !!document.querySelector('.cf-turnstile') ||
          !!document.querySelector('[src*="challenge-platform"]') ||
          typeof window._cf_chl_opt !== 'undefined';

      if (titleChallenge || bodyChallenge || domChallenge) {
        return '0';
      }

      var host = (location.hostname || '').toLowerCase();
      var isMediaFire =
          host === 'mediafire.com' ||
          host.slice(-14) === '.mediafire.com';

      // Preserve the previous behavior for every other website.
      if (!isMediaFire) return '1';

      // MediaFire can clear the challenge before the actual file page
      // finishes replacing the transitional document.
      if (document.readyState !== 'complete') return '0';

      var button =
          document.querySelector('#downloadButton') ||
          document.querySelector('a[aria-label="Download file"]') ||
          document.querySelector('a.input.popsok');
      if (!button) return '0';

      var href =
          button.getAttribute('href') ||
          button.href ||
          '';
      var direct =
          /^https:\/\/download[^.]*\.mediafire\.com\//i.test(href) ||
          /^https:\/\/[^/]+\.mediafireusercontent\.com\//i.test(href);
      if (!direct) return '0';

      // Give plugin.js a stable fallback marker in addition to the
      // ordinary #downloadButton[href] attribute.
      try {
        document.documentElement.setAttribute(
          'data-skystream-mediafire-direct',
          href
        );
      } catch (_) {}

      return '1';
    })()
    ''';

    var isReady = await controller.evaluateJavascript(
      source: readinessScript,
    );
    if (isReady != '1') return;

    final effectiveUrl = currentUrl ?? url;
    final effectiveHost =
        Uri.tryParse(effectiveUrl)?.host.toLowerCase() ?? '';
    final isMediaFire =
        effectiveHost == 'mediafire.com' ||
        effectiveHost.endsWith('.mediafire.com');

    if (isMediaFire) {
      // Ensure the final href/HTML has settled after the challenge.
      await Future<void>.delayed(
        const Duration(milliseconds: 450),
      );
      isReady = await controller.evaluateJavascript(
        source: readinessScript,
      );
      if (isReady != '1') return;
    }

    final html = await controller.evaluateJavascript(
      source: 'document.documentElement.outerHTML',
    );
    final body = html?.toString();
    if (body == null ||
        body.length < 500 ||
        _looksLikeBrowserChallenge(body)) {
      return;
    }

    if (kDebugMode && isMediaFire) {
      debugPrint(
        '$_tag MediaFire final HTML captured '
        '(${body.length} chars) from $effectiveUrl',
      );
    }

    result = CfResult(
      body: body,
      statusCode: 200,
      finalUrl: effectiveUrl,
    );

    if (!solved) solved = true;

    // Completes cached navigate() calls. It is harmless during the
    // first solve because holder.hostView is installed afterward.
    holder.hostView?.onLoaded(body);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('$_tag readiness check failed: $e');
    }
  } finally {
    checking = false;
  }
}

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      onWebViewCreated: (c) => capturedController = c,
      onLoadStop: (c, u) => checkSolved(c, u?.toString()),
      onTitleChanged: (c, t) {
        if (!solved) checkSolved(c, null);
      },
      onProgressChanged: (c, p) {
        if (p == 100) checkSolved(c, null);
      },
      onReceivedError: (c, r, e) {
        final isCancel =
            e.type == WebResourceErrorType.CANCELLED ||
            e.description.contains('-999') ||
            e.description.toLowerCase().contains('cancel');
        if (isCancel) {
          return;
        }
        holder.hostView?.onLoaded(null);
      },
      // Suppress console messages from cached pages (e.g. cinemacity's
      // content-protector.min.js polls the DOM in a tight setInterval,
      // flooding the platform channel with ~40 calls/sec of serialized
      // "[object Object]" strings).
      onConsoleMessage: (_, _) {},
    );

    try {
      await headless.run();
      final deadline = DateTime.now().add(_timeout);
      while (!solved && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(_pollInterval);
      }

      if (!solved) {
        await headless.dispose();
        return null;
      }

      final hostView = _HostWebView(cacheKey, headless, capturedController);
      holder.hostView = hostView;
      _hostWebViews[cacheKey] = hostView;
      hostView.startIdleTimer();

      // Silence the cached page's console to prevent scripts like
      // cinemacity's content-protector.min.js from flooding native logcat
      // and the plugin's method-channel debug layer with ~40 calls/sec.
      await hostView.silenceConsole();

      if (kDebugMode) debugPrint('$_tag WebView session ready for $cacheKey');
      return result;
    } catch (e) {
      await headless.dispose();
      return null;
    }
  }

  static String _normalizeHost(String host) {
    final h = host.toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  String? _headerValue(Map<String, dynamic> headers, String key) {
    final value = headers[key] ?? headers[key.toLowerCase()];
    if (value == null) return null;
    if (value is List) return value.isNotEmpty ? value.first.toString() : null;
    return value.toString();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _HostWebView {
  final String host;
  final HeadlessInAppWebView _headless;
  final InAppWebViewController? _controller;

  Completer<String?>? _pending;
  bool _disposed = false;
  Timer? _idleTimer;

  static const _idleTimeout = Duration(seconds: 90);

  _HostWebView(this.host, this._headless, this._controller);

  void startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, () {
      if (!_disposed) {
        try {
          dispose();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('${CloudflareBypass._tag} Idle timer dispose error: $e');
          }
        }
      }
    });
  }

  Future<String?> navigate(String url, {int retries = 1}) async {
    if (_disposed || _controller == null) return null;
    startIdleTimer();

    if (_pending != null && !_pending!.isCompleted) {
      await _pending!.future.catchError((_) => null);
    }

    _pending = Completer<String?>();
    try {
      await _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      final html = await _pending!.future.timeout(CloudflareBypass._navTimeout);

      if (html == null && retries > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return navigate(url, retries: retries - 1);
      }
      // Re-silence console after each navigation (page reload replaces overrides).
      await silenceConsole();
      return html;
    } on TimeoutException {
      if (!(_pending?.isCompleted ?? true)) _pending!.complete(null);
      return null;
    } catch (e) {
      return null;
    }
  }

  void onLoaded(String? html) {
    if (_pending != null && !_pending!.isCompleted) _pending!.complete(html);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    if (_pending != null && !_pending!.isCompleted) {
      if (kDebugMode) {
        debugPrint(
          '${CloudflareBypass._tag} $host: Cancelling active navigation and disposing',
        );
      }
      _pending!.complete(null);
    }
    try {
      if (CloudflareBypass.instance._hostWebViews[host] == this) {
        CloudflareBypass.instance._hostWebViews.remove(host);
      }
      await _headless.dispose();
    } catch (_) {}
  }

  /// Permanently seal all console methods so page scripts (e.g. cinemacity's
  /// content-protector.min.js running in a setInterval) cannot re-enable them
  /// and flood the platform channel with serialized messages.
  ///
  /// Simple assignment (`console.log = noop`) is undone by any script that
  /// re-assigns afterward. `Object.defineProperty` with configurable:false
  /// makes the property non-writable and non-configurable — subsequent writes
  /// silently no-op even inside setInterval callbacks.
  Future<void> silenceConsole() async {
    if (_disposed || _controller == null) return;
    try {
      await _controller.evaluateJavascript(
        source: '''
        (function() {
          var noop = function(){};
          var methods = ['log','info','debug','warn','error','dir','table',
                         'trace','group','groupCollapsed','groupEnd','clear',
                         'count','assert','time','timeLog','timeEnd','timeStamp'];
          methods.forEach(function(m) {
            try {
              Object.defineProperty(console, m, {
                get: function(){ return noop; },
                set: function(){},
                configurable: false
              });
            } catch(_) {}
          });
        })();
      ''',
      );
    } catch (_) {}
  }
}

class _ViewHolder {
  _HostWebView? hostView;
}

class CfResult {
  final String body;
  final int statusCode;
  final String finalUrl;
  const CfResult({
    required this.body,
    required this.statusCode,
    required this.finalUrl,
  });
}
