import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
		as android_wv;
import 'package:webview_flutter_x/src/scroll_event.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Extended [WebViewController] with document bridges and native scroll input.
class WebViewControllerPlus extends WebViewController {
	WebViewControllerPlus({
		super.onPermissionRequest,
	});

	//|----------------------------------------------------
	//| Properties
	//|----------------------------------------------------

	/// Whether the link long-press JS channel has been registered.
	bool _linkLongPressChannelRegistered = false;

	/// Whether the document click JS channel has been registered.
	bool _onClickChannelRegistered = false;

	/// Whether the document scroll-gesture JS channel has been registered.
	bool _onScrollChannelRegistered = false;

	/// Whether the document resize JS channel has been registered.
	bool _onResizeChannelRegistered = false;

	/// Running total scroll offset accumulated from scroll deltas; reset on page load.
	Offset _scrollOffset = Offset.zero;

	/// Background color applied on navigation and page load.
	Color? _backgroundColor;

	/// Last padding passed to [setPadding]; reapplied after each page load.
	EdgeInsets? _padding;

	/// Handler for link long-press / context-menu URLs from injected JS.
	void Function(String url)? _onLinkClick;

	/// Handler for document tap / press from injected JS.
	void Function()? _onClick;

	/// Handler for user-driven scroll input.
	void Function(ScrollEvent event)? _onScroll;

	/// Handler for document layout/resize changes from injected JS.
	void Function(Size size)? _onResize;

	//|----------------------------------------------------
	//| Constants
	//|----------------------------------------------------

	/// How long to wait before triggering a long press on a link.
	static const double LINK_LONG_PRESS_DELAY = 500.0;

	/// Dedupe window for duplicate [LinkLongPress] posts for the same URL.
	static const double LINK_LONG_PRESS_DELAY_DEDUPE = 400.0;

	//|----------------------------------------------------
	//| Stock plus APIs
	//|----------------------------------------------------

	/// Return the height of [WebViewWidget]
	Future<double> get webViewHeight => _getWebViewHeight();

	Future<double> _getWebViewHeight() async {
		String getHeightScript = r"""(function () {
                var element = document.body;
                var height = element.offsetHeight,
                    style = window.getComputedStyle(element)
                return ['top', 'bottom']
                    .map(function (side) {
                        return parseInt(style["margin-" + side]);
                    }).reduce(function (total, side) {
                        return total + side;
                    }, height)
            })();""";

		return double.parse(
				(await super.runJavaScriptReturningResult(getHeightScript))
						.toString());
	}

	/// Load assets on the local server. [LocalHostServer] must be running.
	///
	/// [method] must be one of the supported HTTP methods in [LoadRequestMethod].
	///
	/// If [headers] is not empty, its key-value pairs will be added as the
	/// headers for the request.
	///
	/// If [body] is not null, it will be added as the body for the request.
	///
	/// Throws an ArgumentError if [uri] has an empty scheme.
	Future<void> loadFlutterAssetWithServer(
		String uri,
		int port, {
		LoadRequestMethod method = LoadRequestMethod.get,
		Map<String, String> headers = const <String, String>{},
		Uint8List? body,
	}) async {
		return super.loadRequest(Uri.parse('http://localhost:$port/$uri'),
				headers: headers, body: body, method: method);
	}

	//|----------------------------------------------------
	//| Document bridges
	//|----------------------------------------------------

	/// Registers [onScroll] for user-driven scroll input.
	///
	/// Platform matrix:
	/// - **iOS / macOS:** native [WebKitWebViewController.setOnScrollGesture].
	/// - **Android:** native [android_wv.AndroidWebViewController.setOnScrollGesture].
	/// - **Other desktop:** JavaScript `wheel` → [OnScroll].
	void setOnScrollListener(void Function(ScrollEvent event)? onScroll) {
		if (onScroll == null) return;
		_onScroll = onScroll;
		if (_isApple) {
			final controller = platform as WebKitWebViewController;
			controller.setOnScrollGesture((event) {
				_buildScrollEvent(
					eventType: _phaseFromApple(event.eventType),
					delta: event.delta,
					velocity: event.velocity,
					globalPosition: event.globalPosition,
					localPosition: event.localPosition,
				);
			}, consume: true);
			return;
		}
		if (defaultTargetPlatform == TargetPlatform.android) {
			final controller = platform as android_wv.AndroidWebViewController;
			controller.setOnScrollGesture((event) {
				_buildScrollEvent(
					eventType: _phaseFromAndroid(event.eventType),
					delta: event.delta,
					velocity: event.velocity,
					globalPosition: event.globalPosition,
					localPosition: event.localPosition,
				);
			}, consume: true);
			return;
		}
		if (_onScrollChannelRegistered) return;
		_onScrollChannelRegistered = true;
		addJavaScriptChannel(
			'OnScroll',
			onMessageReceived: _onScrollMessage,
		);
	}

	/// Forwards [onScrollPositionChange] to [setOnScrollPositionChange] on the
	/// platform controller.
	Future<void> setOnScrollPositionChangeListener(
		void Function(ScrollPositionChange scrollPositionChange)?
				onScrollPositionChange,
	) =>
			setOnScrollPositionChange(onScrollPositionChange);

	/// Long-press and context-menu on links; JS is reinjected on each
	/// [NavigationDelegate.onPageFinished].
	void setLinkClickListener(void Function(String url)? onLinkClick) {
		_onLinkClick = onLinkClick;
		if (onLinkClick == null) return;
		if (_linkLongPressChannelRegistered) return;
		_linkLongPressChannelRegistered = true;
		addJavaScriptChannel(
			'LinkLongPress',
			onMessageReceived: (JavaScriptMessage message) {
				final url = message.message;
				if (url.isNotEmpty) _onLinkClick?.call(url);
			},
		);
	}

	/// Document tap / press; JS is reinjected on each
	/// [NavigationDelegate.onPageFinished].
	void setOnClickListener(void Function()? onClick) {
		_onClick = onClick;
		if (onClick == null) return;
		if (_onClickChannelRegistered) return;
		_onClickChannelRegistered = true;
		addJavaScriptChannel(
			'OnClick',
			onMessageReceived: (_) {
				_onClick?.call();
			},
		);
	}

	/// Document layout/resize changes; JS is reinjected on each
	/// [NavigationDelegate.onPageFinished].
	/// Posts the document size whenever the layout settles (fonts, images, async content).
	void setOnResizeListener(void Function(Size size)? onResize) {
		_onResize = onResize;
		if (onResize == null) return;
		if (_onResizeChannelRegistered) return;
		_onResizeChannelRegistered = true;
		addJavaScriptChannel(
			'OnResize',
			onMessageReceived: _onResizeMessage,
		);
	}

	/// Returns the scrollable height of the web document in logical pixels.
	Future<double> getContentHeight() async {
		const script = r"""(function () {
			var body = document.body;
			var doc = document.documentElement;
			return Math.max(
				body.scrollHeight, body.offsetHeight,
				doc.scrollHeight, doc.offsetHeight
			);
		})();""";
		try {
			final result = await runJavaScriptReturningResult(script);
			return double.tryParse(result.toString()) ?? 0;
		} catch (_) {
			return 0;
		}
	}

	/// Set the background color of the webview.
	void setBackground(Color? color) {
		if (color != null) _backgroundColor = color;
		final applied = _backgroundColor;
		if (applied == null) return;
		setBackgroundColor(applied);
	}

	/// Set padding around document body using Flutter [EdgeInsets].
	void setPadding(EdgeInsets? padding) {
		if (padding != null) _padding = padding;
		final applied = _padding;
		if (applied == null) return;
		runJavaScript(
				"if (document.body) { var s = document.body.style; s.paddingTop = '${applied.top}px'; s.paddingRight = '${applied.right}px'; s.paddingBottom = '${applied.bottom}px'; s.paddingLeft = '${applied.left}px'; }");
	}

	/// Scrolls the loaded document to vertical offset [y] via native [scrollTo].
	///
	/// Android's native [scrollTo] expects physical pixels, so pass
	/// [devicePixelRatio] on Android (defaults to `1`).
	void scrollToY(double y, {double devicePixelRatio = 1}) {
		if (defaultTargetPlatform == TargetPlatform.android) {
			y *= devicePixelRatio;
		}
		scrollTo(0, y.round());
	}

	/// Wraps [delegate] to reapply background color and padding and reinject
	/// document listeners on each navigation event.
	@override
	Future<void> setNavigationDelegate(NavigationDelegate delegate) {
		return super.setNavigationDelegate(NavigationDelegate(
			onNavigationRequest: (request) {
				setBackground(null);
				setPadding(null);
				final handler = delegate.onNavigationRequest;
				if (handler == null) return NavigationDecision.navigate;
				return handler(request);
			},
			onPageStarted: (url) {
				setBackground(null);
				setPadding(null);
				delegate.onPageStarted?.call(url);
			},
			onPageFinished: (url) {
				setBackground(null);
				_injectDocumentListeners();
				setPadding(null);
				delegate.onPageFinished?.call(url);
			},
			onProgress: delegate.onProgress,
			onWebResourceError: delegate.onWebResourceError,
		));
	}

	//|----------------------------------------------------
	//| Internal
	//|----------------------------------------------------

	bool get _isApple =>
			defaultTargetPlatform == TargetPlatform.iOS ||
			defaultTargetPlatform == TargetPlatform.macOS;

	bool get _isDesktop =>
			defaultTargetPlatform == TargetPlatform.macOS ||
			defaultTargetPlatform == TargetPlatform.linux ||
			defaultTargetPlatform == TargetPlatform.windows;

	/// Injects listeners registered via the document bridge setters.
	void _injectDocumentListeners() {
		scrollToY(0);
		_scrollOffset = Offset.zero;
		if (_onLinkClick != null) _injectLinkLongPressListener();
		if (_onClick != null) _injectClickListener();
		if (_onScroll != null) _injectScrollListener();
		if (_onResize != null) _injectResizeListener();
	}

	/// Parses an [OnResize] message and forwards the document size to [_onResize].
	void _onResizeMessage(JavaScriptMessage message) {
		try {
			final data = jsonDecode(message.message) as Map<String, dynamic>;
			_onResize
					?.call(Size(_getCoord(data, 'width'), _getCoord(data, 'height')));
		} catch (_) {}
	}

	/// Parses an [OnScroll] message and forwards it to [_buildScrollEvent].
	void _onScrollMessage(JavaScriptMessage message) {
		try {
			final data = jsonDecode(message.message) as Map<String, dynamic>;
			final globalPosition = _globalPositionFrom(data);
			final localPosition = _localPositionFrom(data);
			switch (data['event'] as String?) {
				case 'start':
					_buildScrollEvent(
							eventType: ScrollEventPhase.start,
							delta: Offset.zero,
							velocity: Offset.zero,
							globalPosition: globalPosition,
							localPosition: localPosition);
				case 'end':
					_buildScrollEvent(
							eventType: ScrollEventPhase.end,
							delta: Offset.zero,
							velocity: Offset(
									_getCoord(data, 'velocityX'), _getCoord(data, 'velocityY')),
							globalPosition: globalPosition,
							localPosition: localPosition);
				case 'cancel':
					_buildScrollEvent(
							eventType: ScrollEventPhase.cancel,
							delta: Offset.zero,
							velocity: Offset.zero,
							globalPosition: globalPosition,
							localPosition: localPosition);
				case 'update' || _:
					_buildScrollEvent(
							eventType: ScrollEventPhase.update,
							delta: Offset(
									_getCoord(data, 'deltaX'), _getCoord(data, 'deltaY')),
							velocity: Offset.zero,
							globalPosition: globalPosition,
							localPosition: localPosition);
			}
		} catch (_) {}
	}

	/// Builds a [ScrollEvent] and forwards it to [_onScroll].
	void _buildScrollEvent({
		required ScrollEventPhase eventType,
		required Offset delta,
		required Offset velocity,
		Offset? globalPosition,
		Offset? localPosition,
	}) {
		_scrollOffset += delta;
		final event = ScrollEvent(
			eventType: eventType,
			delta: delta,
			velocity: velocity,
			offset: _scrollOffset,
			globalPosition: globalPosition,
			localPosition: localPosition,
		);
		_onScroll?.call(event);
	}

	/// Injects the platform-specific user-scroll bridge.
	///
	/// Platform matrix:
	/// - **macOS:** `preventDefault` on wheel only (native gesture is already
	///   consumed via [WebKitWebViewController.setOnScrollGesture]; AppKit still
	///   delivers wheel to the document unless JS blocks it).
	/// - **iOS / Android:** no JS — native `consume` disables platform scrolling.
	/// - **Other desktop:** posts wheel deltas to [OnScroll].
	void _injectScrollListener() {
		if (defaultTargetPlatform == TargetPlatform.macOS) {
			runJavaScript(
				"(function(){var key='__OnScrollBridge';var prev=window[key];if(prev&&prev.remove){prev.remove();}function onWheel(e){e.preventDefault();}window.addEventListener('wheel',onWheel,{passive:false});window[key]={remove:function(){window.removeEventListener('wheel',onWheel);}};})();",
			);
			return;
		} else if (defaultTargetPlatform == TargetPlatform.iOS ||
				defaultTargetPlatform == TargetPlatform.android) {
			return;
		} else if (_isDesktop) {
			runJavaScript(
				"(function(){var key='__OnScrollBridge';var prev=window[key];if(prev&&prev.remove){prev.remove();}function onWheel(e){if(window.OnScroll&&window.OnScroll.postMessage){OnScroll.postMessage(JSON.stringify({deltaX:e.deltaX,deltaY:e.deltaY,globalX:e.screenX,globalY:e.screenY,localX:e.clientX,localY:e.clientY,hasPreciseDeltas:e.deltaMode===0}));}}window.addEventListener('wheel',onWheel,{passive:true});window[key]={remove:function(){window.removeEventListener('wheel',onWheel);}};})();",
			);
			return;
		} else {
			throw UnimplementedError(
					'Unsupported platform: $defaultTargetPlatform');
		}
	}

	/// Injects a [ResizeObserver] that posts the document size to [OnResize].
	void _injectResizeListener() {
		runJavaScript(
			"(function(){var key='__OnResizeBridge';var prev=window[key];if(prev&&prev.remove){prev.remove();}function measure(){var body=document.body;var doc=document.documentElement;var h=Math.max(body.scrollHeight,body.offsetHeight,doc.scrollHeight,doc.offsetHeight);var w=Math.max(body.scrollWidth,body.offsetWidth,doc.scrollWidth,doc.offsetWidth);if(window.OnResize&&window.OnResize.postMessage){OnResize.postMessage(JSON.stringify({width:w,height:h}));}}var ro=new ResizeObserver(measure);ro.observe(document.documentElement);if(document.body)ro.observe(document.body);if(document.fonts&&document.fonts.ready){document.fonts.ready.then(measure);}window.addEventListener('load',measure);measure();window[key]={remove:function(){ro.disconnect();window.removeEventListener('load',measure);}};})();",
		);
	}

	/// Injects link long-press listener so link long-presses post to [LinkLongPress].
	void _injectLinkLongPressListener() {
		final onContextMenuJS = defaultTargetPlatform == TargetPlatform.macOS
				? 'function onContextMenu(e){var href=hrefFrom(e.target);if(href)send(href);e.preventDefault();}'
				: 'function onContextMenu(e){var href=hrefFrom(e.target);if(!href)return;e.preventDefault();send(href);}';
		runJavaScript(
			'(function(){var key=\'__LinkLongPressBridge\';var prev=window[key];if(prev&&prev.remove){prev.remove();}var LONG_MS=$LINK_LONG_PRESS_DELAY;var SLOP_SQ=100;var DEDUPE_MS=$LINK_LONG_PRESS_DELAY_DEDUPE;var longPressTimer=null;var anchorHref=null;var startXY=null;var lastSent=0;var lastUrl=\'\';var suppressClickHref=null;function hrefFrom(el){while(el&&el!==document){if(el.tagName===\'A\'&&el.href)return el.href;el=el.parentElement;}return null;}function send(url){var now=Date.now();if(url===lastUrl&&now-lastSent<DEDUPE_MS)return;lastUrl=url;lastSent=now;suppressClickHref=url;LinkLongPress.postMessage(url);}$onContextMenuJS function cancelPress(){clearTimeout(longPressTimer);longPressTimer=null;anchorHref=null;startXY=null;}function onPointerDown(e){if(e.pointerType===\'mouse\'&&e.button!==0)return;var href=hrefFrom(e.target);if(!href){suppressClickHref=null;return;}cancelPress();anchorHref=href;startXY={x:e.clientX,y:e.clientY};longPressTimer=setTimeout(function(){longPressTimer=null;if(anchorHref)send(anchorHref);cancelPress();},LONG_MS);}function onPointerMove(e){if(!anchorHref||!startXY)return;var h=hrefFrom(e.target);if(h!==anchorHref){cancelPress();return;}var dx=e.clientX-startXY.x,dy=e.clientY-startXY.y;if(dx*dx+dy*dy>SLOP_SQ)cancelPress();}function onPointerEnd(e){cancelPress();}function onClick(e){if(!suppressClickHref)return;var href=hrefFrom(e.target);if(href===suppressClickHref){e.preventDefault();e.stopPropagation();if(e.stopImmediatePropagation)e.stopImmediatePropagation();}suppressClickHref=null;}document.addEventListener(\'contextmenu\',onContextMenu,true);document.addEventListener(\'click\',onClick,true);document.addEventListener(\'pointerdown\',onPointerDown,{passive:true,capture:true});document.addEventListener(\'pointermove\',onPointerMove,{passive:true,capture:true});document.addEventListener(\'pointerup\',onPointerEnd,{passive:true,capture:true});document.addEventListener(\'pointercancel\',onPointerEnd,{passive:true,capture:true});window[key]={remove:function(){cancelPress();suppressClickHref=null;document.removeEventListener(\'contextmenu\',onContextMenu,true);document.removeEventListener(\'click\',onClick,true);document.removeEventListener(\'pointerdown\',onPointerDown,{capture:true});document.removeEventListener(\'pointermove\',onPointerMove,{capture:true});document.removeEventListener(\'pointerup\',onPointerEnd,{capture:true});document.removeEventListener(\'pointercancel\',onPointerEnd,{capture:true});}};})();',
		);
	}

	/// Injects document onClick listener so document clicks post to [OnClick].
	void _injectClickListener() {
		runJavaScript(
			"(function(){var key='__OnClickBridge';var prev=window[key];if(prev&&prev.remove){prev.remove();}var lastAt=0;var DEDUPE_MS=40;function notify(){var now=Date.now();if(now-lastAt<DEDUPE_MS)return;lastAt=now;OnClick.postMessage('click');}function onPointerDown(){notify();}function onMouseDown(){notify();}function onTouchStart(){notify();}document.addEventListener('pointerdown',onPointerDown,{passive:true,capture:true});document.addEventListener('mousedown',onMouseDown,{passive:true,capture:true});document.addEventListener('touchstart',onTouchStart,{passive:true,capture:true});window[key]={remove:function(){document.removeEventListener('pointerdown',onPointerDown,{capture:true});document.removeEventListener('mousedown',onMouseDown,{capture:true});document.removeEventListener('touchstart',onTouchStart,{capture:true});}};})();",
		);
	}

	double _getCoord(Map<String, dynamic> data, String key) =>
			(data[key] as num?)?.toDouble() ?? 0;

	Offset? _globalPositionFrom(Map<String, dynamic> data) {
		if (data.containsKey('globalX') || data.containsKey('globalY')) {
			return Offset(_getCoord(data, 'globalX'), _getCoord(data, 'globalY'));
		}
		if (data.containsKey('screenX') || data.containsKey('screenY')) {
			return Offset(_getCoord(data, 'screenX'), _getCoord(data, 'screenY'));
		}
		return null;
	}

	Offset? _localPositionFrom(Map<String, dynamic> data) {
		if (data.containsKey('localX') || data.containsKey('localY')) {
			return Offset(_getCoord(data, 'localX'), _getCoord(data, 'localY'));
		}
		return null;
	}

	ScrollEventPhase _phaseFromApple(ScrollGesturePhase phase) => switch (phase) {
				ScrollGesturePhase.start => ScrollEventPhase.start,
				ScrollGesturePhase.update => ScrollEventPhase.update,
				ScrollGesturePhase.end => ScrollEventPhase.end,
				ScrollGesturePhase.cancel => ScrollEventPhase.cancel,
			};

	ScrollEventPhase _phaseFromAndroid(android_wv.ScrollGesturePhase phase) =>
			switch (phase) {
				android_wv.ScrollGesturePhase.start => ScrollEventPhase.start,
				android_wv.ScrollGesturePhase.update => ScrollEventPhase.update,
				android_wv.ScrollGesturePhase.end => ScrollEventPhase.end,
				android_wv.ScrollGesturePhase.cancel => ScrollEventPhase.cancel,
			};
}
