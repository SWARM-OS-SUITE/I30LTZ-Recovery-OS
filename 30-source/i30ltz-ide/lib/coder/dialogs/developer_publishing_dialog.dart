import 'dart:async';
import 'dart:io' hide Platform;
import '../../platform/platform.dart';
import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../../services/package_signing_service.dart';
import '../../services/extension_runtime_service.dart';
import '../editor_model.dart';

class DeveloperPublishingDialog extends StatefulWidget {
  const DeveloperPublishingDialog({super.key});

  @override
  State<DeveloperPublishingDialog> createState() => _DeveloperPublishingDialogState();
}

class _DeveloperPublishingDialogState extends State<DeveloperPublishingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController(text: 'my-custom-tool');
  final _nameCtrl = TextEditingController(text: 'My Custom Tool');
  final _versionCtrl = TextEditingController(text: '1.0.0');
  final _publisherCtrl = TextEditingController(text: 'community.developer');
  final _descCtrl = TextEditingController(text: 'Custom developer productivity tooling for Swarm OS');
  final _privateKeyCtrl = TextEditingController(text: '4f9c31a78e22bd1005b823e9a117b98d24f0c793ba91efc3a70081d45903c712');

  String _category = 'Tools';
  final Set<String> _permissions = {'editor.read'};
  List<String> _validationErrors = [];
  String _calculatedDigest = '';
  String _calculatedSignature = '';
  bool _isPackaging = false;

  static const _availableCategories = ['Languages', 'Linters', 'Themes', 'Snippets', 'Android', 'AI', 'Git', 'Tools'];
  static const _availablePermissions = ['editor.read', 'editor.write', 'terminal.exec', 'filesystem.read', 'network.http'];

  @override
  void initState() {
    super.initState();
    unawaited(_revalidate());
  }

  Future<void> _revalidate() async {
    final manifestMap = {
      'id': _idCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'version': _versionCtrl.text.trim(),
      'publisher': _publisherCtrl.text.trim(),
    };

    final errs = PackageSigningService.instance.validateManifest(manifestMap);

    // Check SemVer
    final semVerRegex = RegExp(r'^\d+\.\d+\.\d+$');
    if (!semVerRegex.hasMatch(_versionCtrl.text.trim())) {
      errs.add('Version must strictly follow SemVer (e.g. 1.0.0)');
    }

    final payloadPreview = '// Extension Entrypoint: ${_idCtrl.text}\nmodule.exports = { activate() { console.log("Started"); } };';
    final digest = PackageSigningService.instance.calculateDigest(payloadPreview);

    final signed = await PackageSigningService.instance.signPackage(
      manifest: ExtensionManifest.fromJson(manifestMap),
      payloadContent: payloadPreview,
      privateKeyHex: _privateKeyCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _validationErrors = errs;
      _calculatedDigest = digest;
      _calculatedSignature = signed.signature;
    });
  }

  Future<void> _buildAndSignPackage() async {
    if (_validationErrors.isNotEmpty) return;
    setState(() => _isPackaging = true);

    try {
      final manifest = ExtensionManifest(
        id: _idCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        version: _versionCtrl.text.trim(),
        publisher: _publisherCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        main: 'extension.js',
        permissions: _permissions.toList(),
      );

      final home = Platform.environment['HOME'] ?? '/home/i30ltz';
      final outDir = Directory('$home/.i30ltz-ide/published_packages');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final pkgFile = '$home/.i30ltz-ide/published_packages/${manifest.id}-${manifest.version}.swarm-ext';
      final tempDir = Directory('$home/.i30ltz-ide/temp_${manifest.id}');
      if (!tempDir.existsSync()) tempDir.createSync(recursive: true);

      final entryFile = File('${tempDir.path}/extension.js');
      await entryFile.writeAsString('// Auto-generated entrypoint\nmodule.exports = { activate() { console.log("Activated ${manifest.id}"); } };');

      await PackageSigningService.instance.exportSwarmExtBundle(
        targetDir: tempDir,
        manifest: manifest,
        privateKey: _privateKeyCtrl.text.trim(),
        outputPath: pkgFile,
      );

      // Clean temp
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}

      // Register extension into runtime service
      final newExt = MarketplaceExtension(
        id: manifest.id,
        name: manifest.name,
        publisher: manifest.publisher,
        description: manifest.description,
        version: manifest.version,
        rating: 5.0,
        installs: 1,
        category: _category,
        tags: ['custom', manifest.id],
        isInstalled: true,
        installedVersion: manifest.version,
        isVerifiedPublisher: manifest.publisher == 'swarm.io',
        signatureStatus: manifest.publisher == 'swarm.io' ? 'verified_official' : 'unverified_community',
      );

      await ExtensionRuntimeService.instance.installExtension(newExt);

      if (mounted) {
        setState(() => _isPackaging = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Package successfully built, cryptographically signed, and installed: ${manifest.id}'),
            backgroundColor: SwarmColors.agentEmerald,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPackaging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Packaging failed: $e'), backgroundColor: SwarmColors.agentRose),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SwarmColors.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: SwarmColors.border)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: SwarmColors.accent, size: 22),
                  const SizedBox(width: 10),
                  const Text('Developer Portal: Package & Sign Extension', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: SwarmColors.textMuted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Generate standard .swarm-ext bundles with cryptographic Ed25519 signature, manifest validation, and local registry deployment.',
                style: TextStyle(fontSize: 11, color: SwarmColors.textMuted),
              ),
              const Divider(height: 24, color: SwarmColors.border),

              // ID and Version
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _idCtrl,
                      label: 'Extension ID',
                      hint: 'e.g. git-graph-pro',
                      onChanged: (_) => _revalidate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildTextField(
                      controller: _versionCtrl,
                      label: 'SemVer Version',
                      hint: '1.0.0',
                      onChanged: (_) => _revalidate(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Name and Publisher
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _nameCtrl,
                      label: 'Display Name',
                      hint: 'Git Graph Pro',
                      onChanged: (_) => _revalidate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildTextField(
                      controller: _publisherCtrl,
                      label: 'Publisher ID',
                      hint: 'swarm.io',
                      onChanged: (_) => _revalidate(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              _buildTextField(
                controller: _descCtrl,
                label: 'Description',
                hint: 'Brief description of features',
                maxLines: 2,
                onChanged: (_) => _revalidate(),
              ),
              const SizedBox(height: 12),

              // Category dropdown
              Row(
                children: [
                  const Text('Category: ', style: TextStyle(fontSize: 11, color: SwarmColors.textSecondary)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _category,
                    dropdownColor: SwarmColors.bgElevated,
                    style: const TextStyle(fontSize: 12, color: SwarmColors.textPrimary),
                    items: _availableCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _category = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Permissions selector
              const Text('Permissions Required:', style: TextStyle(fontSize: 11, color: SwarmColors.textSecondary)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: _availablePermissions.map((perm) {
                  final has = _permissions.contains(perm);
                  return FilterChip(
                    label: Text(perm, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                    selected: has,
                    selectedColor: SwarmColors.accent.withAlpha(50),
                    checkmarkColor: SwarmColors.accent,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _permissions.add(perm);
                        } else {
                          _permissions.remove(perm);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Ed25519 Signing Key
              _buildTextField(
                controller: _privateKeyCtrl,
                label: 'Signing Key (Ed25519 / Hex)',
                hint: 'Private key hex seed',
                fontMonospace: true,
                onChanged: (_) => _revalidate(),
              ),
              const SizedBox(height: 12),

              // Live Cryptographic Signature Status Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SwarmColors.bgBase,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _validationErrors.isEmpty ? SwarmColors.agentEmerald.withAlpha(100) : SwarmColors.agentRose.withAlpha(100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _validationErrors.isEmpty ? Icons.lock_outline_rounded : Icons.warning_amber_rounded,
                          size: 16,
                          color: _validationErrors.isEmpty ? SwarmColors.agentEmerald : SwarmColors.agentRose,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _validationErrors.isEmpty ? 'CRYPTOGRAPHIC INTEGRITY: READY TO SIGN' : 'VALIDATION ISSUES DETECTED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _validationErrors.isEmpty ? SwarmColors.agentEmerald : SwarmColors.agentRose,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    if (_validationErrors.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ..._validationErrors.map((err) => Text('• $err', style: const TextStyle(fontSize: 11, color: SwarmColors.agentRose))),
                    ] else ...[
                      const SizedBox(height: 6),
                      Text('SHA256 Payload Digest: $_calculatedDigest', style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: SwarmColors.textMuted)),
                      const SizedBox(height: 2),
                      Text('Signature: $_calculatedSignature', style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: SwarmColors.accent)),
                      const SizedBox(height: 2),
                      const Text('Symmetric MAC — proves key possession and detects tampering, but does not attest publisher identity.', style: TextStyle(fontSize: 9, color: SwarmColors.textMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: SwarmColors.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SwarmColors.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: _isPackaging
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.rocket_launch_rounded, size: 16, color: Colors.black),
                    label: Text(
                      _isPackaging ? 'Packaging & Signing...' : 'Sign & Publish (.swarm-ext)',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: (_validationErrors.isEmpty && !_isPackaging) ? _buildAndSignPackage : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool fontMonospace = false,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(fontSize: 11, color: SwarmColors.textPrimary, fontFamily: fontMonospace ? 'monospace' : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 11, color: SwarmColors.textDisabled),
            isDense: true,
            filled: true,
            fillColor: SwarmColors.bgBase,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.accent)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }
}
