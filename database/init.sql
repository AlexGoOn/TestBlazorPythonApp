IF DB_ID(N'BlazorLab') IS NULL
    CREATE DATABASE BlazorLab;
GO

USE BlazorLab;
GO

IF OBJECT_ID(N'dbo.Notes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Notes
    (
        Id uniqueidentifier NOT NULL CONSTRAINT PK_Notes PRIMARY KEY,
        Text nvarchar(200) NOT NULL,
        CreatedBy varchar(10) NOT NULL,
        CreatedAt datetime2 NOT NULL CONSTRAINT DF_Notes_CreatedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_Notes_Text CHECK (LEN(LTRIM(RTRIM(Text))) > 0),
        CONSTRAINT CK_Notes_CreatedBy CHECK (CreatedBy IN ('Blazor', 'Python'))
    );
END;
GO
