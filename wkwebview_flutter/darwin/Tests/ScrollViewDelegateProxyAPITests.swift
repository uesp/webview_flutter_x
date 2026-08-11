// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

@testable import webview_flutter_wkwebview

#if os(iOS)
  import UIKit
#endif
#if os(macOS)
  import AppKit
#endif

class ScrollViewDelegateProxyAPITests: XCTestCase {
  #if os(iOS)
    func testPigeonDefaultConstructor() {
      let registrar = TestProxyApiRegistrar()
      let api = registrar.apiDelegate.pigeonApiUIScrollViewDelegate(registrar)

      let instance = try? api.pigeonDelegate.pigeonDefaultConstructor(pigeonApi: api)
      XCTAssertNotNil(instance)
    }

    @MainActor func testScrollViewDidScroll() {
      let api = TestScrollViewDelegateApi()
      let registrar = TestProxyApiRegistrar()
      let instance = ScrollViewDelegateImpl(api: api, registrar: registrar)
      let scrollView = UIScrollView(frame: .zero)
      let x = 1.0
      let y = 1.0
      scrollView.contentOffset = CGPoint(x: x, y: y)
      instance.scrollViewDidScroll(scrollView)

      XCTAssertEqual(api.scrollViewDidScrollArgs, [scrollView, x, y])
    }
  #endif

  #if os(macOS)
    func testPigeonDefaultConstructorMacOS() {
      let registrar = TestProxyApiRegistrar()
      let api = registrar.apiDelegate.pigeonApiFWFNSScrollViewDelegate(registrar)

      let instance = try? api.pigeonDelegate.pigeonDefaultConstructor(pigeonApi: api)
      XCTAssertNotNil(instance)
      XCTAssertTrue(instance is FWFNSScrollViewDelegateImpl)
    }

    @MainActor func testScrollWheelForwardsPayload() {
      let api = TestFWFNSScrollViewDelegateApi()
      let registrar = TestProxyApiRegistrar()
      let instance = FWFNSScrollViewDelegateImpl(api: api, registrar: registrar)
      let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

      instance.attachScrollWheel(to: scrollView, consume: false)
      instance.reportScrollWheelForTesting(
        scrollView: scrollView,
        eventType: .update,
        timestamp: 12.5,
        globalX: 10,
        globalY: 20,
        localX: 3,
        localY: 4,
        deltaX: 0.5,
        deltaY: -1.25,
        isMomentum: false,
        hasPreciseDeltas: true
      )

      XCTAssertEqual(api.scrollWheelArgs?.eventType, .update)
      XCTAssertEqual(api.scrollWheelArgs?.timestamp, 12.5)
      XCTAssertEqual(api.scrollWheelArgs?.globalX, 10)
      XCTAssertEqual(api.scrollWheelArgs?.globalY, 20)
      XCTAssertEqual(api.scrollWheelArgs?.localX, 3)
      XCTAssertEqual(api.scrollWheelArgs?.localY, 4)
      XCTAssertEqual(api.scrollWheelArgs?.deltaX, 0.5)
      XCTAssertEqual(api.scrollWheelArgs?.deltaY, -1.25)
      XCTAssertEqual(api.scrollWheelArgs?.isMomentum, false)
      XCTAssertEqual(api.scrollWheelArgs?.hasPreciseDeltas, true)
      XCTAssertTrue(instance.hasScrollWheelMonitorForTesting)

      instance.detachScrollWheel()
      XCTAssertFalse(instance.hasScrollWheelMonitorForTesting)
    }
  #endif
}

#if os(iOS)
  class TestScrollViewDelegateApi: PigeonApiProtocolUIScrollViewDelegate {
    var scrollViewDidScrollArgs: [AnyHashable?]? = nil

    func scrollViewDidScroll(
      pigeonInstance pigeonInstanceArg: UIScrollViewDelegate,
      scrollView scrollViewArg: UIScrollView, x xArg: Double, y yArg: Double,
      completion: @escaping (Result<Void, PigeonError>) -> Void
    ) {
      scrollViewDidScrollArgs = [scrollViewArg, xArg, yArg]
    }
  }
#endif

#if os(macOS)
  struct TestScrollWheelArgs {
    let scrollView: NSScrollView?
    let eventType: FWFNSScrollWheelPhase
    let timestamp: Double
    let globalX: Double
    let globalY: Double
    let localX: Double
    let localY: Double
    let deltaX: Double
    let deltaY: Double
    let isMomentum: Bool
    let hasPreciseDeltas: Bool
  }

  class TestFWFNSScrollViewDelegateApi: PigeonApiProtocolFWFNSScrollViewDelegate {
    var scrollWheelArgs: TestScrollWheelArgs?

    func scrollViewDidScroll(
      pigeonInstance pigeonInstanceArg: FWFNSScrollViewDelegate,
      scrollView scrollViewArg: NSScrollView, x xArg: Double, y yArg: Double,
      completion: @escaping (Result<Void, PigeonError>) -> Void
    ) {}

    func scrollWheel(
      pigeonInstance pigeonInstanceArg: FWFNSScrollViewDelegate,
      scrollView scrollViewArg: NSScrollView?,
      eventType eventTypeArg: FWFNSScrollWheelPhase,
      timestamp timestampArg: Double,
      globalX globalXArg: Double,
      globalY globalYArg: Double,
      localX localXArg: Double,
      localY localYArg: Double,
      deltaX deltaXArg: Double,
      deltaY deltaYArg: Double,
      isMomentum isMomentumArg: Bool,
      hasPreciseDeltas hasPreciseDeltasArg: Bool,
      completion: @escaping (Result<Void, PigeonError>) -> Void
    ) {
      scrollWheelArgs = TestScrollWheelArgs(
        scrollView: scrollViewArg,
        eventType: eventTypeArg,
        timestamp: timestampArg,
        globalX: globalXArg,
        globalY: globalYArg,
        localX: localXArg,
        localY: localYArg,
        deltaX: deltaXArg,
        deltaY: deltaYArg,
        isMomentum: isMomentumArg,
        hasPreciseDeltas: hasPreciseDeltasArg
      )
      completion(.success(()))
    }
  }
#endif
