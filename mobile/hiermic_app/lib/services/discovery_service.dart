import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/server_info.dart';
import 'constants.dart';

class DiscoveryService {
  final _controller = StreamController<List<ServerInfo>>.broadcast();
  final _servers    = <ServerInfo>{};
  MDnsClient? _client;

  Stream<List<ServerInfo>> get servers => _controller.stream;
  List<ServerInfo> get currentServers => _servers.toList();

  Future<void> start() async {
    _client = MDnsClient();
    await _client!.start();

    _client!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(Constants.mdnsServiceType),
    ).listen((PtrResourceRecord ptr) {
      _client!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      ).listen((SrvResourceRecord srv) {
        _client!.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        ).listen((IPAddressResourceRecord addr) {
          final server = ServerInfo(
            name:    ptr.domainName.split('.').first,
            address: addr.address,
            port:    srv.port,
          );
          if (_servers.add(server)) {
            _controller.add(_servers.toList());
          }
        });
      });
    });
  }

  void stop() {
    _client?.stop();
    _client = null;
    _servers.clear();
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
