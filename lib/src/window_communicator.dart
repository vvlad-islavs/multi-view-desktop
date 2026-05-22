import 'dart:async';

/// In-process message bus between views.
///
/// Because [runMultiApp] uses a single Flutter engine and a single Dart
/// isolate, all views share memory directly.  [WindowCommunicator] provides
/// a lightweight routing layer so views can still exchange messages without
/// tight coupling.
///
/// Two addressing modes are supported:
///
/// Point-to-point - deliver to a specific view:
/// ```dart
/// // Send to view 2
/// WindowCommunicator.send(2, {'action': 'reload'});
///
/// // Listen in view 2
/// WindowCommunicator.listen(2).listen((msg) => print(msg));
/// ```
///
/// Broadcast - deliver to every subscribed view:
/// ```dart
/// // In view 1 - send to all
/// WindowCommunicator.broadcast({'theme': 'dark'});
///
/// // In any view - listen for broadcasts
/// WindowCommunicator.onBroadcast.listen((msg) => print(msg));
/// ```
class WindowCommunicator {
  WindowCommunicator._();

  // Per-view streams, keyed by viewId.
  static final Map<int, StreamController<dynamic>> _viewControllers = {};

  // Single broadcast stream shared across all views.
  static final StreamController<dynamic> _broadcastController =
      StreamController<dynamic>.broadcast();

  // -------------------------------------------------------------------------
  // Point-to-point
  // -------------------------------------------------------------------------

  /// Returns a broadcast [Stream] of messages sent to [viewId] via [send].
  ///
  /// Multiple callers with the same [viewId] share the same stream instance.
  /// Subscriptions are persistent across callers - no need to re-subscribe
  /// when the sender changes.
  static Stream<dynamic> listen(int viewId) {
    _viewControllers.putIfAbsent(
      viewId,
      () => StreamController<dynamic>.broadcast(),
    );
    return _viewControllers[viewId]!.stream;
  }

  /// Delivers [message] to every active listener registered for [targetViewId]
  /// via [listen].
  ///
  /// If no one is listening the message is silently dropped.
  static void send(int targetViewId, dynamic message) {
    _viewControllers[targetViewId]?.add(message);
  }

  // -------------------------------------------------------------------------
  // Broadcast
  // -------------------------------------------------------------------------

  /// A broadcast [Stream] that receives every message sent via [broadcast].
  ///
  /// Subscribe in any view to receive global announcements:
  /// ```dart
  /// WindowCommunicator.onBroadcast.listen((msg) {
  ///   if (msg is Map && msg['theme'] != null) applyTheme(msg['theme']);
  /// });
  /// ```
  static Stream<dynamic> get onBroadcast => _broadcastController.stream;

  /// Delivers [message] to every active [onBroadcast] subscriber in every
  /// view simultaneously.
  ///
  /// Use this for global application events such as theme changes, logout
  /// signals, or refresh requests that should affect all open windows at once.
  static void broadcast(dynamic message) {
    _broadcastController.add(message);
  }

  // -------------------------------------------------------------------------
  // Internal cleanup
  // -------------------------------------------------------------------------

  /// Closes and removes the per-view stream for [viewId].
  ///
  /// Called automatically by the library when a view is removed from the
  /// [ViewCollection].  Do not call this manually.
  static void disposeView(int viewId) {
    _viewControllers.remove(viewId)?.close();
  }
}
