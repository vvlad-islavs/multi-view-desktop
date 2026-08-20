// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Manager-specific bindings for [ViewCloseService] (dispose, invoke, anchor policy).
@internal
class ViewCloseDelegate {
  const ViewCloseDelegate({
    required this.disposeView,
    required this.invoke,
    required this.anchorCandidatesExcluding,
    required this.isLastMacosRootView,
    required this.enableDynamicAnchor,
  });

  final void Function(int viewId) disposeView;
  final T? Function<T>(int viewId, T Function() func, {bool dialogSupports}) invoke;

  final List<int> Function({int? excludingViewId}) anchorCandidatesExcluding;
  final bool Function(int viewId) isLastMacosRootView;
  final bool enableDynamicAnchor;
}
