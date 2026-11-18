import 'package:material_ui/material_ui.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

/// Minimal window content for E2E (no [HomePage] ConfirmDialog).
///
/// Not for preventClose probes - those use [HomePage] + `confirmClose`.
class E2ePlainPage extends StatelessWidget {
  const E2ePlainPage({super.key, this.label = 'E2E window'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final id = MultiViewDesktop.of(context).id;
    return Material(
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Text(
          '$label\nview #$id',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 16),
        ),
      ),
    );
  }
}
