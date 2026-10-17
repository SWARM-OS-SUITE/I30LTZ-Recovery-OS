import 'dart:io' as io;

class Platform {
  static Map<String, String> get environment => io.Platform.environment;
  static String get localHostname => io.Platform.localHostname;
  static int get numberOfProcessors => io.Platform.numberOfProcessors;
  static String get resolvedExecutable => io.Platform.resolvedExecutable;
}
