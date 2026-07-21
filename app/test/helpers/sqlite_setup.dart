import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Linux test helper for sqlite3 dynamic library loading.
//
// On Linux the sqlite3 package (transitive dep of sqflite_common_ffi) tries to
// load libsqlite3.so by default, but many distros ship only libsqlite3.so.0
// (no unversioned .so symlink).  In a Flutter test runner there is no
// sqlite3_flutter_libs plugin bundled, so the default open path fails with:
//   Failed to load dynamic library 'libsqlite3.so':
//   cannot open shared object file: No such file or directory
//
// The fix: override the sqlite3 package's library-loader with a fallback that
// tries libsqlite3.so first, then libsqlite3.so.0.
//
// ┌─ Important: sqflite_common_ffi spawns a background isolate ───────────┐
// │ databaseFactoryFfi  uses Isolate.spawn() – the override set in the   │
// │                     main isolate is NOT visible in the background     │
// │                     isolate (each isolate has its own heap).          │
// │                                                                       │
// │ databaseFactoryFfiNoIsolate  runs DB ops on the main isolate – the   │
// │                               override works correctly.              │
// │                                                                       │
// │ Always use databaseFactoryFfiNoIsolate in tests that open a database. │
// └───────────────────────────────────────────────────────────────────────┘

DynamicLibrary _openSqlite() {
  try {
    return DynamicLibrary.open('libsqlite3.so');
  } on ArgumentError {
    return DynamicLibrary.open('libsqlite3.so.0');
  }
}

void setupSqlite() {
  if (Platform.isLinux) {
    open.overrideForAll(_openSqlite);
  }
}

/// Returns an ffiInit callback for use with [createDatabaseFactoryFfi].
///
/// Pass this as the `ffiInit` argument when you must use the isolate-based
/// factory (rare).  The callback runs inside the spawned isolate where it
/// calls [open.overrideForAll] on the isolate's own heap.
SqfliteFfiInit ffiInitForIsolate() => () {
  if (Platform.isLinux) {
    open.overrideForAll(_openSqlite);
  }
};
