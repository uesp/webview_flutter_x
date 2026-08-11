// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'web_kit.g.dart';

/// Platform-agnostic scroll view for WKWebView on iOS ([UIScrollView]) and macOS
/// ([NSScrollView]).
class PlatformScrollView {
	PlatformScrollView._(this._uiScrollView, this._nsScrollView);

	final UIScrollView? _uiScrollView;
	final NSScrollView? _nsScrollView;

	/// Creates a [PlatformScrollView] from the native web view implementation.
	factory PlatformScrollView.from(WKWebView webView) {
		switch (webView) {
			case UIViewWKWebView():
				return PlatformScrollView._(webView.scrollView, null);
			case NSViewWKWebView():
				return PlatformScrollView._(null, webView.scrollView);
		}
		throw UnimplementedError('${webView.runtimeType} is not supported.');
	}

	/// Creates a [PlatformScrollView] from a linked macOS [NSScrollView].
	factory PlatformScrollView.fromLinkedMacScrollView(NSScrollView scrollView) {
		return PlatformScrollView._(null, scrollView);
	}

	Future<List<double>> getContentOffset() {
		if (_uiScrollView != null) {
			return _uiScrollView.getContentOffset();
		}
		return _nsScrollView!.getContentOffset();
	}

	Future<void> scrollBy(double x, double y) {
		if (_uiScrollView != null) {
			return _uiScrollView.scrollBy(x, y);
		}
		return _nsScrollView!.scrollBy(x, y);
	}

	Future<void> setContentOffset(double x, double y) {
		if (_uiScrollView != null) {
			return _uiScrollView.setContentOffset(x, y);
		}
		return _nsScrollView!.setContentOffset(x, y);
	}

	Future<void> setUiDelegate(UIScrollViewDelegate? delegate) {
		return _uiScrollView!.setDelegate(delegate);
	}

	Future<void> setNsDelegate(FWFNSScrollViewDelegate? delegate) {
		return _nsScrollView!.setDelegate(delegate);
	}

	Future<void> setBounces(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setBounces(value);
		}
		return _nsScrollView!.setBounces(value);
	}

	Future<void> setBouncesHorizontally(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setBouncesHorizontally(value);
		}
		return _nsScrollView!.setBouncesHorizontally(value);
	}

	Future<void> setBouncesVertically(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setBouncesVertically(value);
		}
		return _nsScrollView!.setBouncesVertically(value);
	}

	Future<void> setAlwaysBounceVertical(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setAlwaysBounceVertical(value);
		}
		return _nsScrollView!.setAlwaysBounceVertical(value);
	}

	Future<void> setAlwaysBounceHorizontal(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setAlwaysBounceHorizontal(value);
		}
		return _nsScrollView!.setAlwaysBounceHorizontal(value);
	}

	Future<void> setShowsVerticalScrollIndicator(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setShowsVerticalScrollIndicator(value);
		}
		return _nsScrollView!.setShowsVerticalScrollIndicator(value);
	}

	Future<void> setShowsHorizontalScrollIndicator(bool value) {
		if (_uiScrollView != null) {
			return _uiScrollView.setShowsHorizontalScrollIndicator(value);
		}
		return _nsScrollView!.setShowsHorizontalScrollIndicator(value);
	}

	Future<void> setBackgroundColor(UIColor color) {
		return _uiScrollView!.setBackgroundColor(color);
	}
}
