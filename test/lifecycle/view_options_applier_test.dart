import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/ffi/ffi_bridge.dart';
import 'package:multiview_desktop/src/lifecycle/view_options_applier.dart';

void main() {
  group('ViewOptionsApplier', () {
    late RecordingFfiBridge ffi;
    late ViewOptionsApplier applier;

    setUp(() {
      ffi = RecordingFfiBridge();
      applier = ViewOptionsApplier(ffi: ffi);
    });

    test('applyWindow maps all provided options', () {
      applier.applyWindow(
        1,
        WindowOptions(
          size: const Size(200, 100),
          alignment: Alignment.center,
          backgroundColor: const Color(0xFF112233),
          minimumSize: const Size(50, 50),
          maximumSize: const Size(400, 400),
          title: 'Hello',
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
          alwaysOnTop: true,
          fullScreen: false,
        ),
      );

      expect(ffi.hasCall('setSize:1:200.0x100.0'), isTrue);
      expect(ffi.hasCall('setAlignment:1:'), isTrue);
      expect(ffi.hasCall('setBackgroundColor:1'), isTrue);
      expect(ffi.hasCall('setMinSize:1:50.0x50.0'), isTrue);
      expect(ffi.hasCall('setMaxSize:1:400.0x400.0'), isTrue);
      expect(ffi.hasCall('setTitle:1:Hello'), isTrue);
      expect(ffi.hasCall('setTitleBarStyle:1:hidden'), isTrue);
      expect(ffi.hasCall('setAlwaysOnTop:1:true'), isTrue);
      expect(ffi.hasCall('setFullScreen:1:false'), isTrue);
    });

    test('applyWindow with only defaults still applies default alignment', () {
      applier.applyWindow(1, WindowOptions());
      expect(ffi.calls, ['setAlignment:1:0.0,0.0']);
    });

    test('applyDialog maps dialog options', () {
      applier.applyDialog(
        2,
        DialogOptions(
          size: const Size(120, 80),
          backgroundColor: Colors.red,
          minimumSize: const Size(10, 10),
          maximumSize: const Size(300, 300),
          isResizable: true,
          title: 'Dlg',
          titleBarStyle: TitleBarStyle.normal,
          windowButtonVisibility: true,
          alwaysOnTop: false,
        ),
      );

      // size is skipped on Windows only
      expect(ffi.hasCall('setBackgroundColor:2'), isTrue);
      expect(ffi.hasCall('setMinSize:2:10.0x10.0'), isTrue);
      expect(ffi.hasCall('setMaxSize:2:300.0x300.0'), isTrue);
      expect(ffi.hasCall('setResizable:2:true'), isTrue);
      expect(ffi.hasCall('setTitle:2:Dlg'), isTrue);
      expect(ffi.hasCall('setTitleBarStyle:2:normal'), isTrue);
      expect(ffi.hasCall('setAlwaysOnTop:2:false'), isTrue);
    });
  });
}
