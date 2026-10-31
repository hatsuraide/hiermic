import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';
import 'constants.dart';

/// Persists the list of saved servers.
class SettingsService {
  static const _keyConfigs = 'server_configs';

  // Legacy single-server keys (written by older app versions).
  static const _legacyKeyName    = 'last_server_name';
  static const _legacyKeyAddress = 'last_server_address';
  static const _legacyKeyPort    = 'last_server_port';

  Future<List<ServerConfig>> loadServerConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configs = _decode(prefs.getString(_keyConfigs));

    if (configs.isNotEmpty) return configs;

    // Migrate a previously saved single server into the new list.
    final legacy = _loadLegacyServer(prefs);
    if (legacy == null) return [];

    final migrated = [legacy];
    await saveServerConfigs(migrated);
    await prefs.remove(_legacyKeyName);
    await prefs.remove(_legacyKeyAddress);
    await prefs.remove(_legacyKeyPort);
    return migrated;
  }

  Future<void> saveServerConfigs(List<ServerConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyConfigs,
      jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
  }

  static List<ServerConfig> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((json) => ServerConfig.tryFromJson(Map<String, dynamic>.from(json)))
          .whereType<ServerConfig>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static ServerConfig? _loadLegacyServer(SharedPreferences prefs) {
    final address = prefs.getString(_legacyKeyAddress);
    if (address == null || address.isEmpty) return null;

    final parsed = InternetAddress.tryParse(address);
    if (parsed == null) return null;

    return ServerConfig(
      name: prefs.getString(_legacyKeyName) ?? parsed.address,
      host: parsed.address,
      port: prefs.getInt(_legacyKeyPort) ?? Constants.controlPort,
    );
  }
}
