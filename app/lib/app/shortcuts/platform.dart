import 'package:flutter/foundation.dart';

/// Whether the app runs on macOS. Read from [defaultTargetPlatform] (not `dart:io`), so a test can
/// switch it with `debugDefaultTargetPlatformOverride`.
bool get isMac => defaultTargetPlatform == TargetPlatform.macOS;

/// The modifier of the shortcuts in the style of common business-app shortcuts: Alt, and Ctrl on
/// macOS (where Option types special characters and Cmd belongs to the system and the browser).
String get primaryModifierLabel => isMac ? 'Ctrl' : 'Alt';
