import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Open/close fade policy for a [ViewOwnerBase] implementation.
@internal
class ViewOwnerFadeConfig {
  const ViewOwnerFadeConfig({
    this.fadeInOnOpen = false,
    this.fadeOutOnClose = false,
    this.openDuration = const Duration(milliseconds: 500),
    this.closeDuration = const Duration(milliseconds: 500),
    this.curve = Curves.easeIn,
  });

  static const none = ViewOwnerFadeConfig();

  static const windowDefaults = ViewOwnerFadeConfig(
    fadeInOnOpen: true,
    fadeOutOnClose: true,
  );

  static const modelessDialogDefaults = ViewOwnerFadeConfig(
    fadeInOnOpen: true,
    fadeOutOnClose: true,
    openDuration: Duration(milliseconds: 250),
  );

  final bool fadeInOnOpen;
  final bool fadeOutOnClose;
  final Duration openDuration;
  final Duration closeDuration;
  final Curve curve;
}
