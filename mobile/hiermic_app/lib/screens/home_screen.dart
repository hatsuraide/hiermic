import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/server_info.dart';
import '../services/audio_service.dart';
import '../services/constants.dart';
import '../services/control_service.dart';
import '../services/discovery_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _discovery = DiscoveryService();
  final _audio     = AudioService();
  final _control   = ControlService();

  List<ServerInfo> _servers = [];
  ServerInfo?      _connected;
  bool             _streaming = false;
  String           _status    = 'Scanning for servers...';

  final _manualIpCtrl   = TextEditingController();
  final _manualPortCtrl = TextEditingController(text: '${Constants.controlPort}');

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _startDiscovery();

    _control.onDisconnected = () => setState(() {
      _connected  = null;
      _streaming  = false;
      _status     = 'Disconnected';
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    if (Platform.isAndroid) await Permission.nearbyWifiDevices.request();
  }

  Future<void> _startDiscovery() async {
    await _discovery.start();
    _discovery.servers.listen((servers) {
      setState(() => _servers = servers);
    });
  }

  Future<void> _connect(ServerInfo server) async {
    setState(() => _status = 'Connecting to ${server.name}...');
    try {
      await _control.connect(server);
      setState(() {
        _connected = server;
        _status    = 'Connected to ${server.name}';
      });
    } catch (e) {
      setState(() => _status = 'Connection failed: $e');
    }
  }

  Future<void> _connectManual() async {
    final ip   = _manualIpCtrl.text.trim();
    if (ip.isEmpty) return;
    final port = int.tryParse(_manualPortCtrl.text.trim()) ?? Constants.controlPort;

    final server = ServerInfo(
      name:    ip,
      address: InternetAddress(ip),
      port:    port,
    );
    await _connect(server);
  }

  Future<void> _toggleStreaming() async {
    if (_connected == null) return;

    if (!_streaming) {
      await _audio.startStreaming(_connected!);
      _control.sendStart();
      setState(() {
        _streaming = true;
        _status    = 'Streaming to ${_connected!.name}';
      });
    } else {
      await _audio.stopStreaming();
      _control.sendStop();
      setState(() {
        _streaming = false;
        _status    = 'Connected to ${_connected!.name}';
      });
    }
  }

  Future<void> _disconnect() async {
    if (_streaming) await _audio.stopStreaming();
    await _control.disconnect();
    setState(() {
      _connected = null;
      _streaming = false;
      _status    = 'Disconnected';
    });
  }

  @override
  Widget build(BuildContext context) {
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(status: _status, streaming: _streaming),
            const SizedBox(height: 16),
            if (_connected == null) ...[
              _ManualConnectCard(
                ipController:   _manualIpCtrl,
                portController: _manualPortCtrl,
                onConnect: _connectManual,
              ),
              const SizedBox(height: 16),
              _ServerList(
                servers: _servers,
                onTap: _connect,
              ),
            ] else ...[
              _StreamButton(
                streaming: _streaming,
                onTap: _toggleStreaming,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _discovery.dispose();
    _audio.dispose();
    _control.disconnect();
    _manualIpCtrl.dispose();
    _manualPortCtrl.dispose();
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

class _ManualConnectCard extends StatelessWidget {
  final TextEditingController ipController;
  final TextEditingController portController;
  final VoidCallback onConnect;
  const _ManualConnectCard({
    required this.ipController,
    required this.portController,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ipController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '192.168.x.x',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => onConnect(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: portController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '7878',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
              keyboardType: TextInputType.number,
              onSubmitted: (_) => onConnect(),
            ),
          ),
          TextButton(onPressed: onConnect, child: const Text('Connect')),
        ],
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  final List<ServerInfo> servers;
  final void Function(ServerInfo) onTap;
  const _ServerList({required this.servers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No servers found on this network.\nMake sure HierMic Server is running.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.separated(
        itemCount: servers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = servers[i];
          return ListTile(
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: const Icon(Icons.computer, color: Colors.blueAccent),
            title: Text(s.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(s.displayAddress, style: const TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => onTap(s),
          );
        },
      ),
    );
  }
}

class _StreamButton extends StatelessWidget {
  final bool streaming;
  final VoidCallback onTap;
  const _StreamButton({required this.streaming, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
                streaming ? 'TAP TO STOP' : 'TAP TO STREAM',
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
