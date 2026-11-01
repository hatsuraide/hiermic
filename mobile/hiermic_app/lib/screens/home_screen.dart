import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/server_config.dart';
import '../models/server_info.dart';
import '../services/audio_service.dart';
import '../services/constants.dart';
import '../services/control_service.dart';
import '../services/discovery_service.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _SessionPhase { connecting, connected, error }

class _ServerSession {
  final String id;
  final ControlService control;
  ServerInfo server;
  _SessionPhase phase = _SessionPhase.connecting;
  String? error;

  _ServerSession({
    required this.id,
    required this.server,
    required this.control,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final _discovery = DiscoveryService();
  final _audio     = AudioService();
  final _settings  = SettingsService();

  final _sessions = <String, _ServerSession>{};
  List<ServerConfig> _configs    = [];
  List<ServerInfo>   _discovered = [];
  bool               _streaming  = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _startDiscovery();
    _loadConfigs();
  }

  List<ServerInfo> get _connectedServers => _sessions.values
      .where((session) => session.phase == _SessionPhase.connected)
      .map((session) => session.server)
      .toList();

  String get _status {
    if (_streaming) {
      final count = _connectedServers.length;
      return 'Streaming to $count server${count == 1 ? '' : 's'}';
    }

    final connecting = _sessions.values
        .where((session) => session.phase == _SessionPhase.connecting);
    if (connecting.isNotEmpty) {
      return 'Connecting to ${connecting.first.server.name}...';
    }

    final count = _connectedServers.length;
    if (count > 0) return 'Connected to $count server${count == 1 ? '' : 's'}';

    final failed = _sessions.values
        .any((session) => session.phase == _SessionPhase.error);
    if (failed) return 'Connection failed';

    return 'Scanning for servers...';
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    if (Platform.isAndroid) await Permission.nearbyWifiDevices.request();
  }

  Future<void> _startDiscovery() async {
    await _discovery.start();
    _discovery.servers.listen((servers) {
      setState(() => _discovered = servers);
    });
  }

  Future<void> _loadConfigs() async {
    try {
      final configs = await _settings.loadServerConfigs();
      if (!mounted) return;
      setState(() => _configs = configs);
    } catch (e) {
      debugPrint('Failed to load saved servers: $e');
    }
  }

  Future<void> _persistConfigs() async {
    try {
      await _settings.saveServerConfigs(_configs);
    } catch (e) {
      debugPrint('Failed to save servers: $e');
    }
  }

  String _keyFor(ServerInfo server) => '${server.address.address}:${server.port}';

  ServerConfig? _configForServer(ServerInfo server) {
    final id = _keyFor(server);
    for (final config in _configs) {
      if (config.id == id) return config;
    }
    return null;
  }

  Future<void> _connect(ServerInfo server) async {
    if (!mounted) return;

    final key = _keyFor(server);
    final existing = _sessions[key];

    if (existing != null) {
      // Already connecting or connected: nothing to do.
      if (existing.phase != _SessionPhase.error) return;

      // Retry: retire the failed session before replacing it.
      existing.control.onDisconnected = null;
      unawaited(existing.control.disconnect());
    }

    final control = ControlService();
    final session = _ServerSession(id: key, server: server, control: control);
    control.onDisconnected = () => _onSessionClosed(key);

    setState(() => _sessions[key] = session);

    try {
      await control.connect(server);
      if (!mounted || _sessions[key] != session) return;

      setState(() => session.phase = _SessionPhase.connected);

      // Servers connected while streaming join the audio fan-out immediately.
      if (_streaming) {
        control.sendStart();
        _audio.setTargets(_connectedServers);
      }

      // Keep every successfully used server in the saved list.
      unawaited(_rememberServer(server));
    } catch (e) {
      if (!mounted || _sessions[key] != session) return;
      setState(() {
        session.phase = _SessionPhase.error;
        session.error = e.toString();
      });
    }
  }

  Future<void> _connectConfig(ServerConfig config) => _connect(config.toServerInfo());

  Future<void> _connectDiscovered(ServerInfo server) =>
      _connect(_configForServer(server)?.toServerInfo() ?? server);

  void _onSessionClosed(String key) {
    final session = _sessions[key];
    if (session == null || !mounted) return;

    setState(() {
      session.phase = _SessionPhase.error;
      session.error = 'Connection lost';
    });

    _syncAudioTargets();
  }

  Future<void> _disconnectSession(String key) async {
    final session = _sessions.remove(key);
    if (session == null) return;

    session.control.onDisconnected = null;
    await session.control.disconnect();

    if (!mounted) return;
    setState(() {});

    _syncAudioTargets();
  }

  Future<void> _toggleStreaming() async {
    final targets = _connectedServers;
    if (targets.isEmpty) return;

    if (_streaming) {
      await _stopStreaming();
      return;
    }

    try {
      await _audio.startStreaming(targets);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not start microphone: $e');
      return;
    }

    for (final session in _sessions.values) {
      if (session.phase == _SessionPhase.connected) session.control.sendStart();
    }

    if (!mounted) return;
    setState(() => _streaming = true);
  }

  Future<void> _stopStreaming() async {
    for (final session in _sessions.values) {
      if (session.phase == _SessionPhase.connected) session.control.sendStop();
    }

    await _audio.stopStreaming();

    if (!mounted) return;
    setState(() => _streaming = false);
  }

  void _syncAudioTargets() {
    if (!_streaming) return;

    final targets = _connectedServers;
    if (targets.isEmpty) {
      unawaited(_stopStreaming());
    } else {
      _audio.setTargets(targets);
    }
  }

  Future<void> _editConfig(ServerConfig? existing) async {
    final result = await showDialog<ServerConfig>(
      context: context,
      builder: (_) => _ServerDialog(existing: existing),
    );
    if (result == null || !mounted) return;

    final duplicate = _configs.any((c) => c.id == result.id && c.id != existing?.id);
    if (duplicate) {
      _showMessage('${result.host}:${result.port} is already saved');
      return;
    }

    // Changing the address of an active config invalidates its session.
    if (existing != null && existing.id != result.id) {
      await _disconnectSession(existing.id);
      if (!mounted) return;
    }

    setState(() {
      final index = existing == null
          ? -1
          : _configs.indexWhere((c) => c.id == existing.id);

      if (index >= 0) {
        _configs[index] = result;
      } else {
        _configs.add(result);
      }

      // Renames should show up immediately on an active connection.
      final session = _sessions[result.id];
      if (session != null) session.server = result.toServerInfo();
    });

    await _persistConfigs();

    // Adding a new server flows straight into connecting to it.
    if (existing == null) unawaited(_connectConfig(result));
  }

  Future<void> _deleteConfig(ServerConfig config) async {
    await _disconnectSession(config.id);
    if (!mounted) return;

    setState(() => _configs.removeWhere((c) => c.id == config.id));
    await _persistConfigs();
  }

  Future<void> _saveDiscovered(ServerInfo server) async {
    final added = await _rememberServer(server);
    if (!mounted) return;
    if (added) {
      _showMessage('Saved ${server.name}');
    } else {
      _showMessage('${server.displayAddress} is already saved');
    }
  }

  /// Adds [server] to the saved list if it isn't there yet. Returns whether it
  /// was added.
  Future<bool> _rememberServer(ServerInfo server) async {
    final id = _keyFor(server);
    if (_configs.any((c) => c.id == id) || !mounted) return false;

    final config = ServerConfig(
      name: server.name,
      host: server.address.address,
      port: server.port,
    );

    setState(() => _configs.add(config));
    await _persistConfigs();
    return true;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final connectedCount = _connectedServers.length;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('HierMic', style: TextStyle(color: Colors.white)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'v${Constants.appVersion}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(status: _status, streaming: _streaming),
          if (connectedCount > 0) ...[
            const SizedBox(height: 16),
            _StreamButton(
              streaming: _streaming,
              onTap: _toggleStreaming,
            ),
          ],
          const SizedBox(height: 12),
          _SectionHeader(
            title: 'Saved servers',
            trailing: IconButton(
              tooltip: 'Add server',
              icon: const Icon(Icons.add, color: Colors.blueAccent),
              onPressed: () => _editConfig(null),
            ),
          ),
          if (_configs.isEmpty)
            const _HintCard(
              'No saved servers yet.\nTap + to add one, or save a discovered server.',
            )
          else
            ..._configs.map(
              (config) => _SavedServerTile(
                config: config,
                session: _sessions[config.id],
                onConnect: () => _connectConfig(config),
                onDisconnect: () => _disconnectSession(config.id),
                onEdit: () => _editConfig(config),
                onDelete: () => _deleteConfig(config),
              ),
            ),
          const SizedBox(height: 12),
          const _SectionHeader(title: 'Discovered on network'),
          if (_discovered.isEmpty)
            const _HintCard(
              'No servers found on this network.\nMake sure HierMic Server is running.',
            )
          else
            ..._discovered.map((server) {
              final session = _sessions[_keyFor(server)];
              return _DiscoveredServerTile(
                server: server,
                saved: _configForServer(server) != null,
                session: session,
                onConnect: () => _connectDiscovered(server),
                onSave: () => _saveDiscovered(server),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _discovery.dispose();
    unawaited(_audio.dispose());
    for (final session in _sessions.values) {
      session.control.onDisconnected = null;
      unawaited(session.control.disconnect());
    }
    super.dispose();
  }
}

class _StatusCard extends StatelessWidget {
  final String status;
  final bool streaming;
  const _StatusCard({required this.status, required this.streaming});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: streaming ? Colors.greenAccent : Colors.grey.shade800,
          width: streaming ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            streaming ? Icons.mic : Icons.mic_off,
            color: streaming ? Colors.greenAccent : Colors.grey,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(status, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: Colors.grey)),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onTap;
  final List<Widget> actions;

  const _ServerTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.onTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Only the entry itself is tappable; the action strip is not.
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ...actions,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _SavedServerTile extends StatelessWidget {
  final ServerConfig config;
  final _ServerSession? session;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SavedServerTile({
    required this.config,
    required this.session,
    required this.onConnect,
    required this.onDisconnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final phase = session?.phase;

    return _ServerTile(
      leading: phase == _SessionPhase.connecting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _phaseIcon(phase),
      title: config.name,
      subtitle: _subtitle(phase),
      subtitleColor: _subtitleColor(phase),
      onTap: onConnect,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.grey),
          onSelected: (value) {
            switch (value) {
              case 'disconnect':
                onDisconnect();
              case 'edit':
                onEdit();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            if (session != null)
              PopupMenuItem(
                value: 'disconnect',
                child: Text(
                  phase == _SessionPhase.connecting ? 'Cancel' : 'Disconnect',
                ),
              ),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }

  String _subtitle(_SessionPhase? phase) {
    final address = '${config.host}:${config.port}';
    switch (phase) {
      case _SessionPhase.connecting:
        return '$address · Connecting…';
      case _SessionPhase.connected:
        return '$address · Connected';
      case _SessionPhase.error:
        return '$address · ${session?.error ?? 'Connection failed'}';
      case null:
        return address;
    }
  }

  Color _subtitleColor(_SessionPhase? phase) {
    switch (phase) {
      case _SessionPhase.connected:
        return Colors.greenAccent;
      case _SessionPhase.error:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _phaseIcon(_SessionPhase? phase) {
    switch (phase) {
      case _SessionPhase.connected:
        return const Icon(Icons.check_circle, color: Colors.greenAccent);
      case _SessionPhase.connecting:
        return const Icon(Icons.sync, color: Colors.amber);
      case _SessionPhase.error:
        return const Icon(Icons.error_outline, color: Colors.redAccent);
      case null:
        return const Icon(Icons.computer, color: Colors.blueAccent);
    }
  }
}

class _DiscoveredServerTile extends StatelessWidget {
  final ServerInfo server;
  final bool saved;
  final _ServerSession? session;
  final VoidCallback onConnect;
  final VoidCallback onSave;

  const _DiscoveredServerTile({
    required this.server,
    required this.saved,
    required this.session,
    required this.onConnect,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final phase = session?.phase;

    return _ServerTile(
      leading: phase == _SessionPhase.connecting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              phase == _SessionPhase.connected
                  ? Icons.check_circle
                  : Icons.computer,
              color: phase == _SessionPhase.connected
                  ? Colors.greenAccent
                  : Colors.blueAccent,
            ),
      title: server.name,
      subtitle: saved
          ? '${server.displayAddress} · Saved'
          : server.displayAddress,
      subtitleColor: Colors.grey,
      onTap: onConnect,
      actions: [
        IconButton(
          tooltip: saved ? 'Already saved' : 'Save server',
          icon: Icon(
            saved ? Icons.bookmark : Icons.bookmark_add_outlined,
            color: saved ? Colors.greenAccent : Colors.grey,
          ),
          onPressed: saved ? null : onSave,
        ),
      ],
    );
  }
}

class _StreamButton extends StatelessWidget {
  final bool streaming;
  final VoidCallback onTap;
  const _StreamButton({
    required this.streaming,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = streaming ? 'TAP TO STOP' : 'TAP TO STREAM';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: streaming ? Colors.greenAccent.withOpacity(0.15) : const Color(0xFF1E1E1E),
          border: Border.all(
            color: streaming ? Colors.greenAccent : Colors.blueAccent,
            width: 3,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                streaming ? Icons.mic : Icons.mic_none,
                size: 64,
                color: streaming ? Colors.greenAccent : Colors.blueAccent,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: streaming ? Colors.greenAccent : Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  final ServerConfig? existing;
  const _ServerDialog({this.existing});

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _hostCtrl = TextEditingController(text: widget.existing?.host ?? '');
    _portCtrl = TextEditingController(
      text: '${widget.existing?.port ?? Constants.controlPort}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final parsedHost  = InternetAddress.tryParse(_hostCtrl.text.trim());
    final parsedPort  = int.tryParse(_portCtrl.text.trim());

    if (parsedHost == null) {
      setState(() => _error = 'Enter a valid IP address (e.g. 192.168.1.42)');
      return;
    }
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      setState(() => _error = 'Enter a port between 1 and 65535');
      return;
    }

    final name = _nameCtrl.text.trim();
    Navigator.of(context).pop(
      ServerConfig(
        name: name.isEmpty ? parsedHost.address : name,
        host: parsedHost.address,
        port: parsedPort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: Colors.grey);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        widget.existing == null ? 'Add server' : 'Edit server',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                labelStyle: labelStyle,
                hintText: 'Living room PC',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
            TextField(
              controller: _hostCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'IP address',
                labelStyle: labelStyle,
                hintText: '192.168.1.42',
                hintStyle: TextStyle(color: Colors.grey),
              ),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              controller: _portCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                labelStyle: labelStyle,
                hintText: '7878',
                hintStyle: TextStyle(color: Colors.grey),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
