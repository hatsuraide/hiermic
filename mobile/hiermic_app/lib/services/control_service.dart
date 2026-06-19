import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/server_info.dart';
import 'constants.dart';

enum ConnectionState { disconnected, connecting, connected }

typedef MessageCallback = void Function(Map<String, dynamic> msg);

class ControlService {
  Socket? _socket;
  StreamSubscription? _sub;

  ConnectionState state = ConnectionState.disconnected;
  MessageCallback? onMessage;
  VoidCallback? onDisconnected;

  Future<void> connect(ServerInfo server) async {
    state   = ConnectionState.connecting;
    _socket = await Socket.connect(
      server.address,
      Constants.controlPort,
      timeout: const Duration(seconds: 5),
    );

    _sub = _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final msg = jsonDecode(line) as Map<String, dynamic>;
              _handleMessage(msg);
            } catch (_) {}
          },
          onDone: _onDone,
          onError: (_) => _onDone(),
        );

    state = ConnectionState.connected;
    _send({'type': 'Hello', 'version': 1,
           'sampleRate': Constants.sampleRate, 'channels': Constants.channels,
           'format': 'PCM16LE'});
  }

  void sendStart() => _send({'type': 'Start'});
  void sendStop()  => _send({'type': 'Stop'});

  void _send(Map<String, dynamic> msg) {
    if (_socket == null) return;
    _socket!.writeln(jsonEncode(msg));
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? '';
    if (type == 'Ping') {
      _send({'type': 'Pong'});
      return;
    }
    onMessage?.call(msg);
  }

  void _onDone() {
    state = ConnectionState.disconnected;
    onDisconnected?.call();
  }

  Future<void> disconnect() async {
    sendStop();
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    state   = ConnectionState.disconnected;
  }
}

typedef VoidCallback = void Function();
