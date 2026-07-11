// Copyright 2024 - AdMob Integration Package
// Package-internal logging utility

import 'package:flutter/foundation.dart';

/// Package-internal logging function that is a no-op in release builds.
///
/// Unlike [debugPrint], this function checks [kDebugMode] first, preventing
/// operational details from leaking to device logs in production and
/// eliminating the minor overhead of string formatting and I/O.
///
/// All ad_flow source files should use this instead of [debugPrint].
void adFlowLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
