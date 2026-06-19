using System.Text.Json;
using System.Text.Json.Serialization;

namespace HierMic.Protocol;

public enum ControlMessageType
{
    Hello,
    HelloAck,
    Start,
    Stop,
    Ping,
    Pong,
    Error,
}

public class ControlMessage
{
    [JsonConverter(typeof(JsonStringEnumConverter<ControlMessageType>))]
    public ControlMessageType Type { get; set; }

    public int? Version { get; set; }
    public int? SampleRate { get; set; }
    public int? Channels { get; set; }
    public string? Format { get; set; }
    public string? Message { get; set; }

    public string Serialize() =>
        JsonSerializer.Serialize(this, ControlMessageJsonContext.Default.ControlMessage);

    public static ControlMessage? Deserialize(string json) =>
        JsonSerializer.Deserialize(json, ControlMessageJsonContext.Default.ControlMessage);

    public static ControlMessage Hello(
        int sampleRate = Constants.SampleRate,
        int channels   = Constants.Channels) => new()
    {
        Type       = ControlMessageType.Hello,
        Version    = 1,
        SampleRate = sampleRate,
        Channels   = channels,
        Format     = Constants.SampleFormat,
    };

    public static ControlMessage HelloAck() => new() { Type = ControlMessageType.HelloAck };
    public static ControlMessage Start() => new() { Type = ControlMessageType.Start };
    public static ControlMessage Stop() => new() { Type = ControlMessageType.Stop };
    public static ControlMessage Ping() => new() { Type = ControlMessageType.Ping };
    public static ControlMessage Pong() => new() { Type = ControlMessageType.Pong };
    public static ControlMessage Error(string msg) => new() { Type = ControlMessageType.Error, Message = msg };
}

[JsonSerializable(typeof(ControlMessage))]
[JsonSourceGenerationOptions(
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNameCaseInsensitive = true,
    UseStringEnumConverter = true)]
internal partial class ControlMessageJsonContext : JsonSerializerContext { }
