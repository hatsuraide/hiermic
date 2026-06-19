using System.Net;
using System.Net.Sockets;
using HierMic.Protocol;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

public sealed class ControlServer : IAsyncDisposable
{
    private readonly ILogger<ControlServer> _log;
    private readonly ServerConfig _cfg;
    private readonly TcpListener _listener;
    private readonly List<Task> _clientTasks = [];

    public ControlServer(ServerConfig cfg, ILogger<ControlServer> log)
    {
        _cfg      = cfg;
        _log      = log;
        _listener = new TcpListener(IPAddress.Any, cfg.ControlPort);
    }

    public async Task RunAsync(CancellationToken ct)
    {
        _listener.Start();
        _log.LogInformation("TCP control listener on port {Port}", _cfg.ControlPort);

        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                _log.LogWarning("Accept error: {Msg}", ex.Message);
                continue;
            }
            catch (Exception)
            {
                break;
            }

            _log.LogInformation("Client connected: {EP}", client.Client.RemoteEndPoint);
            _clientTasks.Add(HandleClientAsync(client, ct));
        }

        await Task.WhenAll(_clientTasks);
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        using var _ = client;
        await using var stream = client.GetStream();
        using var reader = new StreamReader(stream, leaveOpen: true);
        await using var writer = new StreamWriter(stream, leaveOpen: true);
        writer.AutoFlush = true;

        var ep = client.Client.RemoteEndPoint;

        try
        {
            await writer.WriteLineAsync(ControlMessage.Hello(_cfg.SampleRate, _cfg.Channels).Serialize());

            using var pingCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            var pingTask = PingLoopAsync(writer, pingCts.Token);
            try
            {
                while (!ct.IsCancellationRequested)
                {
                    var line = await reader.ReadLineAsync(ct);
                    if (line is null) break;

                    var msg = ControlMessage.Deserialize(line);
                    if (msg is null) continue;

                    switch (msg.Type)
                    {
                        case ControlMessageType.Hello:
                            _log.LogDebug("Client {EP} hello | v{V}, {Rate}Hz, {Ch}ch",
                                ep, msg.Version, msg.SampleRate, msg.Channels);
                            await writer.WriteLineAsync(ControlMessage.HelloAck().Serialize());
                            break;

                        case ControlMessageType.Start:
                            _log.LogInformation("Client {EP} started streaming", ep);
                            break;

                        case ControlMessageType.Stop:
                            _log.LogInformation("Client {EP} stopped streaming", ep);
                            break;

                        case ControlMessageType.Ping:
                            await writer.WriteLineAsync(ControlMessage.Pong().Serialize());
                            break;

                        case ControlMessageType.Pong:
                            break;

                        default:
                            _log.LogDebug("Unhandled message type: {T}", msg.Type);
                            break;
                    }
                }
            }
            finally
            {
                await pingCts.CancelAsync();
                try { await pingTask; }
                catch
                {
                    // ignored
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            _log.LogWarning("Client {EP} error: {Msg}", ep, ex.Message);
        }
        finally
        {
            _log.LogInformation("Client disconnected: {EP}", ep);
        }
    }

    private static async Task PingLoopAsync(StreamWriter writer, CancellationToken ct)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(10));
        try
        {
            while (await timer.WaitForNextTickAsync(ct))
                await writer.WriteLineAsync(ControlMessage.Ping().Serialize());
        }
        catch (OperationCanceledException) { }
        catch (Exception)
        {
            // ignored
        }
    }

    public ValueTask DisposeAsync()
    {
        _listener.Stop();
        return ValueTask.CompletedTask;
    }
}
