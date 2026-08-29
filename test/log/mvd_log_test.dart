import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:multiview_desktop/src/log/mvd_log.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mvd_log_test_');
    MvdLog.instance.resetForTest();
  });

  tearDown(() {
    MvdLog.instance.resetForTest();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('disabled logger writes nothing', () {
    MvdLog.instance.configure(const LogParams(enable: false), directoryOverride: dir);
    MvdLog.instance.info('test', 'should not appear');
    expect(MvdLog.instance.file, isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('enabled logger writes info to mvd.log', () {
    MvdLog.instance.configure(const LogParams(enable: true, sizeKb: 64), directoryOverride: dir);
    MvdLog.instance.info('shift', 'registerInitialWindow', {'realId': 28, 'shift': 27});

    final file = MvdLog.instance.file!;
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    expect(text, contains('[shift] registerInitialWindow'));
    expect(text, contains('realId=28'));
    expect(text, contains('shift=27'));
  });

  test('negative ids are logged as error', () {
    MvdLog.instance.configure(const LogParams(enable: true, sizeKb: 64), directoryOverride: dir);
    MvdLog.instance.ids(
      'shift',
      'window registered',
      realId: 28,
      publicId: -27,
      parentPublicId: -27,
      shift: 27,
    );

    final text = MvdLog.instance.file!.readAsStringSync();
    expect(text, contains(' E [shift]'));
    expect(text, contains('invalid view id'));
    expect(text, contains('publicId=-27'));
  });

  test('parent public id 0 is logged as error', () {
    MvdLog.instance.configure(const LogParams(enable: true, sizeKb: 64), directoryOverride: dir);
    MvdLog.instance.ids(
      'create',
      'window registered',
      realId: 18,
      publicId: 2,
      parentRealId: 16,
      parentPublicId: 0,
      shift: 16,
    );

    final text = MvdLog.instance.file!.readAsStringSync();
    expect(text, contains(' E [create]'));
    expect(text, contains('parentPublicId'));
    expect(text, contains('public ids must be >= 1'));
  });

  test('native create error codes are logged as error', () {
    MvdLog.instance.configure(const LogParams(enable: true, sizeKb: 64), directoryOverride: dir);
    MvdLog.instance.ids('create', 'WindowOwner native created', realId: -1);

    final text = MvdLog.instance.file!.readAsStringSync();
    expect(text, contains('native create returned error code'));
    expect(text, contains('realId=-1'));
  });

  test('rotates to mvd.log.prev when sizeKb is exceeded', () {
    MvdLog.instance.configure(const LogParams(enable: true, sizeKb: 1), directoryOverride: dir);
    for (var i = 0; i < 80; i++) {
      MvdLog.instance.info('fill', 'line $i ${'x' * 80}');
    }
    expect(File('${dir.path}${Platform.pathSeparator}mvd.log.prev').existsSync(), isTrue);
    expect(MvdLog.instance.file!.existsSync(), isTrue);
  });

  test('defaultLogDirectory is independent of kDebugMode', () {
    expect(MvdLog.defaultLogDirectory().path, isNotEmpty);
    expect(kDebugMode, isTrue);
    expect(MvdLog.defaultLogDirectory().path, contains('multiview_desktop'));
  });
}
