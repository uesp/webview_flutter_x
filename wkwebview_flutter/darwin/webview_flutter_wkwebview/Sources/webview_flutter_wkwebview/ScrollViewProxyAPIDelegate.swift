// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

#if os(macOS)
  private var macScrollDelegates: [ObjectIdentifier: FWFNSScrollViewDelegateImpl] = [:]
#endif

/// ProxyApi implementation for `UIScrollView` and `NSScrollView`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class ScrollViewProxyAPIDelegate: PigeonApiDelegateUIScrollView, PigeonApiDelegateNSScrollView {
  #if os(iOS)
    func getContentOffset(pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView) throws
      -> [Double]
    {
      let offset = pigeonInstance.contentOffset
      return [offset.x, offset.y]
    }

    func scrollBy(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, x: Double, y: Double
    ) throws {
      let offset = pigeonInstance.contentOffset
      pigeonInstance.contentOffset = CGPoint(x: offset.x + x, y: offset.y + y)
    }

    func setContentOffset(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, x: Double, y: Double
    ) throws {
      pigeonInstance.contentOffset = CGPoint(x: x, y: y)
    }

    func setDelegate(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView,
      delegate: UIScrollViewDelegate?
    ) throws {
      pigeonInstance.delegate = delegate
    }

    func setBounces(pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool)
      throws
    {
      pigeonInstance.bounces = value
    }

    func setBouncesHorizontally(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      if #available(iOS 17.4, *) {
        #if compiler(>=6.0)
          pigeonInstance.bouncesHorizontally = value
        #else
          throw (pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar).createUnsupportedVersionError(
            method: "UIScrollView.bouncesHorizontally", versionRequirements: "compiler>=6.0")
        #endif
      } else {
        throw (pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar).createUnsupportedVersionError(
          method: "UIScrollView.bouncesHorizontally", versionRequirements: "iOS 17.4")
      }
    }

    func setBouncesVertically(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      if #available(iOS 17.4, *) {
        #if compiler(>=6.0)
          pigeonInstance.bouncesVertically = value
        #else
          throw (pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar).createUnsupportedVersionError(
            method: "UIScrollView.bouncesVertically", versionRequirements: "compiler>=6.0")
        #endif
      } else {
        throw (pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar).createUnsupportedVersionError(
          method: "UIScrollView.bouncesVertically", versionRequirements: "iOS 17.4")
      }
    }

    func setAlwaysBounceVertical(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      pigeonInstance.alwaysBounceVertical = value
    }

    func setAlwaysBounceHorizontal(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      pigeonInstance.alwaysBounceHorizontal = value
    }

    func setShowsVerticalScrollIndicator(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      pigeonInstance.showsVerticalScrollIndicator = value
    }

    func setShowsHorizontalScrollIndicator(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      pigeonInstance.showsHorizontalScrollIndicator = value
    }

    func setScrollEnabled(
      pigeonApi: PigeonApiUIScrollView, pigeonInstance: UIScrollView, value: Bool
    ) throws {
      pigeonInstance.isScrollEnabled = value
    }
  #endif

  #if os(macOS)
    func getContentOffset(pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView) throws
      -> [Double]
    {
      let origin = pigeonInstance.contentView.bounds.origin
      return [origin.x, origin.y]
    }

    func scrollBy(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, x: Double, y: Double
    ) throws {
      let clipView = pigeonInstance.contentView
      var origin = clipView.bounds.origin
      origin.x += CGFloat(x)
      origin.y += CGFloat(y)
      clipView.scroll(to: origin)
      pigeonInstance.reflectScrolledClipView(clipView)
    }

    func setContentOffset(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, x: Double, y: Double
    ) throws {
      let clipView = pigeonInstance.contentView
      clipView.scroll(to: NSPoint(x: x, y: y))
      pigeonInstance.reflectScrolledClipView(clipView)
    }

    func setDelegate(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView,
      delegate: FWFNSScrollViewDelegate?
    ) throws {
      let scrollViewId = ObjectIdentifier(pigeonInstance)
      macScrollDelegates[scrollViewId]?.detach()
      macScrollDelegates.removeValue(forKey: scrollViewId)
      guard let impl = delegate as? FWFNSScrollViewDelegateImpl else { return }
      macScrollDelegates[scrollViewId] = impl
      impl.attach(to: pigeonInstance)
    }

    func setBounces(pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool)
      throws
    {
      let elasticity: NSScrollView.Elasticity = value ? .allowed : .none
      pigeonInstance.verticalScrollElasticity = elasticity
      pigeonInstance.horizontalScrollElasticity = elasticity
    }

    func setBouncesHorizontally(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.horizontalScrollElasticity = value ? .allowed : .none
    }

    func setBouncesVertically(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.verticalScrollElasticity = value ? .allowed : .none
    }

    func setAlwaysBounceVertical(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.verticalScrollElasticity = value ? .allowed : .automatic
    }

    func setAlwaysBounceHorizontal(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.horizontalScrollElasticity = value ? .allowed : .automatic
    }

    func setShowsVerticalScrollIndicator(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.hasVerticalScroller = value
    }

    func setShowsHorizontalScrollIndicator(
      pigeonApi: PigeonApiNSScrollView, pigeonInstance: NSScrollView, value: Bool
    ) throws {
      pigeonInstance.hasHorizontalScroller = value
    }
  #endif
}
