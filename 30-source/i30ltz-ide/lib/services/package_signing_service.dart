import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

enum SignatureVerificationStatus {
  verifiedOfficial,
  verifiedPartner,
  unverifiedCommunity,
  invalidSignature,
  unsigned,
}

class ExtensionManifest {
  final String id;
  final String name;
  final String version;
  final String publisher;
  final String description;
  final String main;
  final List<String> permissions;
  final Map<String, dynamic> raw;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.publisher,
    required this.description,
    required this.main,
    this.permissions = const [],
    this.raw = const {},
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    return ExtensionManifest(
      id: json['id'] as String? ?? 'unknown.ext',
      name: json['name'] as String? ?? 'Unnamed Extension',
      version: json['version'] as String? ?? '0.1.0',
      publisher: json['publisher'] as String? ?? 'anonymous',
      description: json['description'] as String? ?? '',
      main: json['main'] as String? ?? 'extension.js',
      permissions: (json['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'publisher': publisher,
        'description': description,
        'main': main,
        'permissions': permissions,
        ...raw,
      };
}

class SignedPackage {
  final ExtensionManifest manifest;
  final String payloadBase64;
  final String signature;
  final String publisherKeyFingerprint;
  // The signer's actual Ed25519 public key, hex-encoded. Verification is
  // asymmetric: a third party checks the signature against THIS key, never
  // against a secret only the signer knows. The fingerprint above is a short
  // display hash of the same bytes; verifyPackage() checks the full key.
  final String publisherPublicKeyHex;
  final SignatureVerificationStatus verificationStatus;

  const SignedPackage({
    required this.manifest,
    required this.payloadBase64,
    required this.signature,
    required this.publisherKeyFingerprint,
    required this.publisherPublicKeyHex,
    required this.verificationStatus,
  });

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'payload': payloadBase64,
        'signature': signature,
        'publisherKeyFingerprint': publisherKeyFingerprint,
        'publisherPublicKeyHex': publisherPublicKeyHex,
      };

  factory SignedPackage.fromJson(Map<String, dynamic> json) {
    final manifest = ExtensionManifest.fromJson(json['manifest'] as Map<String, dynamic>? ?? {});
    final sig = json['signature'] as String? ?? '';
    final fp = json['publisherKeyFingerprint'] as String? ?? '';
    final pubKeyHex = json['publisherPublicKeyHex'] as String? ?? '';

    // Trust is NEVER derived from the package's own contents. `fp`,
    // `pubKeyHex` and `manifest.publisher` are all attacker-controlled: any
    // bundle could claim publisher "swarm.io" and embed any key it likes.
    // Parsing only records whether a signature is present; granting trust
    // requires verifyPackage() to actually recompute the Ed25519 signature
    // check against the embedded key, and "official" requires that key to
    // match the hardcoded root public key.
    final SignatureVerificationStatus status = sig.isEmpty
        ? SignatureVerificationStatus.unsigned
        : SignatureVerificationStatus.unverifiedCommunity;

    return SignedPackage(
      manifest: manifest,
      payloadBase64: json['payload'] as String? ?? '',
      signature: sig,
      publisherKeyFingerprint: fp,
      publisherPublicKeyHex: pubKeyHex,
      verificationStatus: status,
    );
  }
}

class PackageSigningService {
  static final PackageSigningService instance = PackageSigningService._();
  PackageSigningService._();

  static final Ed25519 _ed25519 = Ed25519();

  // The real SWARM root Ed25519 public key (bo63/bo64, 2026-09-19). Safe to
  // embed — a public key proves nothing by itself, it only lets a verifier
  // check whether a signature was made by whoever holds the matching private
  // key. That private key lives at 20-runtime/secrets/ on i30ltz's machine
  // only (gitignored, never committed) — see the README there for custody
  // and rotation notes. Nothing in this app currently signs with the root
  // key; this constant exists so `verifiedOfficial` has a real asymmetric
  // anchor behind it instead of the literal string constant this replaced.
  static const String officialRootPublicKeyHex =
      'c1dcb2ba9fe6d0f3f8dbab525a659de03ac5fd4af87d634165686b18fb339e9e';

  static String get officialRootFingerprint => _fingerprintOf(officialRootPublicKeyHex);

  static String _fingerprintOf(String publicKeyHex) {
    final hash = sha256.convert(_hexToBytes(publicKeyHex)).toString();
    return 'SWARM-ED25519-${hash.substring(0, 16).toUpperCase()}';
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Validates an extension manifest for required fields
  List<String> validateManifest(Map<String, dynamic> json) {
    final errors = <String>[];
    if ((json['id'] as String? ?? '').trim().isEmpty) errors.add('Missing required field: "id"');
    if ((json['name'] as String? ?? '').trim().isEmpty) errors.add('Missing required field: "name"');
    if ((json['version'] as String? ?? '').trim().isEmpty) errors.add('Missing required field: "version"');
    if ((json['publisher'] as String? ?? '').trim().isEmpty) errors.add('Missing required field: "publisher"');
    return errors;
  }

  /// Calculates SHA256 digest of payload
  String calculateDigest(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  /// Signature prefix. Real Ed25519 now (2026-09-19) — an asymmetric
  /// signature, so a verifier can check *who* signed something using only
  /// the public key carried in the package, with no shared secret required.
  /// Replaces the earlier "HMAC-SHA256-" stopgap, which could only prove the
  /// signer held *a* key, never which publisher they were.
  static const String sigPrefix = 'ED25519-SIG-';

  /// The community publisher flow asks for a typed secret phrase, not 32
  /// bytes of raw key material nobody can type reliably. Hashing the phrase
  /// into a deterministic seed keeps that UX unchanged while producing a
  /// real Ed25519 keypair: the same phrase always yields the same identity
  /// across a publisher's own extensions, and different phrases are
  /// unlinkable, which is the actual property "publisher identity" needs.
  Future<SimpleKeyPair> _deriveKeyPair(String phraseOrKeyHex) async {
    final seed = sha256.convert(utf8.encode(phraseOrKeyHex)).bytes;
    return _ed25519.newKeyPairFromSeed(seed);
  }

  /// Signs an extension package with real Ed25519 over the payload and
  /// manifest digest, so tampering with either is detectable by
  /// verifyPackage(). [privateKeyHex] is the publisher's self-chosen secret
  /// phrase (see _deriveKeyPair) — the root key is never used here; nothing
  /// in the app currently signs as root (see officialRootPublicKeyHex).
  Future<SignedPackage> signPackage({
    required ExtensionManifest manifest,
    required String payloadContent,
    required String privateKeyHex,
    String? publisherFingerprint,
  }) async {
    final keyPair = await _deriveKeyPair(privateKeyHex);
    final publicKey = await keyPair.extractPublicKey();
    final pubKeyHex = _bytesToHex(publicKey.bytes);

    final digest = calculateDigest(payloadContent + jsonEncode(manifest.toJson()));
    final sig = await _ed25519.sign(utf8.encode(digest), keyPair: keyPair);
    final signature = '$sigPrefix${_bytesToHex(sig.bytes)}';

    final fp = publisherFingerprint ??
        'COMMUNITY-PUBKEY-${sha256.convert(utf8.encode(pubKeyHex)).toString().substring(0, 12).toUpperCase()}';

    return SignedPackage(
      manifest: manifest,
      payloadBase64: base64Encode(utf8.encode(payloadContent)),
      signature: signature,
      publisherKeyFingerprint: fp,
      publisherPublicKeyHex: pubKeyHex,
      // Signing locally never confers official trust by itself — verifyPackage()
      // decides that by comparing the embedded public key against the root.
      verificationStatus: SignatureVerificationStatus.unverifiedCommunity,
    );
  }

  /// Verifies the Ed25519 signature against the public key carried in the
  /// package itself — asymmetric verification needs no shared secret from
  /// the verifier. Fails closed: a malformed key, a signature that doesn't
  /// verify, or a missing signature are all treated as untrusted, never
  /// promoted on the strength of the package's own claims. "Official" status
  /// requires the embedded public key to match the hardcoded root key byte
  /// for byte, not just a fingerprint string comparison.
  Future<SignatureVerificationStatus> verifyPackage(SignedPackage package) async {
    if (package.signature.isEmpty) return SignatureVerificationStatus.unsigned;
    if (!package.signature.startsWith(sigPrefix) || package.publisherPublicKeyHex.isEmpty) {
      // Includes legacy "HMAC-SHA256-" bundles from the pre-Ed25519 signer,
      // which were symmetric and are not verifiable this way.
      return SignatureVerificationStatus.invalidSignature;
    }

    final String payloadContent;
    final List<int> publicKeyBytes;
    final List<int> sigBytes;
    try {
      payloadContent = utf8.decode(base64Decode(package.payloadBase64));
      publicKeyBytes = _hexToBytes(package.publisherPublicKeyHex);
      sigBytes = _hexToBytes(package.signature.substring(sigPrefix.length));
    } catch (_) {
      return SignatureVerificationStatus.invalidSignature;
    }

    final digest = calculateDigest(payloadContent + jsonEncode(package.manifest.toJson()));
    final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
    final valid = await _ed25519.verify(
      utf8.encode(digest),
      signature: Signature(sigBytes, publicKey: publicKey),
    );
    if (!valid) return SignatureVerificationStatus.invalidSignature;

    return package.publisherPublicKeyHex == officialRootPublicKeyHex
        ? SignatureVerificationStatus.verifiedOfficial
        : SignatureVerificationStatus.unverifiedCommunity;
  }

  /// Packages a folder or source into `.swarm-ext` JSON bundle
  Future<File> exportSwarmExtBundle({
    required Directory targetDir,
    required ExtensionManifest manifest,
    required String privateKey,
    required String outputPath,
  }) async {
    // Gather all files
    final fileMap = <String, String>{};
    if (targetDir.existsSync()) {
      for (final entity in targetDir.listSync(recursive: true)) {
        if (entity is File) {
          final relPath = entity.path.replaceFirst('${targetDir.path}/', '');
          try {
            fileMap[relPath] = await entity.readAsString();
          } catch (_) {}
        }
      }
    }

    final rawPayload = jsonEncode(fileMap.isNotEmpty ? fileMap : {'main.js': '// Swarm extension entrypoint\nconsole.log("Extension loaded");'});
    final signed = await signPackage(manifest: manifest, payloadContent: rawPayload, privateKeyHex: privateKey);

    final file = File(outputPath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(signed.toJson()));
    return file;
  }
}
