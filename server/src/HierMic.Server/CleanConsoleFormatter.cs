using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Logging.Console;

namespace HierMic.Server;

internal sealed class CleanConsoleFormatter() : ConsoleFormatter(Name)
{
    public new const string Name = "clean";

    public override void Write<TState>(
        in LogEntry<TState> logEntry,
        IExternalScopeProvider? scopeProvider,
        TextWriter textWriter)
    {
        var message = logEntry.Formatter(logEntry.State, logEntry.Exception);
        if (message.Length == 0 && logEntry.Exception is null) return;

        var level = logEntry.LogLevel switch
        {
            LogLevel.Trace => "TRC",
            LogLevel.Debug => "DBG",
            LogLevel.Information => "INF",
            LogLevel.Warning => "WRN",
            LogLevel.Error => "ERR",
            LogLevel.Critical => "CRT",
            _ => "???"
        };

        textWriter.WriteLine($"{DateTime.Now:HH:mm:ss} [{level}] {message}");

        if (logEntry.Exception is { } ex)
            textWriter.WriteLine(ex);
    }
}
