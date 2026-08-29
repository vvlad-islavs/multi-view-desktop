import 'dart:async';

import 'package:flutter/widgets.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Widget-tree registration for a window or dialog view.
@internal
abstract class ViewEntryBase {
  ViewEntryBase({
    required this.widgetBuilder,
    required this.parentContext,
    ViewShellOverrides? initialShellOverrides,
  }) : viewShellOverrides = ValueNotifier<ViewShellOverrides?>(initialShellOverrides);

  final Widget Function(BuildContext) widgetBuilder;
  final BuildContext? parentContext;

  final ValueNotifier<ViewShellOverrides?> viewShellOverrides;

  void disposeEntryResources() => viewShellOverrides.dispose();
}

@internal
class ViewWindowEntry extends ViewEntryBase {
  ViewWindowEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    this.parentId,
  });

  final int? parentId;
}

@internal
class ViewDialogEntry extends ViewEntryBase {
  ViewDialogEntry({
    required super.widgetBuilder,
    required super.parentContext,
    super.initialShellOverrides,
    required this.parentId,
    required this.isModal,
    required this.closeCompleter,
  });

  final int parentId;
  final bool isModal;
  final Completer<Object?> closeCompleter;

  void completeResult(dynamic result) {
    if (!closeCompleter.isCompleted) {
      closeCompleter.complete(result);
    }
  }
}

@internal
class ViewPopupEntry {
  ViewPopupEntry({required this.parentId});

  final int parentId;
}

/// `_windows` / `_dialogs` / `_popups` maps for lifecycle and native hosts.
@internal
class ViewRegistry {
  final Map<int, ViewWindowEntry> windows = {};
  final Map<int, ViewDialogEntry> dialogs = {};
  final Map<int, ViewPopupEntry> popups = {};

  bool isWindow(int viewId) => windows.containsKey(viewId);

  bool isDialog(int viewId) => dialogs.containsKey(viewId);

  bool isPopup(int viewId) => popups.containsKey(viewId);

  bool isModalDialog(int viewId) => dialogs[viewId]?.isModal ?? false;

  int? windowParentId(int viewId) => windows[viewId]?.parentId;

  int? dialogParentId(int viewId) => dialogs[viewId]?.parentId;

  bool isManaged(int viewId) => isWindow(viewId) || isDialog(viewId) || isPopup(viewId);

  Iterable<int> get windowViewIds => windows.keys;

  Iterable<int> get allManagedViewIds => [...dialogs.keys, ...windows.keys];

  List<int> directChildWindowIds(int parentId) =>
      windows.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  List<int> directDialogChildIds(int parentId) =>
      dialogs.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  List<int> rootWindowIds({int? excludingId}) =>
      windows.entries.where((e) => e.value.parentId == null && e.key != excludingId).map((e) => e.key).toList();

  List<int> descendantWindowIdsDeepestFirst(int rootId) {
    final result = <int>[];
    void walk(int id) {
      for (final child in directChildWindowIds(id)) {
        walk(child);
        result.add(child);
      }
    }

    walk(rootId);
    return result;
  }

  List<int> parentWindowChain(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = windowParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  List<int> parentDialogChain(int childId) {
    final result = <int>[];
    void walk(int id) {
      final parent = dialogParentId(id);
      if (parent == null) return;
      result.add(parent);
      walk(parent);
    }

    walk(childId);
    return result;
  }

  List<int> directPopupChildIds(int parentId) =>
      popups.entries.where((e) => e.value.parentId == parentId).map((e) => e.key).toList();

  ViewEntryBase? entryFor(int viewId) => windows[viewId] ?? dialogs[viewId];
}
