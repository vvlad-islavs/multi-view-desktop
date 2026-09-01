import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'popup_positioner.dart';

/// Controls a [PopupView] from outside the popup content.
///
/// The popup has no public view id and no shell/routing of its own. Position
/// is declared here (or on [PopupView]) and applied by the owning widget.
class PopupController extends ChangeNotifier {
  bool _isOpen = false;
  bool _attached = false;

  Future<void> Function()? _openHandler;
  Future<void> Function()? _closeHandler;

  /// Whether the popup is currently requested open.
  bool get isOpen => _isOpen;

  /// Whether a [PopupView] is currently bound to this controller.
  bool get isAttached => _attached;

  /// Opens the popup. No-op when already open.
  Future<void> open() async {
    if (_isOpen) return;
    _isOpen = true;
    notifyListeners();
    await _openHandler?.call();
  }

  /// Closes the popup. No-op when already closed.
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
    await _closeHandler?.call();
  }

  /// Toggles [open] / [close].
  Future<void> toggle() => _isOpen ? close() : open();

  /// Bound by [PopupView]. Do not call from application code.
  @internal
  void attach({
    required Future<void> Function() onOpen,
    required Future<void> Function() onClose,
  }) {
    _openHandler = onOpen;
    _closeHandler = onClose;
    _attached = true;
  }

  /// Bound by [PopupView]. Do not call from application code.
  @internal
  void detach() {
    _openHandler = null;
    _closeHandler = null;
    _attached = false;
  }

  /// Bound by [PopupView] when the native window disappears.
  @internal
  void markClosed() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }
}
