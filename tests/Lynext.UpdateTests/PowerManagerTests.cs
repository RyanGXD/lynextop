using Lynext;
using System.Globalization;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class PowerManagerTests
{
    [Fact]
    public void ExposesFiveOfficialNamesAndStableInternalIds()
    {
        Assert.Equal(new[] { "Lynext Ultra Performance", "Lynext Gamer", "Lynext Empresarial", "Lynext Lite", "Lynext Economia" },
            OptimizationProfileCatalog.Profiles.Select(profile => profile.Name));
        Assert.Equal(new[] { "gamer-ultra", "gamer", "lite", "business", "economy" },
            OptimizationProfileCatalog.Profiles.Select(profile => profile.Id));
    }

    [Theory]
    [InlineData("gamer-ultra", true)]
    [InlineData("gamer", true)]
    [InlineData("business", false)]
    [InlineData("lite", false)]
    [InlineData("economy", false)]
    public void ProfilesGetCommonValuesAndOnlyGamingGetsFixedCpu(string profileId, bool fixedCpu)
    {
        var settings = PowerManagerService.GetSettingsForProfile(profileId);
        Assert.Equal(new[] { "screen", "sleep", "disk" }.Concat(fixedCpu ? new[] { "cpu-min", "cpu-max" } : Array.Empty<string>()), settings.Select(s => s.Key));
        Assert.Equal((uint)0, settings.Single(s => s.Key == "screen").Ac);
        Assert.Equal((uint)60, settings.Single(s => s.Key == "screen").Dc);
        Assert.Equal((uint)0, settings.Single(s => s.Key == "sleep").Ac);
        Assert.Equal((uint)60, settings.Single(s => s.Key == "sleep").Dc);
        Assert.Equal((uint)0, settings.Single(s => s.Key == "disk").Ac);
        Assert.Equal((uint)0, settings.Single(s => s.Key == "disk").Dc);
        if (fixedCpu)
        {
            Assert.All(settings.Where(s => s.Key.StartsWith("cpu-")), s =>
            {
                Assert.Equal((uint)100, s.Ac);
                Assert.Equal((uint)100, s.Dc);
            });
        }
        else
        {
            Assert.DoesNotContain(settings, s => s.Key.StartsWith("cpu-"));
        }
    }

    [Fact]
    public void SelectingProfilesDoesNotAuthorizeWindowsChanges()
    {
        foreach (var profile in OptimizationProfileCatalog.Profiles)
            Assert.Empty(OptimizationProfileCatalog.GetSelectionOperations(profile.Name));
    }

    [Fact]
    public void UnknownProfileCannotProduceSettings()
    {
        Assert.Empty(PowerManagerService.GetSettingsForProfile("external-command"));
    }

    [Fact]
    public void ActivationCreatesFiveStablePlansConfiguresEachAndLeavesBalancedUntouched()
    {
        var fixture = new PowerManagerFixture();
        try
        {
            var before = fixture.Runner.Schemes[PowerManagerFixture.Balanced].Clone();
            var result = fixture.Service.Activate("gamer-ultra");
            Assert.True(result.Success, result.Message);
            Assert.Equal(6, fixture.Runner.Schemes.Count);
            var snapshot = fixture.Service.ReadSnapshot();
            Assert.Equal(5, snapshot.Profiles.Count(p => p.Exists));
            Assert.Equal("Lynext Ultra Performance", snapshot.Profiles.Single(p => p.IsActive).Name);
            Assert.Equal(snapshot.Profiles.Single(p => p.Id == "gamer-ultra").Guid, fixture.Runner.Active);
            Assert.Equal(before.Values.OrderBy(item => item.Key), fixture.Runner.Schemes[PowerManagerFixture.Balanced].Values.OrderBy(item => item.Key));
            foreach (var profile in snapshot.Profiles)
            {
                var scheme = fixture.Runner.Schemes[profile.Guid!];
                Assert.Equal(new PowerSettingValues(0, 60), scheme.Values[PowerManagerFixture.Key("screen")]);
                Assert.Equal(new PowerSettingValues(0, 60), scheme.Values[PowerManagerFixture.Key("sleep")]);
                Assert.Equal(new PowerSettingValues(0, 0), scheme.Values[PowerManagerFixture.Key("disk")]);
                if (profile.Id is "gamer" or "gamer-ultra")
                {
                    Assert.Equal(new PowerSettingValues(100, 100), scheme.Values[PowerManagerFixture.Key("cpu-min")]);
                    Assert.Equal(new PowerSettingValues(100, 100), scheme.Values[PowerManagerFixture.Key("cpu-max")]);
                }
                else
                {
                    Assert.Equal(before.Values[PowerManagerFixture.Key("cpu-min")], scheme.Values[PowerManagerFixture.Key("cpu-min")]);
                    Assert.Equal(before.Values[PowerManagerFixture.Key("cpu-max")], scheme.Values[PowerManagerFixture.Key("cpu-max")]);
                }
            }
            Assert.True(fixture.Service.Activate("gamer").Success);
            Assert.Equal(6, fixture.Runner.Schemes.Count);
            Assert.True(fixture.Service.RestorePrevious().Success);
            Assert.Equal(PowerManagerFixture.Balanced, fixture.Runner.Active);
            Assert.Equal(6, fixture.Runner.Schemes.Count);
        }
        finally { fixture.Dispose(); }
    }

    [Fact]
    public void ExternalNameCollisionStopsCreationWithoutChangingExistingSchemes()
    {
        var fixture = new PowerManagerFixture();
        try
        {
            fixture.Runner.AddExternal("00000000-0000-0000-0000-000000000099", "Lynext Gamer");
            var result = fixture.Service.Activate("gamer");
            Assert.False(result.Success);
            Assert.Equal(2, fixture.Runner.Schemes.Count);
            Assert.Equal(PowerManagerFixture.Balanced, fixture.Runner.Active);
        }
        finally { fixture.Dispose(); }
    }

    [Fact]
    public void UserSettingConflictPreventsFurtherWritesAndPreservesActiveScheme()
    {
        var fixture = new PowerManagerFixture();
        try
        {
            Assert.True(fixture.Service.Activate("gamer").Success);
            var economy = fixture.Service.ReadSnapshot().Profiles.Single(p => p.Id == "economy");
            fixture.Runner.Set(economy.Guid!, "screen", new PowerSettingValues(15, 20));
            var writesBefore = fixture.Runner.WriteCount;
            var result = fixture.Service.Activate("gamer-ultra");
            Assert.False(result.Success);
            Assert.Contains("Conflito", result.Message);
            Assert.Equal(writesBefore, fixture.Runner.WriteCount);
            Assert.Equal(fixture.Service.ReadSnapshot().Profiles.Single(p => p.Id == "gamer").Guid, fixture.Runner.Active);
        }
        finally { fixture.Dispose(); }
    }

    [Fact]
    public void FailedPowercfgWriteDoesNotActivateProfile()
    {
        var fixture = new PowerManagerFixture();
        try
        {
            fixture.Runner.FailNextDcWrite = true;
            var result = fixture.Service.Activate("economy");
            Assert.False(result.Success);
            Assert.Equal(PowerManagerFixture.Balanced, fixture.Runner.Active);
        }
        finally { fixture.Dispose(); }
    }

    [Fact]
    public void ManagedPowerPolicyFailsClosedBeforeCreatingSchemes()
    {
        var fixture = new PowerManagerFixture();
        try
        {
            fixture.Runner.PowerManaged = true;
            var result = fixture.Service.Activate("business");
            Assert.False(result.Success);
            Assert.Equal(1, fixture.Runner.Schemes.Count);
            Assert.Equal(PowerManagerFixture.Balanced, fixture.Runner.Active);
        }
        finally { fixture.Dispose(); }
    }

    private sealed class PowerManagerFixture : IDisposable
    {
        public const string Balanced = "381b4222-f694-41f0-9685-ff5bb260df2e";
        private readonly string _directory = Path.Combine(Path.GetTempPath(), "lynext-power-tests", Guid.NewGuid().ToString("N"));
        public FakePowerRunner Runner { get; } = new();
        public PowerManagerService Service { get; }
        public PowerManagerFixture() => Service = new PowerManagerService(Runner, Runner, _directory, Runner);
        public void Dispose() { if (Directory.Exists(_directory)) Directory.Delete(_directory, true); }
        public static string Key(string name)
        {
            var setting = PowerManagerService.GetSettingsForProfile(name.StartsWith("cpu-", StringComparison.Ordinal) ? "gamer" : "business").Single(s => s.Key == name);
            return setting.SubgroupGuid + "/" + setting.SettingGuid;
        }
    }

    private sealed class FakePowerRunner : IPowerCommandRunner, IPowerSchemeDescriptionReader, IPowerPolicyDetector
    {
        public sealed class FakeScheme(string name, string description, Dictionary<string, PowerSettingValues> values)
        {
            public string Name { get; set; } = name;
            public string Description { get; set; } = description;
            public Dictionary<string, PowerSettingValues> Values { get; } = values;
            public FakeScheme Clone() => new(Name, Description, new(Values));
        }
        public Dictionary<string, FakeScheme> Schemes { get; } = new(StringComparer.OrdinalIgnoreCase);
        public string Active { get; set; } = PowerManagerFixture.Balanced;
        public int WriteCount { get; private set; }
        public bool FailNextDcWrite { get; set; }
        public bool PowerManaged { get; set; }
        private int _nextGuid = 1;
        public FakePowerRunner()
        {
            var values = new Dictionary<string, PowerSettingValues>();
            foreach (var profile in new[] { "gamer-ultra", "gamer", "business", "lite", "economy" })
                foreach (var setting in PowerManagerService.GetSettingsForProfile(profile))
                    values[Key(setting.SubgroupGuid, setting.SettingGuid)] = setting.Key.StartsWith("cpu-") ? new(5, 8) : new(10, 15);
            Schemes[PowerManagerFixture.Balanced] = new("Balanced", "Windows original", values);
        }
        public void AddExternal(string guid, string name) => Schemes.Add(guid, new(name, "external", new()));
        public void Set(string guid, string key, PowerSettingValues values) => Schemes[guid].Values[key] = values;
        public string ReadDescription(string schemeGuid) => Schemes.TryGetValue(schemeGuid, out var scheme) ? scheme.Description : string.Empty;
        public bool IsPowerManaged() => PowerManaged;
        public PowerCfgCommandResult Run(params string[] a)
        {
            switch (a[0].ToLowerInvariant())
            {
                case "/list": return new(0, string.Join(Environment.NewLine, Schemes.Select(item => $"Power Scheme GUID: {{{item.Key}}} ({item.Value.Name}){(Active == item.Key ? " *" : "")}")));
                case "/getactivescheme": return new(0, $"Power Scheme GUID: {{{Active}}} ({Schemes[Active].Name})");
                case "/a": return new(0, "Standby (S3)");
                case "/duplicatescheme":
                    var guid = $"00000000-0000-0000-0000-{_nextGuid++:D12}";
                    Schemes.Add(guid, Schemes[a[1]].Clone());
                    return new(0, $"Power Scheme GUID: {{{guid}}} ({Schemes[guid].Name})");
                case "/changename": Schemes[a[1]].Name = a[2]; Schemes[a[1]].Description = a[3]; return new(0, "");
                case "/query":
                    var queried = Schemes[a[1]].Values[Key(a[2], a[3])];
                    return new(0, $"Current AC Power Setting Index: 0x{queried.Ac:X8}\r\nCurrent DC Power Setting Index: 0x{queried.Dc:X8}");
                case "/setacvalueindex":
                    WriteCount++;
                    var oldAc = Schemes[a[1]].Values[Key(a[2], a[3])];
                    Schemes[a[1]].Values[Key(a[2], a[3])] = oldAc with { Ac = uint.Parse(a[4], CultureInfo.InvariantCulture) };
                    return new(0, "");
                case "/setdcvalueindex":
                    if (FailNextDcWrite) { FailNextDcWrite = false; return new(5, "", "Access denied"); }
                    WriteCount++;
                    var oldDc = Schemes[a[1]].Values[Key(a[2], a[3])];
                    Schemes[a[1]].Values[Key(a[2], a[3])] = oldDc with { Dc = uint.Parse(a[4], CultureInfo.InvariantCulture) };
                    return new(0, "");
                case "/setactive": Active = a[1]; return new(0, "");
                default: return new(87, "", "Unsupported command");
            }
        }
        private static string Key(string subgroup, string setting) => subgroup + "/" + setting;
    }
}

