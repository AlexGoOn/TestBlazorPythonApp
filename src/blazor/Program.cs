using BlazorApp.Components;
using BlazorApp.Data;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Sql")
    ?? throw new InvalidOperationException("ConnectionStrings:Sql must be configured.");
var pythonUrl = builder.Configuration["PythonService:BaseUrl"]
    ?? throw new InvalidOperationException("PythonService:BaseUrl must be configured.");
if (!Uri.TryCreate(pythonUrl, UriKind.Absolute, out var pythonUri) ||
    (pythonUri.Scheme != Uri.UriSchemeHttp && pythonUri.Scheme != Uri.UriSchemeHttps))
{
    throw new InvalidOperationException("PythonService:BaseUrl must be an absolute HTTP(S) URL.");
}

builder.Services.AddSingleton(new NotesStore(connectionString));
builder.Services.AddHttpClient<PythonService>(client =>
{
    client.BaseAddress = new Uri(pythonUri.AbsoluteUri.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(10);
});
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

var app = builder.Build();

app.UseExceptionHandler(handler => handler.Run(async context =>
{
    var error = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    var status = error switch
    {
        ArgumentException => StatusCodes.Status400BadRequest,
        SqlException => StatusCodes.Status503ServiceUnavailable,
        HttpRequestException => StatusCodes.Status502BadGateway,
        OperationCanceledException => StatusCodes.Status504GatewayTimeout,
        _ => StatusCodes.Status500InternalServerError
    };
    await Results.Problem(
        statusCode: status,
        title: status == 400 ? "Invalid note text." : "The operation failed. Check the application logs.")
        .ExecuteAsync(context);
}));

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
app.UseAntiforgery();

app.MapGet("/health", async (NotesStore store, CancellationToken cancellationToken) =>
{
    await store.PingAsync(cancellationToken);
    return Results.Ok(new { status = "ok", database = "ok" });
});

// Local integration endpoints are not published in production.
if (app.Environment.IsDevelopment())
{
    app.MapGet("/api/notes", (NotesStore store, CancellationToken ct) => store.ListAsync(ct));
    app.MapPost("/api/notes", async (NoteInput input, NotesStore store, CancellationToken ct) =>
        Results.Json(await store.CreateAsync(input, ct), statusCode: StatusCodes.Status201Created));
    app.MapGet("/api/python/notes", (PythonService service, CancellationToken ct) => service.ListAsync(ct));
    app.MapPost("/api/python/notes", async (NoteInput input, PythonService service, CancellationToken ct) =>
        Results.Json(await service.CreateAsync(input, ct), statusCode: StatusCodes.Status201Created));
}

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
