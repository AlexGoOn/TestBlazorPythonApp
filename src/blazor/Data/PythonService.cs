using System.Net.Http.Json;

namespace BlazorApp.Data;

public sealed class PythonService(HttpClient client)
{
    public async Task<IReadOnlyList<Note>> ListAsync(CancellationToken cancellationToken = default) =>
        await client.GetFromJsonAsync<List<Note>>("notes", cancellationToken)
        ?? throw new InvalidOperationException("Python returned an empty response.");

    public async Task<Note> CreateAsync(NoteInput input, CancellationToken cancellationToken = default)
    {
        using var response = await client.PostAsJsonAsync(
            "notes", new NoteInput(input.ValidatedText()), cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<Note>(cancellationToken)
            ?? throw new InvalidOperationException("Python did not return the created note.");
    }
}
