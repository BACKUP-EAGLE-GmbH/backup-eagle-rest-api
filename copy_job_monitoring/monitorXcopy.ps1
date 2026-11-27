<#
.SYNOPSIS
    Runs an xcopy job and reports its result to BACKUP EAGLE (REST API, database or Mail-In).

.DESCRIPTION
    Wrapper for xcopy based copy and backup jobs (e.g. as Windows scheduled task):
      1. Runs xcopy with the given source, destination and options.
      2. Evaluates the exit code, the error output and the number of copied files.
      3. Delivers the result with all error messages to BACKUP EAGLE (-Delivery):
           Rest      POST /api/rest/genericbackup/import-baresult (default)
           Database  INSERT into the import tables BA_RESULT_IMPORT / BA_RESULT_DETAIL_IMPORT
           Mail      mail for the generic Mail-In of BACKUP EAGLE

    The result appears in BACKUP EAGLE like a result of any other backup software (Client Control, reports,
    dashboards, alerts). With the "Non-started detection" (Report missing backups) BACKUP EAGLE additionally
    alerts if no result arrives at all, e.g. because the scheduled task was deleted or the server was down.

    Requires BackupEagleDelivery.ps1 in the same folder.

    Requirements in BACKUP EAGLE:
      - A backup server of the type "Generic" whose name is passed as -BaServer.
      - Rest: REST server activated under Configuration > Settings > REST > Rest server active (default port 10987),
        the change requires a restart of the BACKUP EAGLE server service. A user with the role admin or cc_admin.
      - Database: a database user with INSERT rights on BA_RESULT_IMPORT and BA_RESULT_DETAIL_IMPORT (and the
        sequences BA_RESULT_IMPORT_S / BA_RESULT_DETAIL_IMPORT_S on PostgreSQL/Oracle). For PostgreSQL, MySQL and
        Oracle an ODBC driver is required, SQL Server works without driver.
      - Mail: Mail-In configured (mailbox and a backup assignment for the sender/recipient of the mails).

    The result is failed (RC 8) if xcopy returns an exit code other than 0 OR writes an error message.
    This is important, because xcopy returns 0 with /C (continue on errors) even if files could not be copied,
    and also if a file pattern does not match any file.

    Xcopy exit codes:
      0  files were copied without error
      1  no files were found to copy
      2  aborted, e.g. xcopy asked a question (file or directory? overwrite?) that cannot be answered in a
         scheduled task. The options /I and /Y are added for that reason.
      4  initialization error (not enough memory or disk space, invalid drive, invalid syntax) or a file could
         not be copied (e.g. locked by another process)
      5  disk write error

    Note: Microsoft recommends robocopy instead of xcopy (see monitorRobocopy.ps1), robocopy provides more
    statistics (bytes, failed files) and retries.

.PARAMETER Source
    Source file, directory or pattern (local path or UNC path).

.PARAMETER Destination
    Destination directory (local path or UNC path).

.PARAMETER Options
    Xcopy options. Default: /E /H /K (all subdirectories incl. empty ones, hidden and system files, attributes).
    /I and /Y are always added (unless /-Y is given), so that xcopy does not wait for an answer.
    Can also be passed as one string ("/E /D"), which is required with powershell.exe -File.

.PARAMETER JobName
    Name of the copy job, shown as schedule/project in BACKUP EAGLE (e.g. "FILESERVER_DAILY").

.PARAMETER BaServer
    Name of the backup server of type "Generic" in BACKUP EAGLE the result is assigned to.

.PARAMETER NodeName
    Node name in BACKUP EAGLE. Default: name of this computer.

.PARAMETER NodeGroup
    Node group (domain) in BACKUP EAGLE. Default: XCOPY

.PARAMETER ObjectName
    Name of the backed up object. Default: the source.

.PARAMETER MaxMessageLines
    Maximum number of error lines that are sent to BACKUP EAGLE. Default: 50

.PARAMETER ShowResultOnly
    Run xcopy, but only print the result (JSON, or the mail for -Delivery Mail) instead of sending it (for testing).

.PARAMETER Delivery
    How the result is delivered to BACKUP EAGLE: Rest (default), Database or Mail.

.PARAMETER DbType
    Database type of the BACKUP EAGLE database (-Delivery Database): SqlServer, PostgreSQL, MySQL or Oracle.

.PARAMETER DbConnectionString
    Connection string of the BACKUP EAGLE database (-Delivery Database).
    SQL Server (no driver required):  "Server=dbhost,1433;Database=backupeagle;Integrated Security=true"
    PostgreSQL (psqlODBC):            "Driver={PostgreSQL Unicode(x64)};Server=dbhost;Port=5432;Database=backupeagle"
    MySQL (Connector/ODBC):           "Driver={MySQL ODBC 9.1 Unicode Driver};Server=dbhost;Port=3306;Database=backupeagle"
    Oracle (Oracle ODBC driver):      "Driver={Oracle in instantclient_23};Dbq=dbhost:1521/ORCL"
    SQL Server can also be used via ODBC ("Driver={ODBC Driver 18 for SQL Server};...").

.PARAMETER DbCredentialFile
    File with the database user and password, created with Export-Clixml (see -CredentialFile). Alternatively the
    user and password can be part of the connection string or Windows authentication can be used (SQL Server).

.PARAMETER SmtpServer
    SMTP server for -Delivery Mail.

.PARAMETER SmtpPort
    SMTP port. Default: 25

.PARAMETER SmtpUseSsl
    Use STARTTLS (e.g. port 587). Implicit TLS (port 465) is not supported.

.PARAMETER SmtpCredentialFile
    File with the SMTP user and password, created with Export-Clixml (see -CredentialFile). Without this file
    the mail is sent without authentication.

.PARAMETER MailFrom
    Sender address of the mail.

.PARAMETER MailTo
    Recipient address(es) of the mail: the mailbox read by the Mail-In of BACKUP EAGLE.

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER User
    BACKUP EAGLE user for the REST API. Prompted if neither -User, -Credential nor -CredentialFile is given.

.PARAMETER Password
    Password of the BACKUP EAGLE user (plain text). Prompted if not given.
    Use -Credential or -CredentialFile to avoid the password in plain text.

.PARAMETER Credential
    BACKUP EAGLE user and password as PSCredential. Alternative to -User/-Password, both cannot be combined.

.PARAMETER CredentialFile
    File with the BACKUP EAGLE user and password, created with Export-Clixml (recommended for scheduled tasks).
    The password is stored encrypted and can only be read by the same Windows user on the same computer.
    Create it as the user that runs the scheduled task: Get-Credential | Export-Clixml C:\scripts\be_cred.xml

.PARAMETER TimeoutSec
    Timeout of the REST call in seconds. Default: 60

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options /E,/D -JobName DATA_TO_NAS -BaServer XCOPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin

.EXAMPLE
    # scheduled task: password stored encrypted with Export-Clixml
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options "/E /H /K /D" -JobName DATA_TO_NAS -BaServer XCOPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -CredentialFile C:\scripts\be_cred.xml

.EXAMPLE
    # delivery into the BACKUP EAGLE database (PostgreSQL via psqlODBC, login from an Export-Clixml file)
    .\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer XCOPY_JOBS -Delivery Database -DbType PostgreSQL -DbConnectionString "Driver={PostgreSQL Unicode(x64)};Server=dbhost;Port=5432;Database=backupeagle" -DbCredentialFile C:\scripts\db_cred.xml

.EXAMPLE
    # delivery by mail to the Mail-In mailbox of BACKUP EAGLE
    .\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer XCOPY_JOBS -Delivery Mail -SmtpServer smtp.example.com -MailFrom fileserver01@example.com -MailTo backupeagle-mailin@example.com

.EXAMPLE
    # test: run xcopy and show the result that would be sent
    .\monitorXcopy.ps1 -Source D:\Data -Destination E:\Backup\Data -JobName TEST -BaServer XCOPY_JOBS -ShowResultOnly

.NOTES
    Exit code 0: copy successful and result sent, 1: delivery failed (result NOT in BACKUP EAGLE),
    2: general error (e.g. invalid parameters), 3: copy failed and result sent.
    Tested with Windows PowerShell 5.1.
#>
[CmdletBinding(DefaultParameterSetName = 'UserPassword')]
param(
    [Parameter(Mandatory = $true)]
    [string] $Source,

    [Parameter(Mandatory = $true)]
    [string] $Destination,

    [string[]] $Options = @('/E', '/H', '/K'),

    [Parameter(Mandatory = $true)]
    [string] $JobName,

    [Parameter(Mandatory = $true)]
    [string] $BaServer,

    [string] $NodeName = $env:COMPUTERNAME,

    [string] $NodeGroup = 'XCOPY',

    [string] $ObjectName,

    [int] $MaxMessageLines = 50,

    [switch] $ShowResultOnly,

    [ValidateSet('Rest', 'Database', 'Mail')]
    [string] $Delivery = 'Rest',

    [ValidateSet('SqlServer', 'PostgreSQL', 'MySQL', 'Oracle')]
    [string] $DbType,

    [string] $DbConnectionString,

    [string] $DbCredentialFile,

    [string] $SmtpServer,

    [int] $SmtpPort = 25,

    [switch] $SmtpUseSsl,

    [string] $SmtpCredentialFile,

    [string] $MailFrom,

    [string[]] $MailTo,

    [string] $BaseUrl = 'https://localhost:10987/api/rest',

    [Parameter(ParameterSetName = 'UserPassword')]
    [string] $User,

    [Parameter(ParameterSetName = 'UserPassword')]
    [string] $Password,

    [Parameter(ParameterSetName = 'Credential', Mandatory = $true)]
    [System.Management.Automation.PSCredential] $Credential,

    [Parameter(ParameterSetName = 'CredentialFile', Mandatory = $true)]
    [string] $CredentialFile,

    [int] $TimeoutSec = 60,

    [switch] $VerifyCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# REST, database and mail delivery
. (Join-Path $PSScriptRoot 'BackupEagleDelivery.ps1')

function Format-PathArgument([string] $path) {
    # A trailing backslash would escape the closing quote ("D:\My Data\" -> D:\My Data"), so it is removed.
    # A drive root keeps its meaning by appending "." (D:\ -> D:\.)
    if ($path -match '^[A-Za-z]:\\$') {
        return $path + '.'
    }
    if ($path.Length -gt 3) {
        return $path.TrimEnd('\')
    }
    return $path
}

function Test-Option([string[]] $optionList, [string] $pattern) {
    # true if an option matches the pattern (case-insensitive)
    return [bool](@($optionList | Where-Object { $_ -match $pattern }).Count)
}

function Get-ExitCodeText([int] $code) {
    switch ($code) {
        0 { return 'Files were copied without error.' }
        1 { return 'No files were found to copy.' }
        2 { return 'Xcopy was aborted (Ctrl+C or a question that could not be answered, e.g. file or directory, overwrite).' }
        4 { return 'Initialization error (not enough memory or disk space, invalid drive or syntax) or a file could not be copied.' }
        5 { return 'Disk write error.' }
        default { return 'Unknown exit code.' }
    }
}

function Invoke-Xcopy([string[]] $argumentList) {
    # Runs xcopy, prints its output and returns the output lines (stdout and stderr marked) and the exit code.
    # Xcopy writes in the ANSI code page, so the console is switched to it for the call
    # (file names with umlauts would be garbled otherwise).
    $oldEncoding = $null
    try {
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
    } catch {
        $oldEncoding = $null
    }
    $lines = New-Object System.Collections.Generic.List[object]
    $previousPreference = $ErrorActionPreference
    try {
        # stderr lines arrive as ErrorRecord, they must not stop the script
        $ErrorActionPreference = 'Continue'
        # $null as input: questions of xcopy are not answered, xcopy stops with exit code 2 instead of waiting
        $null | & xcopy.exe @argumentList 2>&1 | ForEach-Object {
            $isError = $_ -is [System.Management.Automation.ErrorRecord]
            $line = if ($isError) { $_.Exception.Message } else { [string]$_ }
            if ($isError) { Write-Host $line -ForegroundColor Red } else { Write-Host $line }
            $lines.Add(@{ Text = $line; IsError = $isError })
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        if ($null -ne $oldEncoding) {
            [Console]::OutputEncoding = $oldEncoding
        }
    }
    return @{ Lines = $lines; ExitCode = $exitCode }
}

function Get-XcopyStatistics($lines) {
    # The last line is "<n> File(s) copied" (text depends on the language), xcopy lists each copied file before
    # (with /F as "source -> destination"). The size of the listed files is added up, a file that is directly
    # followed by an error message was not copied.
    $filesCopied = $null
    $bytes = [long]0
    $sizeKnown = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $entry = $lines[$i]
        if ($entry.IsError) {
            continue
        }
        if ($entry.Text -match '^\s*(\d+)\s+\S') {
            $filesCopied = [long]$Matches[1]
            continue
        }
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1].IsError) {
            continue
        }
        $path = ($entry.Text -split ' -> ')[0].Trim()
        if ($path) {
            try {
                $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if (-not $item.PSIsContainer) {
                    $bytes += $item.Length
                    $sizeKnown = $true
                }
            } catch {
                # no file name (e.g. other output line), ignore
            }
        }
    }
    return @{ FilesCopied = $filesCopied; Bytes = $(if ($sizeKnown) { $bytes } else { $null }) }
}

function New-BaObject([string] $value, [int] $type) {
    # type 0 = info, 8 = error
    return [ordered]@{ value = $value; type = $type }
}

try {
    if (-not $ObjectName) {
        $ObjectName = if ($Source.Length -gt 3) { $Source.TrimEnd('\') } else { $Source }
    }

    # --- build the xcopy command line ---
    # options given as one string ("/E /D") or comma separated (powershell.exe -File) are split before each "/"
    $xcopyOptions = @($Options | ForEach-Object { $_ -split '[,\s]+(?=/)' } | Where-Object { $_ })
    # no questions in a scheduled task: destination is a directory (/I), overwrite without asking (/Y)
    if (-not (Test-Option $xcopyOptions '^/I$')) {
        $xcopyOptions += '/I'
    }
    if (-not (Test-Option $xcopyOptions '^/-?Y$')) {
        $xcopyOptions += '/Y'
    }
    $argumentList = @(Format-PathArgument $Source) + @(Format-PathArgument $Destination) + $xcopyOptions
    $commandLine = 'xcopy ' + (($argumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')

    # --- check and prepare the delivery before the copy job runs ---
    $deliverySettings = @{
        Delivery           = $Delivery
        BaseUrl            = $BaseUrl
        User               = $User
        Password           = $Password
        Credential         = $Credential
        CredentialFile     = $CredentialFile
        TimeoutSec         = $TimeoutSec
        VerifyCertificate  = [bool]$VerifyCertificate
        DbType             = $DbType
        DbConnectionString = $DbConnectionString
        DbCredentialFile   = $DbCredentialFile
        SmtpServer         = $SmtpServer
        SmtpPort           = $SmtpPort
        SmtpUseSsl         = [bool]$SmtpUseSsl
        SmtpCredentialFile = $SmtpCredentialFile
        MailFrom           = $MailFrom
        MailTo             = $MailTo
    }
    if (-not $ShowResultOnly) {
        $settingsError = Test-DeliverySettings $deliverySettings
        if ($settingsError) {
            Write-Host ("ERROR: {0}" -f $settingsError) -ForegroundColor Red
            exit 2
        }
        Initialize-Delivery $deliverySettings
    }

    # --- run xcopy ---
    $baObjects = New-Object System.Collections.Generic.List[object]
    $baObjects.Add((New-BaObject ('Command: ' + $commandLine) 0))
    $startTime = Get-Date
    $exitCode = 4
    $lines = @()
    try {
        $run = Invoke-Xcopy $argumentList
        $exitCode = $run.ExitCode
        $lines = $run.Lines
    } catch {
        # e.g. xcopy.exe not found
        $lines = @(@{ Text = 'xcopy could not be started: ' + $_.Exception.Message; IsError = $true })
        Write-Host $lines[0].Text -ForegroundColor Red
    }
    $endTime = Get-Date

    # --- evaluate ---
    # error messages and repeated questions are only reported once
    $errorLines = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($entry in $lines) {
        if ($entry.IsError -and $entry.Text.Trim() -and -not $seen.ContainsKey($entry.Text.Trim())) {
            $seen[$entry.Text.Trim()] = $true
            $errorLines.Add($entry.Text.Trim())
        }
    }
    if ($exitCode -eq 2) {
        # the unanswered question is written to stdout, report it
        # xcopy appends the unanswered input after the question mark, it is removed
        $lastLines = @($lines | Where-Object { -not $_.IsError -and $_.Text.Trim() } | Select-Object -Last 3 | ForEach-Object { ($_.Text -replace '\?[^?]*$', '?').Trim() })
        foreach ($lastLine in $lastLines) {
            if (-not $seen.ContainsKey($lastLine)) {
                $seen[$lastLine] = $true
                $errorLines.Add($lastLine)
            }
        }
    }

    $failed = ($exitCode -ne 0) -or ($errorLines.Count -gt 0)
    $rc = if ($failed) { 8 } else { 0 }
    $exitText = "Xcopy exit code {0}: {1}" -f $exitCode, (Get-ExitCodeText $exitCode)
    if ($exitCode -eq 0 -and $errorLines.Count -gt 0) {
        $exitText += ' But xcopy reported errors (e.g. with /C), see below.'
    }
    $baObjects.Add((New-BaObject $exitText $rc))

    $statistics = Get-XcopyStatistics $lines
    if ($null -ne $statistics.FilesCopied) {
        $text = "Files copied: {0}" -f $statistics.FilesCopied
        if ($null -ne $statistics.Bytes) {
            $text += (", bytes: {0}" -f $statistics.Bytes)
        }
        $baObjects.Add((New-BaObject $text 0))
    }

    $count = 0
    foreach ($errorLine in $errorLines) {
        if ($count -ge $MaxMessageLines) {
            $baObjects.Add((New-BaObject ("... {0} more error lines, see the xcopy output" -f ($errorLines.Count - $MaxMessageLines)) 8))
            break
        }
        $baObjects.Add((New-BaObject $errorLine 8))
        $count++
    }

    # --- build result ---
    $durationSec = [Math]::Max(1, [long]($endTime - $startTime).TotalSeconds)
    $result = [ordered]@{
        projectName = $JobName
        baServer    = $BaServer
        baNodeGroup = $NodeGroup
        baNode      = $NodeName
        objectName  = $ObjectName
        startTime   = Get-UnixTimeMs $startTime
        endTime     = Get-UnixTimeMs $endTime
        rc          = $rc
        backupState = if ($failed) { 'Failed' } else { 'Success' }
        backupType  = 'Xcopy'
        objectType  = 'Directory'
        baObjects   = $baObjects
    }
    if ($null -ne $statistics.FilesCopied) {
        $result.objectsBackedUp = $statistics.FilesCopied
    }
    if ($null -ne $statistics.Bytes) {
        $result.bytes = $statistics.Bytes
        $result.transferredSize = $statistics.Bytes
        $result.transferRate = [long]($statistics.Bytes / $durationSec)
    }
    if ($ShowResultOnly) {
        Show-BackupEagleResult $result $deliverySettings
        if ($failed) { exit 3 } else { exit 0 }
    }

    # --- deliver result ---
    Write-Host ("Delivering result ({0}) ..." -f $Delivery)
    try {
        $target = Send-BackupEagleResult $result $deliverySettings
    } catch {
        Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
        exit 1
    }
    Write-Host ("Result delivered to {0}: {1}" -f $target, $(if ($failed) { 'copy FAILED (RC 8)' } else { 'copy OK (RC 0)' }))
    if ($failed) { exit 3 } else { exit 0 }
} catch {
    Write-Host ("ERROR: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
    exit 2
}
