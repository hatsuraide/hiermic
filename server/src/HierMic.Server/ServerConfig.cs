using System.Text.Json;
using System.Text.Json.Serialization;
using HierMic.Protocol;

namespace HierMic.Server;

public sealed class ServerConfig
{
    public int    ControlPort    { get; set; } = Constants.ControlPort;
    public int    AudioPort      { get; set; } = Constants.AudioPort;
    public int    SampleRate     { get; set; } = Constants.SampleRate;
    public int    Channels       { get; set; } = Constants.Channels;
    public string PipeSourceName { get; set; } = Constants.PipeSourceName;
    public string PipePath       { get; set; } = Constants.PipePath;

    private static string ConfigPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".config", "hiermic", "config.json");

    public static async Task<ServerConfig> LoadAsync(string[] cliArgs)
    {
        var cfg = new ServerConfig();

        // 1. Config file (~/.config/hiermic/config.json)
        if (File.Exists(ConfigPath))
        {
            try
            {
                var json = await File.ReadAllTextAsync(ConfigPath);
                var fromFile = JsonSerializer.Deserialize(json, ServerConfigJsonContext.Default.ServerConfig);
                if (fromFile is not null) cfg = fromFile;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WRN] Failed to read config file: {ex.Message}");
            }
        }

        // 2. Environment variables  (HIERMIC_CONTROL_PORT, HIERMIC_AUDIO_PORT, …)
        if (Env("HIERMIC_CONTROL_PORT") is { } cp) cfg.ControlPort    = cp;
        if (Env("HIERMIC_AUDIO_PORT")   is { } ap) cfg.AudioPort      = ap;
        if (Env("HIERMIC_SAMPLE_RATE")  is { } sr) cfg.SampleRate     = sr;
        if (Env("HIERMIC_CHANNELS")     is { } ch) cfg.Channels       = ch;
        if (EnvStr("HIERMIC_PIPE_SOURCE") is { } ps) cfg.PipeSourceName = ps;
        if (EnvStr("HIERMIC_PIPE_PATH")   is { } pp) cfg.PipePath       = pp;

        // 3. Command-line args (--control-port=7880, --audio-port=7881, …)
        foreach (var arg in cliArgs)
        {
            if (!arg.StartsWith("--")) continue;
            var eq = arg.IndexOf('=');
            if (eq < 0) continue;
            var key = arg[2..eq].Replace("-", "").ToLowerInvariant();
            var val = arg[(eq + 1)..];
            switch (key)
            {
                case "controlport" when int.TryParse(val, out var v): cfg.ControlPort    = v; break;
                case "audioport"   when int.TryParse(val, out var v): cfg.AudioPort      = v; break;
                case "samplerate"  when int.TryParse(val, out var v): cfg.SampleRate     = v; break;
                case "channels"    when int.TryParse(val, out var v): cfg.Channels       = v; break;
                case "pipesource":                                     cfg.PipeSourceName = val; break;
                case "pipepath":                                       cfg.PipePath       = val; break;
            }
        }

        return cfg;
    }

    // Writes a documented default config so the user has something to edit.
    public static async Task WriteDefaultAsync()
    {
        var dir = Path.GetDirectoryName(ConfigPath)!;
        Directory.CreateDirectory(dir);
        var defaults = new ServerConfig();
        var json = JsonSerializer.Serialize(defaults, ServerConfigJsonContext.Default.ServerConfig);
        await File.WriteAllTextAsync(ConfigPath, json);
        Console.WriteLine($"Default config written to {ConfigPath}");
    }

    private static int? Env(string key) =>
        Environment.GetEnvironmentVariable(key) is { } s && int.TryParse(s, out var v) ? v : null;

    private static string? EnvStr(string key) =>
        Environment.GetEnvironmentVariable(key) is { Length: > 0 } s ? s : null;
}

[JsonSerializable(typeof(ServerConfig))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    WriteIndented = true)]
internal partial class ServerConfigJsonContext : JsonSerializerContext { }
