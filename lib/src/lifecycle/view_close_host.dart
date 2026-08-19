// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Registry and disposal callbacks owned by `_ViewsManagerImpl`.
///
/// Keeps [ViewCloseService] free of `_windows` / `_dialogs` maps.
@internal
class ViewCloseHost {
  const ViewCloseHost({
    required this.isWindow,
    required this.isDialog,
    required this.isModalDialog,
    required this.isPopup,
    required this.windowParentId,
    required this.dialogParentId,
    required this.directChildWindowIds,
    required this.directDialogChildIds,
    required this.rootWindowIds,
    required this.disposeView,
    required this.destroyPopupsByParent,
    required this.removeAllDialogsByParent,
    required this.anchorCandidatesExcluding,
    required this.isAnchorView,
    required this.enableDynamicAnchor,
    required this.isLastMacosRootView,
    required this.onMacosHideInsteadOfClose,
    required this.hasLiveFlutterView,
    required this.onMacosRestoreSaveLastWindowPolicy,
  });

  final bool Function(int viewId) isWindow;
  final bool Function(int viewId) isDialog;
  final bool Function(int viewId) isModalDialog;
  final bool Function(int viewId) isPopup;

  final int? Function(int viewId) windowParentId;
  final int? Function(int viewId) dialogParentId;

  final List<int> Function(int parentId) directChildWindowIds;
  final List<int> Function(int parentId) directDialogChildIds;
  final List<int> Function({int? excludingId}) rootWindowIds;

  final void Function(int viewId) disposeView;
  final void Function(int parentId) destroyPopupsByParent;
  final void Function(int parentId) removeAllDialogsByParent;

  final List<int> Function({int? excludingViewId}) anchorCandidatesExcluding;
  final bool Function(int viewId) isAnchorView;
  final bool enableDynamicAnchor;

  final bool Function(int viewId) isLastMacosRootView;
  final void Function(int viewId) onMacosHideInsteadOfClose;

  final bool Function(int viewId) hasLiveFlutterView;
  final void Function() onMacosRestoreSaveLastWindowPolicy;

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

  bool isManaged(int viewId) => isWindow(viewId) || isDialog(viewId) || isPopup(viewId);
}
