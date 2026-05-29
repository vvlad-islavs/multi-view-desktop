import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

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
/// WindowCommunicator.onDirect(context, viewId: 2).listen((msg) => print(msg));
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
abstract class WindowCommunicator {
  /// Returns a broadcast [Stream] of messages sent to [viewId] via [send].
  ///
  /// When [viewId] is omitted, listens on the window that owns [context].
  /// When [viewId] differs from the current window, sets up a linked listener
  /// so the sender can target another view from this one.
  Stream<dynamic> onDirect(BuildContext context, {int? viewId});

  /// A broadcast [Stream] that receives every message sent via [broadcast].
  ///
  /// Subscribe in any view to receive global announcements:
  /// ```dart
  /// WindowCommunicator.onBroadcast.listen((msg) {
  ///   if (msg is Map && msg['theme'] != null) applyTheme(msg['theme']);
  /// });
  /// ```
  Stream<dynamic> get onBroadcast;

  /// Delivers [message] to every active listener registered for [viewId]
  /// via [onDirect].
  ///
  /// If no one is listening the message is silently dropped
  void send(int viewId, dynamic message);

  /// Delivers [message] to every active [onBroadcast] subscriber in every
  /// view simultaneously.
  ///
  /// Use this for global application events such as theme changes, logout
  /// signals, or refresh requests that should affect all open windows at once.
  void broadcast(dynamic message);

  Future<void> dispose();
}
