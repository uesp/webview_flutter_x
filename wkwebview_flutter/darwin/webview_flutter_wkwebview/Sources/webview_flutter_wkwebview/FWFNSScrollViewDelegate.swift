// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(macOS)
  import Foundation

  /// Marker type for Pigeon macOS scroll callbacks.
  ///
  /// AppKit has no `NSScrollViewDelegate` protocol (unlike UIKit's `UIScrollViewDelegate`).
  protocol FWFNSScrollViewDelegate: NSObjectProtocol {}
#endif
