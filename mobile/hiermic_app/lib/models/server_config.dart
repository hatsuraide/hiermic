import 'dart:io';
import '../services/constants.dart';
import 'server_info.dart';

class ServerConfig {
  final String name;
  final String host;
  final int port;

  const ServerConfig({
    required this.name,
    required this.host,
    required this.port,
  });

  /// Stable identity for a config: host + port.
  String get id => '$host:$port';

  ServerInfo toServerInfo() => ServerInfo(
        name: name,
        address: InternetAddress(host),
        port: port,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
      };

  /// Returns null when the stored entry is invalid or has no usable host.
  static ServerConfig? tryFromJson(Map<String, dynamic> json) {
    final parsed = InternetAddress.tryParse((json['host'] as String? ?? '').trim());
    if (parsed == null) return null;

    final name = (json['name'] as String? ?? '').trim();
    return ServerConfig(
      name: name.isEmpty ? parsed.address : name,
      host: parsed.address,
      port: (json['port'] as num?)?.toInt() ?? Constants.controlPort,
    );
  }
}
