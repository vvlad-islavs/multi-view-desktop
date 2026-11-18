import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

import '../pages/alert_view_dialog.dart';
import '../pages/circles_screen.dart';
import '../pages/home.dart';
import 'e2e_context_store.dart';
import 'e2e_harness.dart';
import 'e2e_host.dart';
import 'e2e_params.dart';
import 'e2e_plain_page.dart';

/// Dependencies injected into default example handlers.
///
/// Swap builders / policies without changing the HTTP server.
class ExampleE2eHandlerDeps {
  ExampleE2eHandlerDeps({
    required this.contexts,
    this.windowBuilder,
    this.dialogBuilder,
    this.overlayDialogBuilder,
    this.popupChildBuilder,
  });

  final E2eContextStore contexts;

  final Widget Function(BuildContext context, int viewId)? windowBuilder;
  final Widget Function(BuildContext context, int viewId)? dialogBuilder;
  final Widget Function(BuildContext context)? overlayDialogBuilder;
  final Widget Function(BuildContext context, PopupController controller)?
      popupChildBuilder;
}

/// Builds the default RPC method map for the example app.
Map<String, E2eHandler> buildExampleE2eHandlers(ExampleE2eHandlerDeps deps) {
  final popups = <int, _PopupSession>{};

  /// Window content: always the real example [HomePage] (ConfirmDialog on preventClose).
  ///
  /// Optional `content`: `home` (default) | `plain` (minimal, no listener - not for preventClose).
  Widget Function(BuildContext context, int viewId) windowBuilderFor(
    E2eRequest req,
  ) {
    final content = req.optional<String>('content') ?? 'home';
    return (context, viewId) {
      final Widget child;
      if (deps.windowBuilder != null) {
        child = deps.windowBuilder!(context, viewId);
      } else {
        child = switch (content) {
          'plain' => const E2ePlainPage(),
          _ => const HomePage(),
        };
      }
      return E2eHost(store: deps.contexts, child: child);
    };
  }

  Widget defaultDialog(BuildContext context, int viewId) {
    return E2eHost(
      store: deps.contexts,
      child: deps.dialogBuilder?.call(context, viewId) ??
          AlertViewDialog(
            title: 'E2E dialog #$viewId',
            content: 'Opened by multiview e2e harness',
            actions: [
              TextButton(
                onPressed: () => context.closeDialog('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => context.closeDialog('ok'),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> settleOpen(E2eRequest req) async {
    final ms = parseSettleMs(req, fallbackAnimMs: kE2eAnimOpenMs)!;
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> settleClose(E2eRequest req) async {
    final ms = parseSettleMs(req, fallbackAnimMs: kE2eAnimCloseMs)!;
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  Future<void> applyLockedFlags(int viewId, E2eRequest req) async {
    final win = MultiViewDesktop.fromId(viewId);
    final resizable = req.optional<bool>('resizable');
    if (resizable != null) win.setResizable(resizable);
    final movable = req.optional<bool>('movable');
    if (movable != null) win.setMovable(movable);
    final minimizable = req.optional<bool>('minimizable');
    if (minimizable != null) win.setMinimizable(minimizable);
    final maximizable = req.optional<bool>('maximizable');
    if (maximizable != null) win.setMaximizable(maximizable);
    final closable = req.optional<bool>('closable');
    if (closable != null) win.setClosable(closable);
    final preventClose = req.optional<bool>('preventClose');
    if (preventClose != null) win.setPreventClose(preventClose);
    final alwaysOnTop = req.optional<bool>('alwaysOnTop');
    if (alwaysOnTop != null) win.setAlwaysOnTop(alwaysOnTop);
  }

  /// Drive [HomePage] prevent-close ConfirmDialog while [closeWindow] is pending.
  Future<bool> answerPreventCloseConfirm({
    required bool accept,
    required Set<int> dialogsBefore,
    int timeoutMs = 5000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final now = MultiViewDesktop.allDialogViewsIds.toSet();
      final created = now.difference(dialogsBefore);
      if (created.isNotEmpty) {
        final id = created.reduce((a, b) => a > b ? a : b);
        // Match ConfirmDialog buttons: Close -> true, Cancel -> false (not null).
        await MultiViewDesktop.fromId(id).closeDialog<bool>(accept);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return false;
  }

  Future<Map<String, Object?>> softCloseView(int viewId, E2eRequest req) async {
    final animation = parseAnimation(req);
    final confirmClose = req.optional<bool>('confirmClose');
    final confirmTimeoutMs =
        req.optional<num>('confirmTimeoutMs')?.toInt() ?? 5000;
    final win = MultiViewDesktop.fromId(viewId);
    final dialogsBefore = MultiViewDesktop.allDialogViewsIds.toSet();

    final pending = win.closeWindow(animation: animation);

    var confirmAnswered = false;
    if (confirmClose != null) {
      confirmAnswered = await answerPreventCloseConfirm(
        accept: confirmClose,
        dialogsBefore: dialogsBefore,
        timeoutMs: confirmTimeoutMs,
      );
      if (!confirmAnswered) {
        win.cancelCascadeClose();
        throw StateError(
          'Prevent-close ConfirmDialog did not appear within ${confirmTimeoutMs}ms '
          '(viewId=$viewId). preventClose windows use HomePage ConfirmDialog - '
          'pass confirmClose:true|false.',
        );
      }
    }

    final ok = await pending.timeout(
      Duration(milliseconds: confirmTimeoutMs + 10000),
      onTimeout: () {
        for (final id in List<int>.from(MultiViewDesktop.allDialogViewsIds)) {
          if (!dialogsBefore.contains(id)) {
            unawaited(MultiViewDesktop.fromId(id).closeDialog<bool>(false));
          }
        }
        win.cancelCascadeClose();
        throw TimeoutException(
          'close_window timed out on viewId=$viewId. '
          'If HomePage ConfirmDialog is shown, pass confirmClose:true|false.',
        );
      },
    );
    await settleClose(req);
    return {
      'closed': ok,
      'viewId': viewId,
      'confirmClose': ?confirmClose,
      if (confirmClose != null) 'confirmAnswered': confirmAnswered,
    };
  }

  return {
    'ping': (_) async => {'pong': true, 'ts': DateTime.now().toIso8601String()},

    'snapshot': (_) async {
      return {
        'windows': MultiViewDesktop.allWindowViewIds,
        'dialogs': MultiViewDesktop.allDialogViewsIds,
        'closeMode': MultiViewDesktop.getCloseMode().name,
        'anchorId': MultiViewDesktop.getAnchorId(),
        'contextIds': deps.contexts.registeredViewIds,
        'openPopups': popups.entries
            .where((e) => e.value.controller.isOpen)
            .map((e) => e.key)
            .toList(),
        'macosParams': {
          'closeAppAfterLastWindowClosed':
              e2eCloseAppAfterLastWindowClosedFromEnvironment(),
          'saveLastWindowToReopen': e2eSaveLastWindowToReopenFromEnvironment(),
        },
      };
    },

    'get_window_state': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      return windowStateMap(viewId);
    },

    'create_window': (req) async {
      final parentId = req.optional<num>('parentId')?.toInt();
      BuildContext? parentContext;
      if (parentId != null) {
        parentContext = deps.contexts.require(parentId);
      }

      final options = parseWindowOptions(req);
      final animation = parseAnimation(req);
      final content = req.optional<String>('content') ?? 'home';
      final id = await openWindow(
        windowBuilderFor(req),
        parentContext: parentContext,
        options: options,
        animation: animation,
      );
      await Future<void>.delayed(const Duration(milliseconds: kE2eHostRegisterMs));
      await applyLockedFlags(id, req);
      await settleOpen(req);
      return {
        'viewId': id,
        'parentId': parentId,
        'content': content,
        'state': windowStateMap(id),
      };
    },

    'create_windows': (req) async {
      final count = req.require<num>('count').toInt();
      final animation = parseAnimation(req);
      final builder = windowBuilderFor(req);
      final ids = <int>[];
      for (var i = 0; i < count; i++) {
        final id = await openWindow(
          builder,
          options: WindowOptions(
            title: req.optional<String>('titlePrefix') != null
                ? '${req.optional<String>('titlePrefix')} ${i + 1}'
                : 'E2E window ${i + 1}/$count',
            size: parseSize(req) ?? const Size(800, 600),
            minimumSize:
                parseSize(req, w: 'minWidth', h: 'minHeight') ?? const Size(400, 300),
            maximumSize: parseSize(req, w: 'maxWidth', h: 'maxHeight'),
            alignment: parseAlignment(req.optional<String>('alignment')) ?? Alignment.center,
            titleBarStyle: parseTitleBarStyle(req.optional<String>('titleBarStyle')),
          ),
          animation: animation,
        );
        ids.add(id);
        await applyLockedFlags(id, req);
        await settleOpen(req);
      }
      return {
        'viewIds': ids,
        'content': req.optional<String>('content') ?? 'home',
      };
    },

    'close_window': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      return softCloseView(viewId, req);
    },

    'close_windows': (req) async {
      final raw = req.require<List<dynamic>>('viewIds');
      final ids = raw.map((e) => (e as num).toInt()).toList();
      final results = <Map<String, Object?>>[];
      for (final id in ids) {
        results.add(await softCloseView(id, req));
      }
      return {'results': results};
    },

    'answer_close_confirm': (req) async {
      final accept = req.require<bool>('accept');
      final timeoutMs = req.optional<num>('timeoutMs')?.toInt() ?? 5000;
      final answered = await answerPreventCloseConfirm(
        accept: accept,
        dialogsBefore: <int>{},
        timeoutMs: timeoutMs,
      );
      return {'answered': answered, 'accept': accept};
    },

    'destroy_window': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      final win = MultiViewDesktop.fromId(viewId);
      win.setPreventClose(false);
      final ok = await win.closeWindow(animation: parseAnimation(req));
      await settleClose(req);
      return {'closed': ok, 'viewId': viewId};
    },

    'set_window_flags': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      await applyLockedFlags(viewId, req);
      return windowStateMap(viewId);
    },

    'set_prevent_close': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      final value = req.require<bool>('value');
      MultiViewDesktop.fromId(viewId).setPreventClose(value);
      return {'viewId': viewId, 'preventClose': value};
    },

    'set_close_mode': (req) async {
      final name = req.require<String>('mode');
      final mode = CloseMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => throw ArgumentError('Unknown CloseMode "$name"'),
      );
      MultiViewDesktop.setCloseMode(mode);
      return {'closeMode': mode.name};
    },

    'close_app': (req) async {
      final name = req.optional<String>('mode');
      CloseMode? mode;
      if (name != null) {
        mode = CloseMode.values.firstWhere((m) => m.name == name);
      }
      // Same as softCloseView: answer HomePage ConfirmDialog while closeApp awaits
      // soft-close of a preventClose root (e.g. forceSecondary -> soft-close primary).
      final confirmClose = req.optional<bool>('confirmClose');
      final confirmTimeoutMs =
          req.optional<num>('confirmTimeoutMs')?.toInt() ?? 8000;
      final dialogsBefore = MultiViewDesktop.allDialogViewsIds.toSet();
      final pending = MultiViewDesktop.closeApp(closeMode: mode);

      var confirmAnswered = false;
      if (confirmClose != null) {
        confirmAnswered = await answerPreventCloseConfirm(
          accept: confirmClose,
          dialogsBefore: dialogsBefore,
          timeoutMs: confirmTimeoutMs,
        );
        if (!confirmAnswered) {
          for (final id in List<int>.from(MultiViewDesktop.allWindowViewIds)) {
            MultiViewDesktop.fromId(id).cancelCascadeClose();
          }
          throw StateError(
            'Prevent-close ConfirmDialog did not appear within '
            '${confirmTimeoutMs}ms during close_app. '
            'Set preventClose on the primary and pass confirmClose:true|false.',
          );
        }
        // HomePage Cancel leaves cancelCascadeClose commented out; return false
        // from onWindowClose should abort, but after forceSecondary the root wait
        // can stay pending - abort explicitly so closeApp can finish.
        if (confirmClose == false) {
          for (final id in List<int>.from(MultiViewDesktop.allWindowViewIds)) {
            MultiViewDesktop.fromId(id).cancelCascadeClose();
          }
        }
      }

      final ok = await pending.timeout(
        Duration(milliseconds: confirmTimeoutMs + 15000),
        onTimeout: () {
          for (final id in List<int>.from(MultiViewDesktop.allDialogViewsIds)) {
            if (!dialogsBefore.contains(id)) {
              unawaited(MultiViewDesktop.fromId(id).closeDialog<bool>(false));
            }
          }
          for (final id in List<int>.from(MultiViewDesktop.allWindowViewIds)) {
            MultiViewDesktop.fromId(id).cancelCascadeClose();
          }
          throw TimeoutException(
            'close_app timed out. If a preventClose ConfirmDialog is shown, '
            'pass confirmClose:true|false.',
          );
        },
      );
      return {
        'allClosed': ok,
        'confirmClose': ?confirmClose,
        if (confirmClose != null) 'confirmAnswered': confirmAnswered,
      };
    },

    'cancel_cascade': (req) async {
      final viewId = req.require<num>('viewId').toInt();
      MultiViewDesktop.fromId(viewId).cancelCascadeClose();
      return {'viewId': viewId, 'cancelled': true};
    },

    'open_os_dialog': (req) async {
      final parentId = req.require<num>('parentId').toInt();
      final parentContext = deps.contexts.require(parentId);
      final options = parseDialogOptions(req);
      final animation = parseAnimation(req);

      final content = req.optional<String>('content') ?? 'alert';
      Widget dialogChild(BuildContext context, int viewId) {
        final Widget body = switch (content) {
          'circles' => const CirclesScreen(),
          _ => defaultDialog(context, viewId),
        };
        if (content == 'circles') {
          return E2eHost(store: deps.contexts, child: body);
        }
        return body;
      }

      final entry = await openDialogEntry<String>(
        dialogChild,
        parentContext: parentContext,
        options: options,
        animation: animation,
      );
      await Future<void>.delayed(const Duration(milliseconds: kE2eHostRegisterMs));
      await applyLockedFlags(entry.id, req);
      await settleOpen(req);
      return {
        'dialogId': entry.id,
        'parentId': parentId,
        'content': content,
        'modal': options.modal ?? true,
        'state': windowStateMap(entry.id),
      };
    },

    'close_dialog': (req) async {
      final dialogId = req.require<num>('dialogId').toInt();
      final result = req.optional<String>('result');
      final ok = await MultiViewDesktop.fromId(dialogId).closeDialog(
            result,
            parseAnimation(req),
          );
      await settleClose(req);
      return {'closed': ok, 'dialogId': dialogId};
    },

    'open_overlay_dialog': (req) async {
      final parentId = req.require<num>('parentId').toInt();
      final parentContext = deps.contexts.require(parentId);
      unawaited(
        showDialog<void>(
          context: parentContext,
          builder: (ctx) {
            return deps.overlayDialogBuilder?.call(ctx) ??
                AlertDialog(
                  title: const Text('E2E overlay dialog'),
                  content: const Text('In-window Material dialog'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
          },
        ),
      );
      await settleOpen(req);
      return {'parentId': parentId, 'opened': true};
    },

    'open_popup': (req) async {
      final parentId = req.require<num>('parentId').toInt();
      final parentContext = deps.contexts.require(parentId);
      final overlay = Overlay.maybeOf(parentContext, rootOverlay: true);
      if (overlay == null) {
        throw StateError('No Overlay for parentId=$parentId');
      }

      final existing = popups[parentId];
      if (existing != null) {
        await existing.controller.close();
        existing.entry.remove();
        popups.remove(parentId);
      }

      final controller = PopupController();
      final animation = parseAnimation(req);
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          return Positioned(
            left: 48,
            top: 48,
            child: PopupView(
              controller: controller,
              builder: (popupCtx) {
                return Material(
                  elevation: 6,
                  child: SizedBox(
                    width: 220,
                    height: 120,
                    child: deps.popupChildBuilder?.call(popupCtx, controller) ??
                        Center(
                          child: TextButton(
                            onPressed: () => controller.close(),
                            child: Text('E2E popup on #$parentId'),
                          ),
                        ),
                  ),
                );
              },
              child: const SizedBox(width: 8, height: 8),
            ),
          );
        },
      );

      overlay.insert(entry);
      popups[parentId] = _PopupSession(controller: controller, entry: entry);
      await controller.open(animation: animation);
      await settleOpen(req);
      return {'parentId': parentId, 'open': true};
    },

    'close_popup': (req) async {
      final parentId = req.require<num>('parentId').toInt();
      final session = popups.remove(parentId);
      if (session == null) {
        return {'parentId': parentId, 'closed': false};
      }
      await session.controller.close(animation: parseAnimation(req));
      session.entry.remove();
      await settleClose(req);
      return {'parentId': parentId, 'closed': true};
    },

    'wait_ms': (req) async {
      final ms = req.require<num>('ms').toInt();
      await Future<void>.delayed(Duration(milliseconds: ms));
      return {'waitedMs': ms};
    },

    'wait_open_settle': (req) async {
      await settleOpen(req);
      return {'settled': true};
    },

    'wait_close_settle': (req) async {
      await settleClose(req);
      return {'settled': true};
    },
  };
}

class _PopupSession {
  _PopupSession({required this.controller, required this.entry});

  final PopupController controller;
  final OverlayEntry entry;
}
