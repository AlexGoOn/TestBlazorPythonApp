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

DECLARE @identities TABLE (Name sysname, PrincipalId uniqueidentifier);
INSERT INTO @identities VALUES
    (N'$(FrontendIdentityName)', '$(FrontendPrincipalId)'),
    (N'$(BackendIdentityName)', '$(BackendPrincipalId)');

DECLARE @name sysname, @principalId uniqueidentifier, @sid binary(16), @sql nvarchar(max);
DECLARE identities CURSOR LOCAL FAST_FORWARD FOR SELECT Name, PrincipalId FROM @identities;
OPEN identities;
FETCH NEXT FROM identities INTO @name, @principalId;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sid = CONVERT(binary(16), @principalId);
    IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @name AND sid <> @sid)
        THROW 50001, 'SQL user SID differs from the managed identity principal ID. Review identity replacement before changing access.', 1;
    IF DATABASE_PRINCIPAL_ID(@name) IS NULL
    BEGIN
        -- Explicit SIDs avoid Microsoft Graph directory permissions on the SQL server.
        SET @sql = N'CREATE USER ' + QUOTENAME(@name) + N' WITH SID = '
            + CONVERT(nvarchar(34), @sid, 1) + N', TYPE = E;';
        EXEC sys.sp_executesql @sql;
    END;
    SET @sql = N'GRANT SELECT, INSERT ON OBJECT::dbo.Notes TO ' + QUOTENAME(@name) + N';';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM identities INTO @name, @principalId;
END;
CLOSE identities;
DEALLOCATE identities;
GO
