using System.Net.NetworkInformation;
using System.Net.Sockets;
using HierMic.Protocol;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

public sealed class HierMicService : IHostedService
{
    private readonly AudioPipeline _pipeline;
    private readonly AudioReceiver _receiver;
    private readonly ControlServer _control;
    private readonly MdnsAdvertiser _mdns;
    private readonly ServerConfig _cfg;
    private readonly ILogger<HierMicService> _log;
    private readonly CancellationTokenSource _cts = new();
    private Task _runTask = Task.CompletedTask;

    public HierMicService(
        AudioPipeline pipeline,
        AudioReceiver receiver,
        ControlServer control,
        MdnsAdvertiser mdns,
        ServerConfig cfg,
        ILogger<HierMicService> log)
    {
        _pipeline = pipeline;
        _receiver = receiver;
        _control  = control;
        _mdns     = mdns;
        _cfg      = cfg;
        _log      = log;
    }

    public async Task StartAsync(CancellationToken ct)
    {
        _log.LogInformation("HierMic starting...");
        await _pipeline.StartAsync(ct);
        _mdns.Start();

        _runTask = Task.WhenAll(
            _control.RunAsync(_cts.Token),
            _receiver.RunAsync(_cts.Token)
        );

        LogNetworkAddresses();
        _log.LogInformation("HierMic v{V} ready. Open the app and connect to one of the addresses above",
            Constants.Version);

        _ = UpdateChecker.CheckAsync(_log, _cts.Token);
    }

    private void LogNetworkAddresses()
    {
        var addresses = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up
                     && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork)
            .Select(a => a.Address)
            .ToList();

        if (addresses.Count == 0)
        {
            Console.WriteLine("(no active network interfaces found)");
            return;
        }

        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        foreach (var ip in addresses)
            Console.WriteLine($"  Server address:  {ip}:{_cfg.ControlPort}");
        Console.WriteLine($"  Virtual mic:     {_cfg.PipeSourceName}");
        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    }

    public async Task StopAsync(CancellationToken ct)
    {
        _log.LogInformation("HierMic stopping...");
        await _cts.CancelAsync();

        // Close the FIFO write-end first. If AudioReceiver is mid-write and the kernel
        // FIFO buffer is full (no consumer reading the source), the write blocks forever —
        // closing the fd from here unblocks it immediately with ObjectDisposedException.
        await _pipeline.CloseAsync();

        // Close sockets so any pending ReceiveAsync / AcceptTcpClientAsync unblocks.
        await _receiver.DisposeAsync();
        await _control.DisposeAsync();

        try { await _runTask.WaitAsync(TimeSpan.FromSeconds(3)); }
        catch (Exception)
        {
            // ignored
        }

        _mdns.Dispose();
        await _pipeline.DisposeAsync();
    }
}
