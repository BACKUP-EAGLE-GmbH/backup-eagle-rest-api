<#
.SYNOPSIS
    Runs a robocopy job and reports its result to BACKUP EAGLE (REST API, database or Mail-In).

.DESCRIPTION
    Wrapper for robocopy based copy and backup jobs (e.g. as Windows scheduled task):
      1. Runs robocopy with the given source, destination and options.
      2. Evaluates the exit code and the summary (directories, files, bytes) and collects the error lines.
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

    Robocopy exit codes:
      0-7  success (1 = files copied, 2 = extra files, 4 = mismatched files) -> result OK (RC 0)
      8+   files could not be copied or fatal error                          -> result failed (RC 8)

    The options /NP (no progress), /BYTES (sizes in bytes) and /NFL /NDL (no file and directory list) are added
    if they are missing, so that the output stays small and can be evaluated. Use -FullOutput to keep the file list.
    If /LOG is used, /TEE is added, because the output is evaluated from the console.

    The script uses only the language independent parts of the robocopy output (numbers and error codes) and
    therefore works with every Windows language.

.PARAMETER Source
    Source directory (local path or UNC path).

.PARAMETER Destination
    Destination directory (local path or UNC path).

.PARAMETER Files
    Optional file names or patterns (e.g. *.bak). Default: all files.

.PARAMETER Options
    Robocopy options. Default: /E /R:3 /W:10 (all subdirectories, 3 retries with 10 seconds wait).
    Note: without /R robocopy retries a locked file 1 million times.
    Can also be passed as one string ("/MIR /R:3 /W:10"), which is required with powershell.exe -File.

.PARAMETER JobName
    Name of the copy job, shown as schedule/project in BACKUP EAGLE (e.g. "FILESERVER_DAILY").

.PARAMETER BaServer
    Name of the backup server of type "Generic" in BACKUP EAGLE the result is assigned to.

.PARAMETER NodeName
    Node name in BACKUP EAGLE. Default: name of this computer.

.PARAMETER NodeGroup
    Node group (domain) in BACKUP EAGLE. Default: ROBOCOPY

.PARAMETER ObjectName
    Name of the backed up object. Default: the source directory.

.PARAMETER MaxMessageLines
    Maximum number of error lines that are sent to BACKUP EAGLE. Default: 50

.PARAMETER FullOutput
    Do not add /NFL /NDL, robocopy lists all copied files and directories.

.PARAMETER ShowResultOnly
    Run robocopy, but only print the result (JSON, or the mail for -Delivery Mail) instead of sending it (for testing).

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
    BACKUP EAGLE user for the REST API. Prompted if neither -User nor -Credential is given.

.PARAMETER Password
    Password of the BACKUP EAGLE user (plain text). Prompted if not given.
    Use -Credential to avoid the password in plain text.

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
    .\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options /MIR,/R:3,/W:10 -JobName DATA_TO_NAS -BaServer ROBOCOPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin

.EXAMPLE
    # scheduled task: password stored encrypted with Export-Clixml
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options "/MIR /R:3 /W:10" -JobName DATA_TO_NAS -BaServer ROBOCOPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -CredentialFile C:\scripts\be_cred.xml

.EXAMPLE
    # delivery into the BACKUP EAGLE database (SQL Server, Windows authentication of the task user)
    .\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options "/MIR /R:3 /W:10" -JobName DATA_TO_NAS -BaServer ROBOCOPY_JOBS -Delivery Database -DbType SqlServer -DbConnectionString "Server=dbhost;Database=backupeagle;Integrated Security=true"

.EXAMPLE
    # delivery by mail to the Mail-In mailbox of BACKUP EAGLE
    .\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer ROBOCOPY_JOBS -Delivery Mail -SmtpServer smtp.example.com -SmtpPort 587 -SmtpUseSsl -SmtpCredentialFile C:\scripts\smtp_cred.xml -MailFrom fileserver01@example.com -MailTo backupeagle-mailin@example.com

.EXAMPLE
    # test: run robocopy and show the result that would be sent
    .\monitorRobocopy.ps1 -Source D:\Data -Destination E:\Backup\Data -JobName TEST -BaServer ROBOCOPY_JOBS -ShowResultOnly

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

    [string[]] $Files = @(),

    [string[]] $Options = @('/E', '/R:3', '/W:10'),

    [Parameter(Mandatory = $true)]
    [string] $JobName,

    [Parameter(Mandatory = $true)]
    [string] $BaServer,

    [string] $NodeName = $env:COMPUTERNAME,

    [string] $NodeGroup = 'ROBOCOPY',

    [string] $ObjectName,

    [int] $MaxMessageLines = 50,

    [switch] $FullOutput,

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
    # true if an option matches the pattern (case-insensitive, e.g. '^/LOG\+?:')
    return [bool](@($optionList | Where-Object { $_ -match $pattern }).Count)
}

function Get-ExitCodeText([int] $code) {
    if ($code -eq 0) {
        return 'No files were copied, source and destination are in sync.'
    }
    $texts = @()
    if ($code -band 1) { $texts += 'Files were copied successfully.' }
    if ($code -band 2) { $texts += 'Extra files or directories were detected in the destination.' }
    if ($code -band 4) { $texts += 'Mismatched files or directories were detected.' }
    if ($code -band 8) { $texts += 'Some files or directories could not be copied (retry limit exceeded).' }
    if ($code -band 16) { $texts += 'Fatal error: robocopy did not copy any files (e.g. invalid parameters, no access to source or destination).' }
    return ($texts -join ' ')
}

function Invoke-Robocopy([string[]] $argumentList) {
    # Runs robocopy, prints its output and returns the output lines and the exit code.
    # Robocopy writes in the OEM code page of the console, so the console is switched to it for the call
    # (file names with umlauts would be garbled otherwise, e.g. if the console uses UTF-8).
    $oldEncoding = $null
    try {
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    } catch {
        $oldEncoding = $null
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $previousPreference = $ErrorActionPreference
    try {
        # stderr lines arrive as ErrorRecord, they must not stop the script
        $ErrorActionPreference = 'Continue'
        # $null as input: robocopy never waits for console input
        $null | & robocopy.exe @argumentList 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
            Write-Host $line
            $lines.Add($line)
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

function Get-RobocopySummary($lines) {
    # The summary consists of the lines directories, files, bytes (in this order, label depends on the language)
    # with 6 numbers each: total, copied, skipped, mismatch, failed, extras. /BYTES makes all values numbers.
    $rows = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*[^:]+:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $rows += , @([long]$Matches[1], [long]$Matches[2], [long]$Matches[3], [long]$Matches[4], [long]$Matches[5], [long]$Matches[6])
        }
    }
    if ($rows.Count -lt 3) {
        # no summary, e.g. robocopy stopped with a fatal error
        return $null
    }
    # the summary is at the end of the output, use the last three rows
    $rows = $rows[($rows.Count - 3)..($rows.Count - 1)]
    return @{ Dirs = $rows[0]; Files = $rows[1]; Bytes = $rows[2] }
}

function Get-RobocopyErrors($lines) {
    # Error lines have a language independent error code "(0x00000005)", the next line contains the Windows error text.
    # Identical errors (retries) are only reported once.
    $errors = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '\(0x[0-9A-Fa-f]{8}\)') {
            # remove the timestamp at the beginning (yyyy/MM/dd HH:mm:ss)
            $text = ($line -replace '^\s*\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\s+', '').Trim()
            if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -and $lines[$i + 1] -notmatch '\(0x[0-9A-Fa-f]{8}\)') {
                $text = $text + ' - ' + $lines[$i + 1].Trim()
            }
            if (-not $seen.ContainsKey($text)) {
                $seen[$text] = $true
                $errors.Add($text)
            }
        }
    }
    return , $errors
}

function New-BaObject([string] $value, [int] $type) {
    # type 0 = info, 8 = error
    return [ordered]@{ value = $value; type = $type }
}

try {
    if (-not $ObjectName) {
        $ObjectName = if ($Source.Length -gt 3) { $Source.TrimEnd('\') } else { $Source }
    }

    # --- build the robocopy command line ---
    # options given as one string ("/MIR /R:3") or comma separated (powershell.exe -File) are split before each "/"
    $robocopyOptions = @($Options | ForEach-Object { $_ -split '[,\s]+(?=/)' } | Where-Object { $_ })
    foreach ($option in '/NP', '/BYTES') {
        if (-not (Test-Option $robocopyOptions ('^' + [regex]::Escape($option) + '$'))) {
            $robocopyOptions += $option
        }
    }
    if (-not $FullOutput) {
        foreach ($option in '/NFL', '/NDL') {
            if (-not (Test-Option $robocopyOptions ('^' + [regex]::Escape($option) + '$'))) {
                $robocopyOptions += $option
            }
        }
    }
    # with /LOG robocopy writes nothing to the console, /TEE writes to both
    if ((Test-Option $robocopyOptions '^/(UNI)?LOG\+?:') -and -not (Test-Option $robocopyOptions '^/TEE$')) {
        $robocopyOptions += '/TEE'
    }
    $argumentList = @(Format-PathArgument $Source) + @(Format-PathArgument $Destination) + @($Files) + $robocopyOptions
    $commandLine = 'robocopy ' + (($argumentList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')

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

    # --- run robocopy ---
    $baObjects = New-Object System.Collections.Generic.List[object]
    $baObjects.Add((New-BaObject ('Command: ' + $commandLine) 0))
    $startTime = Get-Date
    $exitCode = 16
    $lines = @()
    try {
        $run = Invoke-Robocopy $argumentList
        $exitCode = $run.ExitCode
        $lines = $run.Lines
    } catch {
        # e.g. robocopy.exe not found
        $lines = @('robocopy could not be started: ' + $_.Exception.Message)
        Write-Host $lines[0] -ForegroundColor Red
    }
    $endTime = Get-Date

    # --- evaluate ---
    $failed = $exitCode -ge 8
    $rc = if ($failed) { 8 } else { 0 }
    $baObjects.Add((New-BaObject ("Robocopy exit code {0}: {1}" -f $exitCode, (Get-ExitCodeText $exitCode)) $rc))

    $summary = Get-RobocopySummary $lines
    if ($null -ne $summary) {
        $names = 'Directories', 'Files', 'Bytes'
        $keys = 'Dirs', 'Files', 'Bytes'
        for ($i = 0; $i -lt 3; $i++) {
            $v = $summary[$keys[$i]]
            $baObjects.Add((New-BaObject ("{0}: total {1}, copied {2}, skipped {3}, mismatch {4}, failed {5}, extras {6}" -f $names[$i], $v[0], $v[1], $v[2], $v[3], $v[4], $v[5]) 0))
        }
    }

    $errorLines = Get-RobocopyErrors $lines
    if ($failed -and $errorLines.Count -eq 0) {
        # no error with error code found (e.g. invalid parameter), report the last lines of the output instead
        $errorLines = @($lines | Where-Object { $_ -and $_.Trim() -and $_ -notmatch '^\s*-+\s*$' } | Select-Object -Last 10 | ForEach-Object { $_.Trim() })
    }
    # errors of single files (e.g. a locked file that was copied in a retry) are only info if robocopy succeeded
    $errorType = if ($failed) { 8 } else { 0 }
    $count = 0
    foreach ($errorLine in $errorLines) {
        if ($count -ge $MaxMessageLines) {
            $baObjects.Add((New-BaObject ("... {0} more error lines, see the robocopy output" -f ($errorLines.Count - $MaxMessageLines)) $errorType))
            break
        }
        $baObjects.Add((New-BaObject $errorLine $errorType))
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
        backupType  = 'Robocopy'
        objectType  = 'Directory'
        baObjects   = $baObjects
    }
    if ($null -ne $summary) {
        $result.bytes = $summary.Bytes[1]
        $result.transferredSize = $summary.Bytes[1]
        $result.bytesInspected = $summary.Bytes[0]
        $result.transferRate = [long]($summary.Bytes[1] / $durationSec)
        $result.objectsInspected = $summary.Files[0]
        $result.objectsBackedUp = $summary.Files[1]
        $result.objectsFailed = $summary.Files[4]
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
