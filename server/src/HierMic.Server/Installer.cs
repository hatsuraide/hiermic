using System.Diagnostics;
using System.Runtime.Versioning;

namespace HierMic.Server;

[SupportedOSPlatform("linux")]
internal static class Installer
{
    private static string BinDir  => Path.Combine(Home, ".local", "bin");
    private static string BinPath => Path.Combine(BinDir, "hiermic");

    private static string ServiceDir  => Path.Combine(Home, ".config", "systemd", "user");
    private static string ServicePath => Path.Combine(ServiceDir, "hiermic.service");

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private const string ServiceUnit = """
        [Unit]
        Description=HierMic WiFi Microphone Server
        After=pipewire-pulse.service

        [Service]
        ExecStart=%h/.local/bin/hiermic
        Restart=on-failure
        RestartSec=3

        [Install]
        WantedBy=default.target
        """;

    public static async Task InstallAsync()
    {
        var self = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine current binary path.");

        Directory.CreateDirectory(BinDir);
        File.Copy(self, BinPath, overwrite: true);
        File.SetUnixFileMode(BinPath,
            UnixFileMode.UserRead    | UnixFileMode.UserWrite    | UnixFileMode.UserExecute |
            UnixFileMode.GroupRead   | UnixFileMode.GroupExecute |
            UnixFileMode.OtherRead   | UnixFileMode.OtherExecute);
        Console.WriteLine($"Copied binary to: {BinPath}");

        Directory.CreateDirectory(ServiceDir);
        await File.WriteAllTextAsync(ServicePath, ServiceUnit);
        Console.WriteLine($"Wrote unit: {ServicePath}");

        await Systemctl(["daemon-reload"]);
        await Systemctl(["enable", "--now", "hiermic"]);

        Console.WriteLine();
        Console.WriteLine("Installed and started. Useful commands:");
        Console.WriteLine("  systemctl --user status hiermic");
        Console.WriteLine("  journalctl --user -u hiermic -f");
        Console.WriteLine("  hiermic --uninstall");
    }

    public static async Task UninstallAsync()
    {
        Console.WriteLine("Stopping service...");
        await Systemctl(["stop", "hiermic"], ignoreErrors: true, timeoutSeconds: 10);
        await Systemctl(["disable", "hiermic"], ignoreErrors: true);

        if (File.Exists(ServicePath))
        {
            File.Delete(ServicePath);
            Console.WriteLine($"Removed  {ServicePath}");
        }

        await Systemctl(["daemon-reload"], ignoreErrors: true);

        if (File.Exists(BinPath))
        {
            File.Delete(BinPath);
            Console.WriteLine($"Removed  {BinPath}");
        }

        Console.WriteLine("Uninstalled.");
    }

    private static async Task Systemctl(
        string[] args,
        bool ignoreErrors = false,
        int timeoutSeconds = 15)
    {
        var psi = new ProcessStartInfo("systemctl") { UseShellExecute = false };
        psi.ArgumentList.Add("--user");
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var proc = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start systemctl");

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        try
        {
            await proc.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            try { proc.Kill(); }
            catch
            {
                // ignored
            }

            if (!ignoreErrors)
                throw new InvalidOperationException(
                    $"systemctl --user {string.Join(' ', args)} timed out after {timeoutSeconds}s");
            return;
        }

        if (!ignoreErrors && proc.ExitCode != 0)
            throw new InvalidOperationException(
                $"systemctl --user {string.Join(' ', args)} failed (exit {proc.ExitCode})");
    }
}
