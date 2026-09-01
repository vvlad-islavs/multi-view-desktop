
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';

/// Tracks open dialogs per parent window for `DialogModalLayer`.
///
/// Each parent has a `ValueNotifier` with the list of child dialog ids.
/// `DialogModalLayer` listens to it to show or hide the scrim.
class ModalStateService {
  final Map<int, ValueNotifier<List<DialogInfo>>> _notifiers = {};

  /// Notifier for `realViewId`. Created on first access.
  ValueNotifier<List<DialogInfo>> getNotifier(int realViewId) {
    return _notifiers.putIfAbsent(realViewId, () => ValueNotifier([]));
  }

  void registerDialog(int parentRealId, {required int dialogId, required bool isModal}) {
    MvdLog.instance.info('modal', 'registerDialog', {
      'parentRealId': parentRealId,
      'dialogId': dialogId,
      'isModal': isModal,
    });
    final notifier = getNotifier(parentRealId);
    // A new list instance is required so ValueNotifier listeners fire.
    notifier.value = [...notifier.value, (id: dialogId, isModal: isModal)];
  }

  void unregisterDialog(int parentRealId, {required int realDialogId}) {
    MvdLog.instance.info('modal', 'unregisterDialog', {
      'parentRealId': parentRealId,
      'dialogId': realDialogId,
    });
    final notifier = _notifiers[parentRealId];
    if (notifier == null) return;
    notifier.value = [...notifier.value.where((e) => e.id != realDialogId)];
  }

  void disposeView(int realViewId) {
    _notifiers.remove(realViewId)?.dispose();
  }
}
