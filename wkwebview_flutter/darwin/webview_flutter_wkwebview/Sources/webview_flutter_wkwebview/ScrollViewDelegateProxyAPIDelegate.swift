// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import UIKit
  import WebKit
#elseif os(macOS)
  import AppKit
  import FlutterMacOS
#endif

#if os(iOS)
  import Flutter

  /// Implementation of `UIScrollViewDelegate` that calls to Dart in callback methods.
  class ScrollViewDelegateImpl: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let api: PigeonApiProtocolUIScrollViewDelegate
    unowned let registrar: ProxyAPIRegistrar

    weak var gestureScrollView: UIScrollView?
    weak var gestureWebView: WKWebView?
    var panGestureRecognizer: UIPanGestureRecognizer?
    var consumeScrollGestures = false
    var previousScrollEnabled: Bool?
    var lastPanTranslation = CGPoint.zero

    init(api: PigeonApiProtocolUIScrollViewDelegate, registrar: ProxyAPIRegistrar) {
      self.api = api
      self.registrar = registrar
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.scrollViewDidScroll(
          pigeonInstance: self, scrollView: scrollView, x: scrollView.contentOffset.x,
          y: scrollView.contentOffset.y
        ) { result in
          if case .failure(let error) = result {
            onFailure("UIScrollViewDelegate.scrollViewDidScroll", error)
          }
        }
      }
    }

    /// Attaches a pan recognizer that reports scroll gestures to Dart.
    ///
    /// When `consume` is true, native `UIScrollView` scrolling is disabled while
    /// attached so Flutter can own the scroll position.
    ///
    /// Installation waits until [webView] is in a window so it can attach to
    /// Flutter's `FlutterTouchInterceptingView` (where platform-view touches
    /// actually arrive). Long-press / selection recognizers are disabled.
    ///
    /// Prefer [onWebViewMovedToWindow] (via `WebViewImpl.didMoveToWindow`) over
    /// KVO on `window` — the latter does not fire for Flutter platform views.
    func attachScrollGesture(to webView: WKWebView, consume: Bool) {
      detachScrollGesture()
      gestureWebView = webView
      gestureScrollView = webView.scrollView
      consumeScrollGestures = consume
      if consume {
        previousScrollEnabled = webView.scrollView.isScrollEnabled
        webView.scrollView.isScrollEnabled = false
      }
      disableSelectionRecognizers(in: webView)
      if webView.window != nil {
        installPan(on: webView)
      } else {
        // Next run-loop: platform view may already be inserting us into a window.
        DispatchQueue.main.async { [weak self, weak webView] in
          guard let self, let webView, webView.window != nil else { return }
          self.installPan(on: webView)
        }
      }
    }

    /// Called from `WebViewImpl.didMoveToWindow` once the view is in a window.
    func onWebViewMovedToWindow() {
      guard let webView = gestureWebView, webView.window != nil else { return }
      installPan(on: webView)
    }

    func detachScrollGesture() {
      if let pan = panGestureRecognizer {
        pan.view?.removeGestureRecognizer(pan)
      }
      panGestureRecognizer = nil
      if consumeScrollGestures, let scrollView = gestureScrollView,
        let previous = previousScrollEnabled
      {
        scrollView.isScrollEnabled = previous
      }
      previousScrollEnabled = nil
      consumeScrollGestures = false
      gestureScrollView = nil
      gestureWebView = nil
      lastPanTranslation = .zero
    }

    /// Installs the pan on Flutter's touch-intercepting wrapper when present.
    private func installPan(on webView: WKWebView) {
      // Prefer FlutterTouchInterceptingView; re-home if we attached to WKWebView early.
      let host = flutterTouchInterceptingView(from: webView) ?? webView
      if let existing = panGestureRecognizer {
        if existing.view === host { return }
        existing.view?.removeGestureRecognizer(existing)
        panGestureRecognizer = nil
      }
      disableSelectionRecognizers(in: webView)
      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
      pan.delegate = self
      pan.cancelsTouchesInView = false
      pan.delaysTouchesBegan = false
      pan.delaysTouchesEnded = false
      pan.maximumNumberOfTouches = 1
      host.addGestureRecognizer(pan)
      panGestureRecognizer = pan
    }

    /// Turns off long-press / selection gesture recognizers under [root].
    private func disableSelectionRecognizers(in root: UIView) {
      for recognizer in root.gestureRecognizers ?? [] {
        if recognizer is UILongPressGestureRecognizer {
          recognizer.isEnabled = false
        }
      }
      for subview in root.subviews {
        disableSelectionRecognizers(in: subview)
      }
    }

    /// Flutter wraps each UiKitView in `FlutterTouchInterceptingView`.
    private func flutterTouchInterceptingView(from view: UIView) -> UIView? {
      var current: UIView? = view
      while let currentView = current {
        if String(describing: type(of: currentView)).contains("FlutterTouchIntercepting") {
          return currentView
        }
        current = currentView.superview
      }
      return nil
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let scrollView = gestureScrollView else {
        return
      }
      let translation = recognizer.translation(in: scrollView)
      let localPoint = recognizer.location(in: scrollView)
      let globalPoint = flutterGlobalPoint(for: localPoint, in: scrollView)
      let timestamp = ProcessInfo.processInfo.systemUptime

      switch recognizer.state {
      case .began:
        lastPanTranslation = translation
        reportScrollGesture(
          scrollView: scrollView,
          eventType: .start,
          timestamp: timestamp,
          globalX: globalPoint.x,
          globalY: globalPoint.y,
          localX: localPoint.x,
          localY: localPoint.y,
          deltaX: 0,
          deltaY: 0,
          velocityX: 0,
          velocityY: 0
        )
      case .changed:
        let deltaX = translation.x - lastPanTranslation.x
        let deltaY = translation.y - lastPanTranslation.y
        lastPanTranslation = translation
        if deltaX == 0 && deltaY == 0 {
          return
        }
        reportScrollGesture(
          scrollView: scrollView,
          eventType: .update,
          timestamp: timestamp,
          globalX: globalPoint.x,
          globalY: globalPoint.y,
          localX: localPoint.x,
          localY: localPoint.y,
          deltaX: deltaX,
          deltaY: deltaY,
          velocityX: 0,
          velocityY: 0
        )
      case .ended:
        let velocity = recognizer.velocity(in: scrollView)
        let deltaX = translation.x - lastPanTranslation.x
        let deltaY = translation.y - lastPanTranslation.y
        if deltaX != 0 || deltaY != 0 {
          reportScrollGesture(
            scrollView: scrollView,
            eventType: .update,
            timestamp: timestamp,
            globalX: globalPoint.x,
            globalY: globalPoint.y,
            localX: localPoint.x,
            localY: localPoint.y,
            deltaX: deltaX,
            deltaY: deltaY,
            velocityX: 0,
            velocityY: 0
          )
        }
        reportScrollGesture(
          scrollView: scrollView,
          eventType: .end,
          timestamp: timestamp,
          globalX: globalPoint.x,
          globalY: globalPoint.y,
          localX: localPoint.x,
          localY: localPoint.y,
          deltaX: 0,
          deltaY: 0,
          velocityX: velocity.x,
          velocityY: velocity.y
        )
        lastPanTranslation = .zero
      case .cancelled, .failed:
        reportScrollGesture(
          scrollView: scrollView,
          eventType: .cancel,
          timestamp: timestamp,
          globalX: globalPoint.x,
          globalY: globalPoint.y,
          localX: localPoint.x,
          localY: localPoint.y,
          deltaX: 0,
          deltaY: 0,
          velocityX: 0,
          velocityY: 0
        )
        lastPanTranslation = .zero
      default:
        break
      }
    }

    /// Must recognize alongside Flutter's forwarding recognizer on the
    /// touch-intercepting wrapper; returning false cancels the pan.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      return true
    }

    private func reportScrollGesture(
      scrollView: UIScrollView,
      eventType: FWFNSScrollWheelPhase,
      timestamp: TimeInterval,
      globalX: CGFloat,
      globalY: CGFloat,
      localX: CGFloat,
      localY: CGFloat,
      deltaX: CGFloat,
      deltaY: CGFloat,
      velocityX: CGFloat,
      velocityY: CGFloat
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.scrollGesture(
          pigeonInstance: self,
          scrollView: scrollView,
          eventType: eventType,
          timestamp: timestamp,
          globalX: globalX,
          globalY: globalY,
          localX: localX,
          localY: localY,
          deltaX: deltaX,
          deltaY: deltaY,
          velocityX: velocityX,
          velocityY: velocityY
        ) { result in
          if case .failure(let error) = result {
            onFailure("UIScrollViewDelegate.scrollGesture", error)
          }
        }
      }
    }

    /// Maps a point in `view` to Flutter global (window-relative logical) coordinates.
    private func flutterGlobalPoint(for localPoint: CGPoint, in view: UIView) -> CGPoint {
      guard let flutterView = flutterContentView(from: view) else {
        return view.convert(localPoint, to: nil)
      }
      return view.convert(localPoint, to: flutterView)
    }

    private func flutterContentView(from view: UIView) -> UIView? {
      var current: UIView? = view
      while let currentView = current {
        if String(describing: type(of: currentView)).hasPrefix("FlutterView") {
          return currentView
        }
        current = currentView.superview
      }
      return nil
    }
  }
#endif

#if os(macOS)
  /// Observes macOS scroll view content offset and reports changes to Dart.
  class FWFNSScrollViewDelegateImpl: NSObject, FWFNSScrollViewDelegate {
    let api: PigeonApiProtocolFWFNSScrollViewDelegate
    unowned let registrar: ProxyAPIRegistrar
    weak var scrollView: NSScrollView?
    var contentViewBoundsObserver: NSObjectProtocol?

    weak var wheelView: NSView?
    var scrollWheelMonitor: Any?
    var consumeScrollWheelEvents = false
    var mouseWheelIdleTimer: Timer?
    var mouseWheelActive = false
    var lastScrollWheelEvent: NSEvent?
    /// Whether a precise (trackpad) scroll gesture that began inside the target
    /// view is still in progress. Latched so the rest of the gesture keeps
    /// delivering even if the target view moves out from under the pointer.
    var preciseGestureActive = false

    private static let MOUSE_WHEEL_IDLE_END_INTERVAL: TimeInterval = 0.12

    init(api: PigeonApiProtocolFWFNSScrollViewDelegate, registrar: ProxyAPIRegistrar) {
      self.api = api
      self.registrar = registrar
    }

    func attach(to scrollView: NSScrollView) {
      detach()
      self.scrollView = scrollView
      scrollView.contentView.postsBoundsChangedNotifications = true
      reportScrollPosition(for: scrollView)
      contentViewBoundsObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: scrollView.contentView,
        queue: .main
      ) { [weak self] _ in
        guard let self, let scrollView = self.scrollView else { return }
        self.reportScrollPosition(for: scrollView)
      }
    }

    func detach() {
      if let observer = contentViewBoundsObserver {
        NotificationCenter.default.removeObserver(observer)
        contentViewBoundsObserver = nil
      }
      scrollView?.contentView.postsBoundsChangedNotifications = false
      scrollView = nil
    }

    func attachScrollWheel(to view: NSView, consume: Bool) {
      detachScrollWheel()
      wheelView = view
      consumeScrollWheelEvents = consume
      scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
        [weak self] event in
        guard let self, let targetView = self.wheelView else { return event }
        guard let window = targetView.window, event.window == window else { return event }
        let locationInView = targetView.convert(event.locationInWindow, from: nil)
        let inBounds = targetView.bounds.contains(locationInView)
        guard self.shouldHandleScrollWheel(event: event, inBounds: inBounds) else { return event }
        self.handleScrollWheel(event: event, view: targetView)
        return self.consumeScrollWheelEvents ? nil : event
      }
    }

    /// Decides whether a scroll-wheel event should be forwarded.
    ///
    /// Discrete mouse-wheel events (no phase) are gated on the pointer being
    /// inside the target view. Precise trackpad gestures are latched on their
    /// start: once a gesture begins in-bounds it keeps delivering until it ends,
    /// even if the target view moves out from under the pointer mid-gesture.
    private func shouldHandleScrollWheel(event: NSEvent, inBounds: Bool) -> Bool {
      let phase = event.phase
      let momentum = event.momentumPhase

      // Discrete mouse wheel carries no phase information; gate per-event.
      if phase.isEmpty && momentum.isEmpty {
        return inBounds
      }

      if phase.contains(.began) || phase.contains(.mayBegin) {
        preciseGestureActive = inBounds
      } else if phase.contains(.cancelled)
        || momentum.contains(.ended) || momentum.contains(.cancelled)
      {
        let wasActive = preciseGestureActive
        preciseGestureActive = false
        return wasActive
      }
      return preciseGestureActive
    }

    func detachScrollWheel() {
      mouseWheelIdleTimer?.invalidate()
      mouseWheelIdleTimer = nil
      mouseWheelActive = false
      preciseGestureActive = false
      lastScrollWheelEvent = nil
      if let monitor = scrollWheelMonitor {
        NSEvent.removeMonitor(monitor)
        scrollWheelMonitor = nil
      }
      wheelView = nil
      consumeScrollWheelEvents = false
    }

    private func handleScrollWheel(event: NSEvent, view: NSView) {
      lastScrollWheelEvent = event
      let eventType = mapPhase(for: event, view: view)
      let isMomentum = !event.momentumPhase.isEmpty
      let hasPreciseDeltas = event.hasPreciseScrollingDeltas
      let deltaX = hasPreciseDeltas ? event.scrollingDeltaX : event.deltaX
      let deltaY = hasPreciseDeltas ? event.scrollingDeltaY : event.deltaY
      let globalPoint = flutterGlobalPoint(for: event, view: view)
      let localPoint = view.convert(event.locationInWindow, from: nil)
      reportScrollWheel(
        scrollView: nil,
        eventType: eventType,
        timestamp: event.timestamp,
        globalX: globalPoint.x,
        globalY: globalPoint.y,
        localX: localPoint.x,
        localY: localPoint.y,
        deltaX: deltaX,
        deltaY: deltaY,
        isMomentum: isMomentum,
        hasPreciseDeltas: hasPreciseDeltas
      )
    }

    private func activePhase(for event: NSEvent) -> NSEvent.Phase {
      if !event.momentumPhase.isEmpty {
        return event.momentumPhase
      }
      return event.phase
    }

    private func mapPhase(for event: NSEvent, view: NSView) -> FWFNSScrollWheelPhase {
      let phase = activePhase(for: event)
      if phase.isEmpty {
        return synthesizeMouseWheelPhase(for: event, view: view)
      }
      if phase.contains(.began) || phase.contains(.mayBegin) {
        return .start
      }
      if phase.contains(.changed) || phase.contains(.stationary) {
        return .update
      }
      if phase.contains(.ended) {
        return .end
      }
      if phase.contains(.cancelled) {
        return .cancel
      }
      return .update
    }

    private func synthesizeMouseWheelPhase(
      for event: NSEvent, view: NSView
    ) -> FWFNSScrollWheelPhase {
      mouseWheelIdleTimer?.invalidate()
      let eventType: FWFNSScrollWheelPhase
      if !mouseWheelActive {
        mouseWheelActive = true
        eventType = .start
      } else {
        eventType = .update
      }
      mouseWheelIdleTimer = Timer.scheduledTimer(
        withTimeInterval: Self.MOUSE_WHEEL_IDLE_END_INTERVAL, repeats: false
      ) { [weak self] _ in
        guard let self, let view = self.wheelView else { return }
        guard let lastEvent = self.lastScrollWheelEvent else { return }
        self.mouseWheelActive = false
        self.reportScrollWheel(
          scrollView: nil,
          eventType: .end,
          timestamp: lastEvent.timestamp,
          globalX: self.flutterGlobalPoint(for: lastEvent, view: view).x,
          globalY: self.flutterGlobalPoint(for: lastEvent, view: view).y,
          localX: view.convert(lastEvent.locationInWindow, from: nil).x,
          localY: view.convert(lastEvent.locationInWindow, from: nil).y,
          deltaX: 0,
          deltaY: 0,
          isMomentum: false,
          hasPreciseDeltas: lastEvent.hasPreciseScrollingDeltas
        )
        self.lastScrollWheelEvent = nil
      }
      return eventType
    }

    /// Maps a scroll-wheel event to Flutter global (window-relative logical) coordinates.
    private func flutterGlobalPoint(for event: NSEvent, view: NSView) -> NSPoint {
      let localPoint = view.convert(event.locationInWindow, from: nil)
      guard let flutterView = flutterContentView(from: view) else {
        return event.locationInWindow
      }
      return view.convert(localPoint, to: flutterView)
    }

    private func flutterContentView(from view: NSView) -> NSView? {
      if let controller = view.window?.contentViewController as? FlutterViewController {
        return controller.view
      }
      var current: NSView? = view
      while let currentView = current {
        if String(describing: type(of: currentView)).hasPrefix("FlutterView") {
          return currentView
        }
        current = currentView.superview
      }
      return nil
    }

    private func reportScrollWheel(
      scrollView: NSScrollView?,
      eventType: FWFNSScrollWheelPhase,
      timestamp: TimeInterval,
      globalX: CGFloat,
      globalY: CGFloat,
      localX: CGFloat,
      localY: CGFloat,
      deltaX: CGFloat,
      deltaY: CGFloat,
      isMomentum: Bool,
      hasPreciseDeltas: Bool
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.scrollWheel(
          pigeonInstance: self,
          scrollView: scrollView,
          eventType: eventType,
          timestamp: timestamp,
          globalX: globalX,
          globalY: globalY,
          localX: localX,
          localY: localY,
          deltaX: deltaX,
          deltaY: deltaY,
          isMomentum: isMomentum,
          hasPreciseDeltas: hasPreciseDeltas
        ) { result in
          if case .failure(let error) = result {
            onFailure("FWFNSScrollViewDelegate.scrollWheel", error)
          }
        }
      }
    }

    private func reportScrollPosition(for scrollView: NSScrollView) {
      let origin = scrollView.contentView.bounds.origin
      registrar.dispatchOnMainThread { onFailure in
        self.api.scrollViewDidScroll(
          pigeonInstance: self, scrollView: scrollView, x: origin.x, y: origin.y
        ) { result in
          if case .failure(let error) = result {
            onFailure("FWFNSScrollViewDelegate.scrollViewDidScroll", error)
          }
        }
      }
    }

    #if DEBUG
      var hasScrollWheelMonitorForTesting: Bool {
        scrollWheelMonitor != nil
      }

      func reportScrollWheelForTesting(
        scrollView: NSScrollView,
        eventType: FWFNSScrollWheelPhase,
        timestamp: TimeInterval,
        globalX: CGFloat,
        globalY: CGFloat,
        localX: CGFloat,
        localY: CGFloat,
        deltaX: CGFloat,
        deltaY: CGFloat,
        isMomentum: Bool,
        hasPreciseDeltas: Bool
      ) {
        reportScrollWheel(
          scrollView: scrollView,
          eventType: eventType,
          timestamp: timestamp,
          globalX: globalX,
          globalY: globalY,
          localX: localX,
          localY: localY,
          deltaX: deltaX,
          deltaY: deltaY,
          isMomentum: isMomentum,
          hasPreciseDeltas: hasPreciseDeltas
        )
      }
    #endif
  }
#endif

/// ProxyApi implementation for `UIScrollViewDelegate` and `FWFNSScrollViewDelegate`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class ScrollViewDelegateProxyAPIDelegate: PigeonApiDelegateUIScrollViewDelegate,
  PigeonApiDelegateFWFNSScrollViewDelegate
{
  #if os(iOS)
    func pigeonDefaultConstructor(pigeonApi: PigeonApiUIScrollViewDelegate) throws
      -> UIScrollViewDelegate
    {
      return ScrollViewDelegateImpl(
        api: pigeonApi, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar)
    }
  #endif

  #if os(macOS)
    func pigeonDefaultConstructor(pigeonApi: PigeonApiFWFNSScrollViewDelegate) throws
      -> FWFNSScrollViewDelegate
    {
      return FWFNSScrollViewDelegateImpl(
        api: pigeonApi, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar)
    }
  #endif
}
