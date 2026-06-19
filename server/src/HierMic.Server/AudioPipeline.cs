using System.Diagnostics;
using HierMic.Protocol;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

/// <summary>
/// Creates a PipeWire virtual microphone via PulseAudio compat layer:
///
///   mkfifo /tmp/hiermic.pipe
///   pactl load-module module-pipe-source source_name=hiermic file=/tmp/hiermic.pipe
///
/// module-pipe-source opens the FIFO with O_RDONLY|O_NONBLOCK (non-blocking),
/// so it doesn't wait for a writer. Our subsequent O_WRONLY open returns
/// immediately because the read side is already held open by the module.
/// The source "hiermic" appears as a real microphone in pavucontrol, OBS, etc.
/// </summary>
public sealed class AudioPipeline : IAsyncDisposable
{
    private readonly ILogger<AudioPipeline> _log;
    private readonly ServerConfig _cfg;
    private FileStream? _pipe;
    private uint _moduleIndex;
    private bool _loaded;

    public AudioPipeline(ServerConfig cfg, ILogger<AudioPipeline> log)
    {
        _cfg = cfg;
        _log = log;
    }

    public async Task StartAsync(CancellationToken ct)
    {
        await UnloadAsync(ct);

        // FIFO
        if (File.Exists(_cfg.PipePath))
            File.Delete(_cfg.PipePath);

        await RunCheckedAsync("mkfifo", [_cfg.PipePath], ct);
        _log.LogDebug("FIFO created at {Path}", _cfg.PipePath);

        // module-pipe-source
        // pactl is synchronous: it waits until the module is fully loaded.
        // The module opens the FIFO with O_RDONLY|O_NONBLOCK during init,
        // so after pactl returns the read side is already open.
        var idx = await RunPactlAsync(
            $"load-module module-pipe-source " +
            $"source_name={_cfg.PipeSourceName} " +
            $"format=s16le " +
            $"rate={_cfg.SampleRate} " +
            $"channels={_cfg.Channels} " +
            $"file={_cfg.PipePath} " +
            $"source_properties=device.description=HierMic",
            ct);

        if (!uint.TryParse(idx.Trim(), out _moduleIndex))
            throw new InvalidOperationException(
                $"pactl load-module returned unexpected output: '{idx.Trim()}'\n" +
                "Ensure pipewire-pulse is running:\n" +
                "  systemctl --user start pipewire-pulse");

        _loaded = true;
        _log.LogInformation("Loaded module-pipe-source (module index {Idx})", _moduleIndex);

        // Open write end
        // The module holds the read end open (O_NONBLOCK), so our O_WRONLY open
        // should return immediately. Task.Run keeps any brief block off the
        // async thread; 5 s timeout catches a module that failed silently.
        using var openCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        openCts.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            _pipe = await Task.Run(
                () => new FileStream(_cfg.PipePath, FileMode.Open, FileAccess.Write,
                                     FileShare.Read, bufferSize: 4096, useAsync: true),
                openCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new InvalidOperationException(
                $"Timed out opening {_cfg.PipePath} — " +
                "did module-pipe-source fail to open the FIFO? Check: pactl list sources short");
        }

        _log.LogInformation(
            "Virtual mic '{Name}' is live — select it as your microphone in apps",
            _cfg.PipeSourceName);
    }

    public async ValueTask WriteAsync(ReadOnlyMemory<byte> pcm, CancellationToken ct)
    {
        if (_pipe is null) return;
        try
        {
            await _pipe.WriteAsync(pcm, ct);
        }
        catch (Exception ex) when (ex is IOException or ObjectDisposedException)
        {
            // Suppress noise during intentional shutdown — caller's ct is already cancelled.
            if (!ct.IsCancellationRequested)
                _log.LogWarning("Pipe write failed: {Msg}", ex.Message);
        }
    }

    // Closes the write-end of the FIFO without touching the module.
    // Called during shutdown so any in-progress blocked write unblocks immediately.
    public async ValueTask CloseAsync()
    {
        if (_pipe is null) return;
        await _pipe.DisposeAsync();
        _pipe = null;
    }

    public async ValueTask DisposeAsync()
    {
        if (_pipe is not null)
        {
            await _pipe.DisposeAsync();
            _pipe = null;
        }

        if (File.Exists(_cfg.PipePath))
            File.Delete(_cfg.PipePath);

        await UnloadAsync(CancellationToken.None);
    }

    // Helpers

    private async Task UnloadAsync(CancellationToken ct)
    {
        // Unload the module we own (tracked by index)
        if (_loaded && _moduleIndex > 0)
        {
            try
            {
                await RunPactlAsync($"unload-module {_moduleIndex}", ct);
                _log.LogDebug("Unloaded module-pipe-source (index {Idx})", _moduleIndex);
            }
            catch (Exception ex)
            {
                _log.LogWarning("Failed to unload module {Idx}: {Msg}", _moduleIndex, ex.Message);
            }
            finally
            {
                _loaded      = false;
                _moduleIndex = 0;
            }
        }

        // Also sweep for any stale hiermic sources left by previous crashed runs.
        // `pactl list sources short` lines: index \t name \t driver \t ...
        await SweepStaleSourcesAsync(ct);
    }

    private async Task SweepStaleSourcesAsync(CancellationToken ct)
    {
        // `pactl list modules short` lines: moduleIndex \t moduleName \t args \t nUsed
        // Find module-pipe-source rows whose args contain our source_name and unload them.
        try
        {
            var output = await RunPactlAsync("list modules short", ct);
            foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var cols = line.Split('\t');
                if (cols.Length < 3) continue;
                if (!cols[1].Trim().Equals("module-pipe-source", StringComparison.Ordinal)) continue;
                if (!cols[2].Contains($"source_name={_cfg.PipeSourceName}")) continue;
                if (!uint.TryParse(cols[0].Trim(), out var staleModule)) continue;

                _log.LogInformation("Removing stale module-pipe-source (module index {Idx})", staleModule);
                try { await RunPactlAsync($"unload-module {staleModule}", ct); } catch { /* best-effort */ }
            }
        }
        catch (Exception ex)
        {
            _log.LogDebug("Stale module sweep failed: {Msg}", ex.Message);
        }
    }

    private static async Task<string> RunPactlAsync(string args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo("pactl", args)
        {
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
        };

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start pactl");

        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (proc.ExitCode != 0)
            throw new InvalidOperationException(
                $"pactl {args.Split(' ')[0]} failed (exit {proc.ExitCode}): {stderr.Trim()}");

        return stdout;
    }

    private static async Task RunCheckedAsync(string exe, string[] args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(exe)
        {
            RedirectStandardError = true,
            UseShellExecute       = false,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start {exe}");

        await proc.WaitForExitAsync(ct);

        if (proc.ExitCode != 0)
        {
            var err = await proc.StandardError.ReadToEndAsync(ct);
            throw new InvalidOperationException($"{exe} failed: {err.Trim()}");
        }
    }
}
