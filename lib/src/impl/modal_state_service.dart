
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Tracks how many **modal** dialogs are currently blocking each parent window.
///
/// Every time a modal dialog is opened, [registerDialog] increments the parent's
/// counter.  When the dialog closes, [unregisterDialog] decrements it.  The
/// [ValueNotifier] for each parent is injected into the widget tree via
/// [DialogScope] so that [DialogModalLayer] can react to state changes.
class ModalStateService {
  final Map<int, ValueNotifier<List<DialogInfo>>> _notifiers = {};

  /// Returns (creating if necessary) the notifier for [realViewId].
  ValueNotifier<List<DialogInfo>> getNotifier(int realViewId) {
    return _notifiers.putIfAbsent(realViewId, () => ValueNotifier([]));
  }

  /// Increments the modal count for [parentRealId].
  void registerDialog(int parentRealId, {required int dialogId, required bool isModal}) {
    final notifier = getNotifier(parentRealId);
    // Must assign a new list instance — mutating in place and reassigning the
    // same reference does not trigger ValueNotifier listeners.
    notifier.value = [...notifier.value, (id: dialogId, isModal: isModal)];
  }

  /// Decrements the modal count for [parentRealId]. No-ops if already zero.
  void unregisterDialog(int parentRealId, {required int realDialogId}) {
    final notifier = _notifiers[parentRealId];
    if (notifier == null) return;
    notifier.value = [...notifier.value.where((e) => e.id != realDialogId)];
  }

  /// Disposes the notifier for [realViewId] when the window is removed.
  void disposeView(int realViewId) {
    _notifiers.remove(realViewId)?.dispose();
  }
}
