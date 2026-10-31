import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_info.dart';
import 'constants.dart';

class SavedServer {
  final String name;
  final String address;
  final int port;

  const SavedServer({
    required this.name,
    required this.address,
    required this.port,
  });
}

/// Persists the last successfully used server so the app can pre-fill the
/// address on the next launch.
class SettingsService {
  static const _keyName    = 'last_server_name';
  static const _keyAddress = 'last_server_address';
  static const _keyPort    = 'last_server_port';

  Future<SavedServer?> loadLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_keyAddress);
    if (address == null || address.isEmpty) return null;

    return SavedServer(
      name:    prefs.getString(_keyName) ?? address,
      address: address,
      port:    prefs.getInt(_keyPort) ?? Constants.controlPort,
    );
  }

  Future<void> saveLastServer(ServerInfo server) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, server.name);
    await prefs.setString(_keyAddress, server.address.address);
    await prefs.setInt(_keyPort, server.port);
  }
}
