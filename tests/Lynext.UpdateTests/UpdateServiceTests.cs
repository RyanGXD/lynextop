using System.Net;
using System.Text;
using Lynext;
using Xunit;

namespace Lynext.UpdateTests;

public sealed class UpdateServiceTests
{
    private static readonly string Hash = new('b', 64);
    private static HttpClient Client(HttpStatusCode status, string body = "", bool rateLimited = false)
    {
        var handler = new StubHandler(_ =>
        {
            var response = new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            };
            if (rateLimited) response.Headers.TryAddWithoutValidation("X-RateLimit-Remaining", "0");
            return response;
        });
        return new HttpClient(handler);
    }

    private static string Release(string tag, string? digest = null, bool prerelease = false) => $$"""
        {
          "draft": false,
          "prerelease": {{prerelease.ToString().ToLowerInvariant()}},
          "tag_name": "{{tag}}",
          "body": "test notes",
          "published_at": "2026-10-21T00:00:00Z",
          "html_url": "https://github.com/RyanGXD/lynextop/releases/tag/{{tag}}",
          "assets": [{
            "name": "Lynext-Setup-{{tag.TrimStart('v')}}-x64.exe",
            "browser_download_url": "https://github.com/RyanGXD/lynextop/releases/download/{{tag}}/Lynext-Setup-{{tag.TrimStart('v')}}-x64.exe",
            "size": 1234,
            "digest": "{{digest ?? "sha256:" + Hash}}"
          }]
        }
        """;

    [Fact]
    public async Task NotFoundMeansNoStableRelease()
    {
        var result = await UpdateService.CheckLatestAsync(Client(HttpStatusCode.NotFound), new LynextReleaseVersion(new Version(0, 1, 0), true));
        Assert.Null(result);
    }

    [Fact]
    public async Task StableReleaseIsOfferedAndHasIntegritySource()
    {
        var result = await UpdateService.CheckLatestAsync(Client(HttpStatusCode.OK, Release("v0.1.0")), new LynextReleaseVersion(new Version(0, 1, 0), true));
        Assert.NotNull(result);
        Assert.Equal("0.1.0", result.Version);
        Assert.Equal("test notes", result.Notes);
        Assert.True(result.HasIntegritySource);
    }

    [Fact]
    public async Task SameStableVersionIsNotOfferedAgain()
    {
        var result = await UpdateService.CheckLatestAsync(Client(HttpStatusCode.OK, Release("v0.1.0")), new LynextReleaseVersion(new Version(0, 1, 0), false));
        Assert.Null(result);
    }

    [Fact]
    public async Task DoesNotOfferPrereleaseOnStableChannel()
    {
        var result = await UpdateService.CheckLatestAsync(Client(HttpStatusCode.OK, Release("v0.2.0", prerelease: true)), new LynextReleaseVersion(new Version(0, 1, 0), false));
        Assert.Null(result);
    }

    [Fact]
    public async Task RateLimitIsAnErrorRatherThanUpToDate()
    {
        var client = Client(HttpStatusCode.Forbidden, "{}", rateLimited: true);
        await Assert.ThrowsAsync<HttpRequestException>(() => UpdateService.CheckLatestAsync(client, new LynextReleaseVersion(new Version(0, 1, 0), true)));
    }

    [Fact]
    public async Task NetworkFailurePropagatesRatherThanUpToDate()
    {
        using var client = new HttpClient(new StubHandler(_ => throw new HttpRequestException("offline")));
        await Assert.ThrowsAsync<HttpRequestException>(() => UpdateService.CheckLatestAsync(client, new LynextReleaseVersion(new Version(0, 1, 0), true)));
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(response(request));
    }
}
