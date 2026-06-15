import 'package:flutter/material.dart';

class AlertViewDialog extends StatelessWidget {
  const AlertViewDialog({super.key, required this.title, required this.content, this.actions});

  final String title;
  final String content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(title, style: TextStyle(fontSize: 22)),
              Text(content, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              if (actions != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  // mainAxisSize: MainAxisSize.min,
                  children: [...?actions],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
