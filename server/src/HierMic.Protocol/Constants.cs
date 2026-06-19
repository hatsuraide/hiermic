namespace HierMic.Protocol;

public static class Constants
{
    public const string Version = "1.0.0";

    public const int ControlPort = 7878;
    public const int AudioPort   = 7879;

    public const int SampleRate = 48000;
    public const int Channels   = 1;
    public const string SampleFormat = "PCM16LE";

    public const string MdnsServiceType = "_hiermic._tcp";
    public const string MdnsServiceName = "HierMic";

    public const string PipeSourceName = "hiermic";
    public const string PipePath       = "/tmp/hiermic.pipe";

    public const int AudioPacketHeaderSize = 11; // seq(4) + ts(4) + ch(1) + samples(2)
    public const int JitterBufferMs = 40;
}
