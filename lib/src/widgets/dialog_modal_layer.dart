import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Provides a [ValueNotifier<int>] counting the number of active modal dialogs
/// blocking the current window.
///
/// Injected automatically by the library for every OS window. Users do not
/// construct this directly; read it via [DialogScope.of] or simply use
/// [DialogModalLayer].

typedef DialogInfo = ({int id, bool isModal});

class DialogScope extends InheritedWidget {
  const DialogScope({super.key, required this.notifier, required super.child});

  /// Notifier whose value is the number of dialogs currently is children dialogs of
  /// this window. `[]` means the window has no children dialogs.
  final ValueNotifier<List<DialogInfo>> notifier;

  /// Returns the notifier from the nearest [DialogScope], or `null` if
  /// none is present (e.g. window was not created via [runMultiApp]).
  static ValueNotifier<List<DialogInfo>>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DialogScope>()?.notifier;
  }

  /// Returns the notifier from the nearest [DialogScope].
  ///
  /// Throws in debug mode if [runMultiApp] was not used as the entry point.
  static ValueNotifier<List<DialogInfo>> of(BuildContext context) {
    final scope = maybeOf(context);
    assert(
      scope != null,
      'No DialogModalScope found in context. '
      'Make sure runMultiApp() is used as the app entry point.',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(DialogScope oldWidget) => notifier != oldWidget.notifier;
}

/// Wraps a window's content and shows a translucent scrim whenever a **modal**
/// dialog is open over it.
///
/// Place this widget directly inside the window's root builder so it covers
/// the entire window surface:
///
/// ```dart
/// runMultiApp(
///   home: (context, id) => DialogModalLayer(
///     child: MyHomeScreen(),
///   ),
/// );
/// ```
///
/// When [openDialog] is called with `modal: true`, the notifier value
/// increments and the scrim fades in, preventing interaction with the content
/// beneath. When all modal dialogs are closed, the scrim fades out.
///
/// The barrier is purely visual and does not block mouse/keyboard events at
/// the OS level (since each window is a separate OS view). For true input
/// blocking, combine with [MultiViewDesktop.setIgnoreMouseEvents] or use
/// [openDialog]'s built-in behavior which automatically disables interaction
/// on the parent window on supported platforms.
class DialogModalLayer extends StatelessWidget {
  const DialogModalLayer({
    super.key,
    required this.child,
    this.showBarrierForNotModalDialog = false,
    this.barrierColor = const Color(0x80000000),
    this.animationDuration = const Duration(milliseconds: 150),
  });

  final Widget child;

  final bool showBarrierForNotModalDialog;

  /// Color of the modal scrim overlay. Defaults to a semi-transparent black.
  final Color barrierColor;

  /// Duration of the fade animation when the scrim appears or disappears.
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final notifier = DialogScope.of(context);

    return ValueListenableBuilder<List<DialogInfo>>(
      valueListenable: notifier,
      builder: (context, modalList, _) {
        bool showBarrier = showBarrierForNotModalDialog && modalList.isNotEmpty;
        final bool anyIsModal = modalList.any((e) => e.isModal);
        if (anyIsModal) {
          showBarrier = true;
        }
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () async {
            if (showBarrier && !anyIsModal) {
              final dialogsList = modalList.map((e)=> e.id).toList()..sort();
              for (final id in dialogsList){
                await MultiViewDesktop.fromId(id).focus();
              }
            }
          },
          child: Stack(
            children: [
              child,
              AnimatedOpacity(
                opacity: showBarrier ? 1.0 : 0.0,
                duration: animationDuration,
                child: IgnorePointer(
                  ignoring: !showBarrier,
                  child: ColoredBox(color: barrierColor, child: const SizedBox.expand()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
