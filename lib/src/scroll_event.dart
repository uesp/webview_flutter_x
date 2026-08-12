import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Lifecycle phase for a user-driven scroll gesture on the web view.
enum ScrollEventPhase {
	/// The scroll gesture began.
	start,

	/// The scroll gesture changed.
	update,

	/// The scroll gesture ended.
	end,

	/// The scroll gesture was cancelled.
	cancel,
}

/// User-driven scroll input forwarded from native platform gestures or JavaScript.
@immutable
class WebviewScrollEvent {
	/// Creates a [WebviewScrollEvent].
	const WebviewScrollEvent({
		required this.eventType,
		this.delta,
		this.velocity,
		required this.offset,
		this.globalPosition,
		this.localPosition,
	});

	/// Lifecycle phase of the scroll gesture.
	final ScrollEventPhase eventType;

	/// Scroll delta for this event.
	final Offset? delta;

	/// Scroll velocity (px/s), typically set on [ScrollEventPhase.end].
	final Offset? velocity;

	/// Total scroll offset accumulated since the page loaded.
	final Offset offset;

	/// Pointer position in Flutter global (window-relative logical) coordinates when available.
	final Offset? globalPosition;

	/// Pointer position relative to the webview platform view when available.
	final Offset? localPosition;

	/// Returns a copy of this event with the given fields replaced.
	WebviewScrollEvent copyWith({
		ScrollEventPhase? eventType,
		Offset? delta,
		Offset? velocity,
		Offset? offset,
		Offset? globalPosition,
		Offset? localPosition,
	}) =>
			WebviewScrollEvent(
				eventType: eventType ?? this.eventType,
				delta: delta ?? this.delta,
				velocity: velocity ?? this.velocity,
				offset: offset ?? this.offset,
				globalPosition: globalPosition ?? this.globalPosition,
				localPosition: localPosition ?? this.localPosition,
			);

	@override
	String toString() =>
			'WebviewScrollEvent($eventType, delta: $delta, velocity: $velocity, offset: $offset, globalPosition: $globalPosition, localPosition: $localPosition)';
}
