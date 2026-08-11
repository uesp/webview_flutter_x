// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import 'web_kit.g.dart';

final Expando<NSScrollView> _linkedScrollViewByWebView = Expando<NSScrollView>(
  'linkedScrollView',
);

final Expando<bool> _isScrollViewLinkedByWebView = Expando<bool>(
  'isScrollViewLinked',
);

final Expando<Future<bool>> _linkScrollViewFutureByWebView =
    Expando<Future<bool>>('linkScrollViewFuture');

final Expando<NSScrollView> _testingScrollViewOverrideByWebView =
    Expando<NSScrollView>('testingScrollViewOverride');

/// macOS scroll-view linking helpers for [NSViewWKWebView].
extension NSViewWKWebViewScroll on NSViewWKWebView {
  /// The linked native [NSScrollView] after [ensureNativeScrollViewLinked]
  /// succeeds.
  NSScrollView? get linkedNativeScrollView =>
      _isScrollViewLinkedByWebView[this] == true
          ? _linkedScrollViewByWebView[this]
          : null;

  /// Whether [linkedNativeScrollView] has been linked to the native scroll view.
  bool get isNativeScrollViewLinked => _isScrollViewLinkedByWebView[this] == true;

  /// Ensures the native [NSScrollView] pigeon attachment has completed.
  Future<bool> ensureNativeScrollViewLinked() async {
    if (isNativeScrollViewLinked) {
      return true;
    }
    final NSScrollView? testingScrollView =
        _testingScrollViewOverrideByWebView[this];
    if (testingScrollView != null) {
      _linkedScrollViewByWebView[this] = testingScrollView;
      _isScrollViewLinkedByWebView[this] = true;
      return true;
    }
    final Future<bool>? inProgress = _linkScrollViewFutureByWebView[this];
    if (inProgress != null) {
      return inProgress;
    }
    final Future<bool> linkFuture = _linkNativeScrollView();
    _linkScrollViewFutureByWebView[this] = linkFuture;
    try {
      return await linkFuture;
    } finally {
      _linkScrollViewFutureByWebView[this] = null;
    }
  }

  /// Clears a prior macOS scroll-view link so it can be re-established.
  void resetNativeScrollViewLink() {
    _isScrollViewLinkedByWebView[this] = false;
  }

  Future<bool> _linkNativeScrollView() async {
    final NSScrollView scrollView = NSScrollView.pigeon_detached();
    final int scrollViewIdentifier =
        PigeonInstanceManager.instance.addDartCreatedInstance(scrollView);
    try {
      await linkScrollViewByIdentifier(scrollViewIdentifier);
      _linkedScrollViewByWebView[this] =
          _testingScrollViewOverrideByWebView[this] ?? scrollView;
      _isScrollViewLinkedByWebView[this] = true;
      return true;
    } on Object {
      return false;
    }
  }
}

/// Pre-links [scrollView] for unit tests without native pigeon attachment.
@visibleForTesting
void linkMacScrollViewForTesting(
  NSViewWKWebView webView,
  NSScrollView scrollView,
) {
  _testingScrollViewOverrideByWebView[webView] = scrollView;
  _linkedScrollViewByWebView[webView] = scrollView;
  _isScrollViewLinkedByWebView[webView] = true;
}
