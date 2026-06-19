import 'dart:io';

class ServerInfo {
  final String name;
  final InternetAddress address;
  final int port;

  const ServerInfo({
    required this.name,
    required this.address,
    required this.port,
  });

  String get displayAddress => '${address.address}:$port';

  @override
  bool operator ==(Object other) =>
      other is ServerInfo &&
      address.address == other.address.address &&
      port == other.port;

  @override
  int get hashCode => Object.hash(address.address, port);

  @override
  String toString() => '$name ($displayAddress)';
}
