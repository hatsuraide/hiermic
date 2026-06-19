using System.Net.Http.Json;
using System.Text.Json.Serialization;
using HierMic.Protocol;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

internal static class UpdateChecker
{
    private const string ApiUrl =
        "https://api.github.com/repos/hatsuraide/hiermic/releases/latest";

    public static async Task CheckAsync(ILogger logger, CancellationToken ct)
    {
        try
        {
            using var http = new HttpClient();
            http.Timeout = TimeSpan.FromSeconds(5);
            http.DefaultRequestHeaders.UserAgent.ParseAdd($"hiermic/{Constants.Version}");

            var release = await http.GetFromJsonAsync(
                ApiUrl,
                UpdateCheckerJsonContext.Default.GitHubRelease,
                ct);

            if (release is null) return;

            var latest = release.TagName.TrimStart('v');
            if (System.Version.TryParse(latest, out var latestVer) &&
                System.Version.TryParse(Constants.Version, out var currentVer) &&
                latestVer > currentVer)
            {
                logger.LogInformation(
                    "Update available: v{Latest} (you have v{Current}) — https://github.com/hatsuraide/hiermic/releases",
                    latest, Constants.Version);
            }
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or OperationCanceledException)
        {
            // Network unavailable or timeout
        }
    }
}

internal sealed class GitHubRelease
{
    [JsonPropertyName("tag_name")]
    public string TagName { get; set; } = "";
}

[JsonSerializable(typeof(GitHubRelease))]
internal partial class UpdateCheckerJsonContext : JsonSerializerContext { }
