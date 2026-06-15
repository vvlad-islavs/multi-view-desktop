import 'package:flutter/material.dart';

/// Main window seed (deep purple).
ThemeData mainLightTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
  useMaterial3: true,
);

ThemeData mainDarkTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
  useMaterial3: true,
);

/// Secondary window / GoRouter demo (teal accent).
ThemeData secondaryLightTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  useMaterial3: true,
);

ThemeData secondaryDarkTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
  useMaterial3: true,
);
