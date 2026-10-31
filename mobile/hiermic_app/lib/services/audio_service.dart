import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import '../models/server_info.dart';
import 'constants.dart';

class AudioService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  StreamController<Uint8List>? _controller;
  StreamSubscription<Uint8List>? _sub;
  RawDatagramSocket? _socket;
  int _seq = 0;
  final _buf = BytesBuilder(copy: false);
  final _targets = <ServerInfo>[];

  bool get isStreaming => _recorder.isRecording;

  /// Adds or removes destinations while streaming is active.
  void setTargets(Iterable<ServerInfo> servers) {
    _targets
      ..clear()
      ..addAll(servers);
  }

  Future<void> startStreaming(Iterable<ServerInfo> servers) async {
    if (_socket != null) return;
    setTargets(servers);
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    await _recorder.openRecorder();

    _controller = StreamController<Uint8List>();
    _sub = _controller!.stream.listen((data) {
      if (data.isEmpty) return;
      _buf.add(data);

      while (_buf.length >= Constants.bytesPerPacket) {
        final all = _buf.toBytes();
        final pcm = all.sublist(0, Constants.bytesPerPacket);
        _buf.clear();
        if (all.length > Constants.bytesPerPacket) {
          _buf.add(all.sublist(Constants.bytesPerPacket));
        }
        // Audio UDP port is always controlPort + 1 (matches server convention).
        final packet = _buildPacket(_seq++, pcm);
        for (final target in List<ServerInfo>.of(_targets)) {
          _socket?.send(packet, target.address, target.port + 1);
        }
      }
    });

    await _recorder.startRecorder(
      toStream: _controller!.sink,
      codec: Codec.pcm16,
      numChannels: Constants.channels,
      sampleRate: Constants.sampleRate,
    );
  }

  Future<void> stopStreaming() async {
    if (_socket == null && !_recorder.isRecording) return;

    await _recorder.stopRecorder();
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
    _socket?.close();
    _socket = null;
    _buf.clear();
    _targets.clear();
    await _recorder.closeRecorder();
  }

  Uint8List _buildPacket(int seq, Uint8List pcm) {
    final samples = pcm.length ~/ (Constants.channels * 2);
    final header  = ByteData(Constants.packetHeaderSize);
    final ts      = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;

    header.setUint32(0, seq & 0xFFFFFFFF, Endian.little);
    header.setUint32(4, ts, Endian.little);
    header.setUint8(8, Constants.channels);
    header.setUint16(9, samples, Endian.little);

    final out = Uint8List(Constants.packetHeaderSize + pcm.length);
    out.setAll(0, header.buffer.asUint8List());
    out.setAll(Constants.packetHeaderSize, pcm);
    return out;
  }

  Future<void> dispose() => stopStreaming();
}
