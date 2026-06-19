using HierMic.Protocol;
using Makaretu.Dns;
using Microsoft.Extensions.Logging;

namespace HierMic.Server;

public sealed class MdnsAdvertiser : IDisposable
{
    private readonly ILogger<MdnsAdvertiser> _log;
    private readonly ServiceDiscovery _sd;
    private ServiceProfile? _profile;

    private readonly ServerConfig _cfg;

    public MdnsAdvertiser(ServerConfig cfg, ILogger<MdnsAdvertiser> log)
    {
        _cfg = cfg;
        _log = log;
        _sd  = new ServiceDiscovery();
    }

    public void Start()
    {
        _profile = new ServiceProfile(
            Constants.MdnsServiceName,
            Constants.MdnsServiceType,
            (ushort)_cfg.ControlPort
        );

        _sd.Advertise(_profile);
        _log.LogInformation("mDNS: advertising {Name}.{Type} on port {Port}",
            Constants.MdnsServiceName, Constants.MdnsServiceType, _cfg.ControlPort);
    }

    public void Dispose()
    {
        try
        {
            if (_profile is not null)
            {
                _sd.Unadvertise(_profile);
            }
        }
        catch (Exception ex)
        {
            _log.LogWarning("mDNS unadvertise failed: {Msg}", ex.Message);
        }
        finally
        {
            _sd.Dispose();
        }
    }
}
