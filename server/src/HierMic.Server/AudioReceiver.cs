using System.Net.Sockets;
using HierMic.Protocol;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

public sealed class AudioReceiver : IAsyncDisposable
{
    private readonly AudioPipeline _pipeline;
    private readonly ILogger<AudioReceiver> _log;
    private readonly UdpClient _udp;
    private readonly int _audioPort;

    private uint _lastSeq;
    private ulong _received;
    private ulong _dropped;

    public AudioReceiver(ServerConfig cfg, AudioPipeline pipeline, ILogger<AudioReceiver> log)
    {
        _pipeline = pipeline;
        _log      = log;
        _udp      = new UdpClient(cfg.AudioPort);
        _audioPort = cfg.AudioPort;
    }

    public async Task RunAsync(CancellationToken ct)
    {
        _log.LogInformation("UDP audio listener on port {Port}", _audioPort);

        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _udp.ReceiveAsync(ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                _log.LogWarning("UDP receive error: {Msg}", ex.Message);
                continue;
            }
            catch (Exception)
            {
                break;
            }

            if (!AudioPacket.TryParse(result.Buffer, out var pkt))
            {
                _log.LogDebug("Malformed audio packet from {EP}, ignoring", result.RemoteEndPoint);
                continue;
            }

            // Simple sequence gap detection (wraps at uint.MaxValue naturally)
            if (_received > 0 && pkt.Sequence != _lastSeq + 1)
                _dropped += pkt.Sequence - _lastSeq - 1;

            _lastSeq = pkt.Sequence;
            _received++;

            await _pipeline.WriteAsync(pkt.PcmData, ct);

            if (_received % 500 == 0)
                _log.LogDebug("Audio stats | received: {R}, dropped: {D}", _received, _dropped);
        }
    }

    public ValueTask DisposeAsync()
    {
        _udp.Dispose();
        return ValueTask.CompletedTask;
    }
}
