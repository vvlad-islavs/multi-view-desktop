import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays out [child] at its intrinsic size so a [Column] shrink-wraps instead
/// of expanding to the native view, and reports that size for window chrome.
///
/// Incoming view constraints are ignored for measurement. [maxSize] is the
/// finite ceiling (typically the parent window) so flex children never see
/// unbounded constraints. Wrap the content in [SizedBox] for a fixed size.
class PopupContentSizer extends SingleChildRenderObjectWidget {
  const PopupContentSizer({super.key, required this.maxSize, required this.onSize, required super.child});

  /// Largest size the popup may occupy. Used as a finite max so [Column] and
  /// [Expanded] do not hit unbounded constraints.
  final Size maxSize;

  /// Called after layout with the content size the native window should take.
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPopupContentSizer(maxSize: maxSize, onSize: onSize);
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderPopupContentSizer renderObject) {
    renderObject
      ..maxSize = maxSize
      ..onSize = onSize;
  }
}

class RenderPopupContentSizer extends RenderProxyBox {
  RenderPopupContentSizer({required Size maxSize, required ValueChanged<Size> onSize})
    : _maxSize = maxSize,
      _onSize = onSize;

  Size _maxSize;
  ValueChanged<Size> _onSize;
  Size? _lastReported;
  bool _sizeCallbackScheduled = false;

  set maxSize(Size value) {
    if (_maxSize == value) return;
    _maxSize = value;
    markNeedsLayout();
  }

  set onSize(ValueChanged<Size> value) {
    _onSize = value;
  }

  Size _measureChild() {
    final child = this.child;
    if (child == null) {
      return const Size(1, 1);
    }

    final maxW = _maxSize.width.isFinite && _maxSize.width > 0 ? _maxSize.width : 800.0;
    final maxH = _maxSize.height.isFinite && _maxSize.height > 0 ? _maxSize.height : 600.0;

    var width = child.getMaxIntrinsicWidth(double.infinity);
    if (!width.isFinite) {
      width = child.getMinIntrinsicWidth(double.infinity);
    }
    width = width.isFinite ? width.clamp(0.0, maxW) : maxW;
    if (width < 1) width = 1;

    var height = child.getMaxIntrinsicHeight(width);
    if (!height.isFinite) {
      height = child.getMinIntrinsicHeight(width);
    }
    height = height.isFinite ? height.clamp(0.0, maxH) : maxH;
    if (height < 1) height = 1;

    child.layout(BoxConstraints(maxWidth: width, maxHeight: height), parentUsesSize: true);
    return Size(child.size.width.clamp(1.0, maxW), child.size.height.clamp(1.0, maxH));
  }

  void _reportSize(Size size) {
    if (_lastReported == size) return;
    _lastReported = size;
    if (_sizeCallbackScheduled) return;
    _sizeCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sizeCallbackScheduled = false;
      final reported = _lastReported;
      if (reported != null) {
        _onSize(reported);
      }
    });
  }

  @override
  void performLayout() {
    final measured = _measureChild();
    size = constraints.constrain(measured);
    _reportSize(measured);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) {
      super.paint(context, offset);
    });
  }
}
