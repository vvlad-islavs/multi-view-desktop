import 'package:flutter/foundation.dart';
import 'package:multiview_desktop/src/view_manager/view_manager_proxies.dart';

/// macOS-only window APIs for a [MultiViewDesktop] instance.
///
/// Access via `MultiViewDesktop.of(context).macos` or
/// `MultiViewDesktop.fromId(id).macos`.
///
/// On non-macOS platforms these methods are no-ops / return safe defaults
/// (handled by the native manager).
class MultiViewDesktopMacos {
  /// Creates a macOS facade for [realId]. Application code uses [MultiViewDesktop.macos].
  @internal
  MultiViewDesktopMacos(this._realId, this._proxies);

  final int _realId;
  final ViewManagerProxies _proxies;

  /// Returns whether the window is excluded from Mission Control / Expose.
  bool isHideFromCollection() {
    return _proxies.platform.isHideFromCollection(_realId);
  }

  /// Hides or shows the window in Mission Control and Expose.
  void hideFromCollection(bool isHideFromCollection) {
    _proxies.platform.hideFromCollection(_realId, isHideFromCollection);
  }

  /// Returns whether the window is pinned to all Spaces.
  bool isVisibleOnAllWorkspaces() {
    return _proxies.platform.isVisibleOnAllWorkspaces(_realId);
  }

  /// Pins or unpins the window across all Spaces.
  void setVisibleOnAllWorkspaces(bool visible, {bool visibleOnFullScreen = false}) {
    _proxies.platform.setVisibleOnAllWorkspaces(_realId, visible, visibleOnFullScreen: visibleOnFullScreen);
  }

  /// Sets the dock icon badge label. Pass `null` or empty to clear.
  void setBadgeLabel({String? label}) {
    _proxies.platform.setBadgeLabel(_realId, label);
  }

  /// Returns whether this window is on the currently active Mission Control Space.
  ///
  /// On Windows and Linux always returns `true`.
  bool isOnActiveSpace() {
    return _proxies.platform.isOnActiveSpace(_realId);
  }
}
