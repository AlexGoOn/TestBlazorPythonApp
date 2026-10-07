namespace BlazorApp.Data;

public sealed record Note(Guid Id, string Text, string CreatedBy, DateTime CreatedAt);

public sealed record NoteInput(string? Text)
{
    public string ValidatedText()
    {
        var text = Text?.Trim();
        if (string.IsNullOrEmpty(text) || text.Length > 200)
        {
            throw new ArgumentException("Text must contain between 1 and 200 UTF-16 code units.");
        }

        return text;
    }
}
