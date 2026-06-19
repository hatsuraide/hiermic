using System.Buffers.Binary;

namespace HierMic.Protocol;

// Wire format: seq(4) | timestamp(4) | channels(1) | sampleCount(2) | pcm(...)
public readonly struct AudioPacket
{
    public uint Sequence { get; init; }
    public uint Timestamp { get; init; }
    public byte Channels { get; init; }
    public ushort SampleCount { get; init; }
    public ReadOnlyMemory<byte> PcmData { get; init; }

    public int PcmBytes => Channels * SampleCount * 2;

    public static bool TryParse(ReadOnlySpan<byte> buf, out AudioPacket packet)
    {
        packet = default;
        if (buf.Length < Constants.AudioPacketHeaderSize)
            return false;

        var seq = BinaryPrimitives.ReadUInt32LittleEndian(buf);
        var ts = BinaryPrimitives.ReadUInt32LittleEndian(buf[4..]);
        var channels = buf[8];
        var samples = BinaryPrimitives.ReadUInt16LittleEndian(buf[9..]);
        var expected = Constants.AudioPacketHeaderSize + channels * samples * 2;

        if (buf.Length < expected)
            return false;

        packet = new AudioPacket
        {
            Sequence = seq,
            Timestamp = ts,
            Channels = channels,
            SampleCount = samples,
            PcmData = buf[Constants.AudioPacketHeaderSize..expected].ToArray(),
        };
        return true;
    }

    public static byte[] Encode(uint seq, uint ts, byte channels, ReadOnlySpan<byte> pcm)
    {
        ushort samples = (ushort)(pcm.Length / (channels * 2));
        var buf = new byte[Constants.AudioPacketHeaderSize + pcm.Length];
        
        BinaryPrimitives.WriteUInt32LittleEndian(buf, seq);
        BinaryPrimitives.WriteUInt32LittleEndian(buf.AsSpan(4), ts);
        
        buf[8] = channels;
        BinaryPrimitives.WriteUInt16LittleEndian(buf.AsSpan(9), samples);
        pcm.CopyTo(buf.AsSpan(Constants.AudioPacketHeaderSize));
        
        return buf;
    }
}
