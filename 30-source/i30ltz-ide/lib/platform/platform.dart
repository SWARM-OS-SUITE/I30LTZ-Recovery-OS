// Drop-in replacement for dart:io's Platform. Identical on desktop; on web
// (the Vercel mock build) it returns harmless values instead of throwing.
export 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
