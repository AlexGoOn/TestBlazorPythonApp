using System.Data;
using Microsoft.Data.SqlClient;

namespace BlazorApp.Data;

public sealed class NotesStore(string connectionString)
{
    public async Task PingAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand("SELECT TOP (0) Id FROM dbo.Notes", connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<Note>> ListAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(
            "SELECT TOP (100) Id, Text, CreatedBy, CreatedAt FROM dbo.Notes ORDER BY CreatedAt DESC, Id",
            connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var notes = new List<Note>();
        while (await reader.ReadAsync(cancellationToken))
        {
            notes.Add(ReadNote(reader));
        }

        return notes;
    }

    public async Task<Note> CreateAsync(NoteInput input, CancellationToken cancellationToken = default)
    {
        var text = input.ValidatedText();
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand("""
            INSERT INTO dbo.Notes (Id, Text, CreatedBy)
            OUTPUT INSERTED.Id, INSERTED.Text, INSERTED.CreatedBy, INSERTED.CreatedAt
            VALUES (@id, @text, 'Blazor')
            """, connection);
        command.Parameters.Add("@id", SqlDbType.UniqueIdentifier).Value = Guid.NewGuid();
        command.Parameters.Add("@text", SqlDbType.NVarChar, 200).Value = text;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("SQL did not return the created note.");
        }

        return ReadNote(reader);
    }

    private static Note ReadNote(SqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        DateTime.SpecifyKind(reader.GetDateTime(3), DateTimeKind.Utc));
}
