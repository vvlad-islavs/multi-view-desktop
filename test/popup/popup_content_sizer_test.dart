import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/popup/popup_content_sizer.dart';

void main() {
  Future<Size?> pumpSizer(WidgetTester tester, {required Size maxSize, required Widget child, BoxConstraints? constraints}) async {
    Size? reported;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: constraints ?? BoxConstraints.loose(maxSize),
            child: PopupContentSizer(
              maxSize: maxSize,
              onSize: (size) => reported = size,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return reported;
  }

  testWidgets('Column shrink-wraps to children without an explicit size', (tester) async {
    final reported = await pumpSizer(
      tester,
      maxSize: const Size(400, 300),
      child: const Column(
        children: [
          SizedBox(width: 80, height: 20),
          SizedBox(width: 40, height: 30),
        ],
      ),
    );

    expect(reported, const Size(80, 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SizedBox sets the popup size', (tester) async {
    final reported = await pumpSizer(
      tester,
      maxSize: const Size(800, 600),
      child: const SizedBox(width: 120, height: 90, child: Placeholder()),
    );

    expect(reported, const Size(120, 90));
  });

  testWidgets('Column with Expanded does not throw unbounded constraints', (tester) async {
    final reported = await pumpSizer(
      tester,
      maxSize: const Size(400, 300),
      child: const Column(
        children: [
          SizedBox(width: 60, height: 16),
          Expanded(child: SizedBox.expand()),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(reported, isNotNull);
    expect(reported!.width, 60);
    expect(reported.height, lessThanOrEqualTo(300));
  });

  testWidgets('content size is independent of the current native view constraints', (tester) async {
    final reported = await pumpSizer(
      tester,
      maxSize: const Size(400, 300),
      constraints: BoxConstraints.tight(const Size(1, 1)),
      child: const SizedBox(width: 140, height: 70),
    );

    expect(reported, const Size(140, 70));
  });

  testWidgets('Overlay.wrap lets Slider build without a MaterialApp Overlay', (tester) async {
    await tester.pumpWidget(
      Material(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Theme(
              data: ThemeData.light(),
              child: Align(
                alignment: Alignment.topLeft,
                child: PopupContentSizer(
                  maxSize: const Size(400, 300),
                  onSize: (_) {},
                  child: Overlay.wrap(
                    alwaysSizeToContent: true,
                    child: Slider(value: 1, min: 0.2, max: 1, onChanged: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
  });
}
