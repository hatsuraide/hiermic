using HierMic.Server;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Console;

if (args is ["--install"])      { await Installer.InstallAsync();        return; }
if (args is ["--uninstall"])    { await Installer.UninstallAsync();      return; }
if (args is ["--write-config"]) { await ServerConfig.WriteDefaultAsync(); return; }

var config = await ServerConfig.LoadAsync(args);

var host = Host.CreateDefaultBuilder(args)
    .ConfigureLogging(l =>
    {
        l.ClearProviders();
        l.AddConsole(o => o.FormatterName = CleanConsoleFormatter.Name);
        l.AddConsoleFormatter<CleanConsoleFormatter, ConsoleFormatterOptions>();
        l.SetMinimumLevel(LogLevel.Information);
        l.AddFilter("Microsoft", LogLevel.Warning);
        l.AddFilter("System",    LogLevel.Warning);
    })
    .ConfigureServices(s =>
    {
        s.AddSingleton(config);
        s.AddSingleton<AudioPipeline>();
        s.AddSingleton<AudioReceiver>();
        s.AddSingleton<ControlServer>();
        s.AddSingleton<MdnsAdvertiser>();
        s.AddHostedService<HierMicService>();
    })
    .UseConsoleLifetime(o => o.SuppressStatusMessages = true)
    .Build();

await host.RunAsync();
