<#
.SYNOPSIS
    Imports node names from a file into a user defined group via the BACKUP EAGLE REST API.

.DESCRIPTION
    Same behaviour as the node import in the user defined group editor of the BACKUP EAGLE Admin UI (BE-8604):
    1. Reads the node file: one node per line, lines are trimmed, empty lines are skipped,
       duplicates (case-insensitive) are removed, at most 1000 nodes (the rest is cut off with a warning).
    2. Each node "node001" becomes the pattern "*node001*" (disable with -NoWildcard).
    3. Reads all user defined groups:     GET  /api/rest/udgs/list
    4. Group with the given name exists:  POST /api/rest/udgs/update  (ALL existing entries are replaced)
       Group does not exist:              POST /api/rest/udgs/add
       Only the column node name (baNodeName) is filled, all other columns are "*", exclude is false.
       Name and address list of an existing group stay unchanged.

    Requirement: REST server activated in BACKUP EAGLE under Configuration > Settings > REST > Rest server active
    (default port 10987). It is deactivated by default, the change requires a restart of the BACKUP EAGLE server service.

    Supports -WhatIf (shows what would be done without changing anything) and -Confirm.

.PARAMETER NodeFile
    Text file with one node name per line (UTF-8 or ANSI, e.g. exported from Excel as .txt/.csv with one column).

.PARAMETER GroupName
    Name of the user defined group that is created or updated.

.PARAMETER Hostname
    Host name or IP address of the BACKUP EAGLE server. Default: localhost

.PARAMETER Port
    Port of the BACKUP EAGLE REST server. Default: 10987

.PARAMETER BaseUrl
    Base URL of the REST API, overrides -Hostname/-Port. Default: https://<Hostname>:<Port>/api/rest

.PARAMETER NoWildcard
    Import the node names as they are instead of "*<node>*".

.PARAMETER User
    BACKUP EAGLE user for the REST API. Prompted if neither -User nor -Credential is given.

.PARAMETER Password
    Password of the BACKUP EAGLE user (plain text). Prompted if not given.
    Use -Credential to avoid the password in plain text.

.PARAMETER Credential
    BACKUP EAGLE user and password as PSCredential. Alternative to -User/-Password, both cannot be combined.

.PARAMETER TimeoutSec
    Timeout of each REST call in seconds. Default: 60

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\importNodesToUserDefinedGroup.ps1 -NodeFile .\nodes.txt -GroupName "Merck-Report-Nodes" -Hostname beserver -User admin -Password admin

    Creates the group "Merck-Report-Nodes" or replaces its entries with "*<node>*" for every node in nodes.txt.

.EXAMPLE
    .\importNodesToUserDefinedGroup.ps1 -NodeFile .\nodes.txt -GroupName "Merck-Report-Nodes" -Hostname beserver -WhatIf

    Prompts for user and password and only shows whether the group would be created or updated.

.EXAMPLE
    .\importNodesToUserDefinedGroup.ps1 -NodeFile .\nodes.txt -GroupName "UDG-1" -Hostname 192.168.0.1 -Credential (Get-Credential) -NoWildcard -Confirm:$false

    Uses a PSCredential, imports the node names without wildcards and does not ask for confirmation.

.NOTES
    Exit code 0: success (or -WhatIf / nothing to do), 1: REST call failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding(DefaultParameterSetName = 'UserPassword', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $NodeFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $GroupName,

    [string] $Hostname = 'localhost',

    [ValidateRange(1, 65535)]
    [int] $Port = 10987,

    [string] $BaseUrl,

    [switch] $NoWildcard,

    [Parameter(ParameterSetName = 'UserPassword')]
    [string] $User,

    [Parameter(ParameterSetName = 'UserPassword')]
    [string] $Password,

    [Parameter(ParameterSetName = 'Credential', Mandatory = $true)]
    [System.Management.Automation.PSCredential] $Credential,

    [int] $TimeoutSec = 60,

    [switch] $VerifyCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# same limit as the node import dialog of the Admin UI (NodeImportTextParser.MAX_LINES)
$MaxNodes = 1000

function ConvertTo-PlainText([System.Security.SecureString] $secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-ErrorDetails($errorRecord) {
    # PowerShell 7 provides the response body in ErrorDetails, Windows PowerShell 5.1 only in the response stream
    if ($errorRecord.ErrorDetails -and $errorRecord.ErrorDetails.Message) {
        return $errorRecord.ErrorDetails.Message
    }
    $response = $null
    if ($errorRecord.Exception.PSObject.Properties['Response']) {
        $response = $errorRecord.Exception.Response
    }
    if ($response) {
        # the UDG provider returns its error message in the HTTP reason phrase, not in the body
        $status = [int]$response.StatusCode
        $reason = ''
        if ($response.PSObject.Properties['StatusDescription']) {
            $reason = $response.StatusDescription
        } elseif ($response.PSObject.Properties['ReasonPhrase']) {
            $reason = $response.ReasonPhrase
        }
        $body = ''
        if ($response -is [System.Net.HttpWebResponse]) {
            try {
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $body = $reader.ReadToEnd()
            } catch {
                $body = ''
            }
        }
        return ("HTTP {0} {1} {2}" -f $status, $reason, $body).Trim()
    }
    return $errorRecord.Exception.Message
}

function Invoke-BeRest([string] $Method, [string] $Path, $Body) {
    $params = @{
        Uri             = ($BaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/'))
        Method          = $Method
        Headers         = $script:headers
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
    }
    if ($null -ne $Body) {
        # UTF-8 bytes so that special characters in group and node names survive
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 10 -Compress))
        $params.ContentType = 'application/json; charset=utf-8'
    }
    if (-not $VerifyCertificate -and $PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
    }
    $response = Invoke-WebRequest @params
    # decode as UTF-8 (Windows PowerShell 5.1 falls back to ISO-8859-1 if the response has no charset)
    return [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
}

function Read-NodeFile([string] $path) {
    # returns the distinct, trimmed, non-empty lines of the file (same rules as NodeImportTextParser)
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).ProviderPath)
    $text = $null
    try {
        # strict UTF-8 (throws on invalid bytes), BOM is removed
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $text = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
    } catch {
        # no valid UTF-8 -> ANSI file (e.g. saved by Excel/Notepad)
        $text = [System.Text.Encoding]::Default.GetString($bytes)
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $nodes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($text -split "`r`n|`r|`n")) {
        $node = $line.Trim()
        if ($node -and $seen.Add($node)) {
            $nodes.Add($node)
        }
    }
    return ,$nodes.ToArray()
}

function New-GroupElement([string] $nodePattern) {
    # same defaults as the node import of the Admin UI: only the node name is set, everything else matches all
    return [ordered]@{
        baServerName    = '*'
        baNodeName      = $nodePattern
        baNodeGroupName = '*'
        baNodeOs        = '*'
        baNodeContact   = '*'
        baNodeActive    = '*'
        baServerActive  = '*'
        isExclude       = $false
        tag             = '*'
    }
}

try {
    if (-not $BaseUrl) {
        $BaseUrl = 'https://{0}:{1}/api/rest' -f $Hostname, $Port
    }

    # --- read nodes ---
    if (-not (Test-Path -LiteralPath $NodeFile -PathType Leaf)) {
        throw "Node file not found: $NodeFile"
    }
    $nodes = Read-NodeFile $NodeFile
    if ($nodes.Count -eq 0) {
        throw "Node file contains no node names: $NodeFile"
    }
    if ($nodes.Count -gt $MaxNodes) {
        Write-Warning ("Node file contains {0} nodes, only the first {1} are imported." -f $nodes.Count, $MaxNodes)
        $nodes = $nodes[0..($MaxNodes - 1)]
    }
    $elements = @(foreach ($node in $nodes) {
        if ($NoWildcard) {
            New-GroupElement $node
        } else {
            New-GroupElement ('*' + $node + '*')
        }
    })
    Write-Host ("{0} nodes read from {1}" -f $nodes.Count, $NodeFile)

    # --- connection settings ---
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not $VerifyCertificate) {
            if (-not ('TrustAllCertsPolicy' -as [type])) {
                Add-Type -TypeDefinition @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
'@
            }
            [Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
    }

    # --- authentication (console prompt for missing values, no GUI dialog) ---
    if ($PSCmdlet.ParameterSetName -eq 'Credential') {
        $User = $Credential.UserName
        $Password = $Credential.GetNetworkCredential().Password
    } else {
        if (-not $User) {
            $User = Read-Host -Prompt 'BACKUP EAGLE user'
        }
        if (-not $Password) {
            $Password = ConvertTo-PlainText (Read-Host -AsSecureString -Prompt 'BACKUP EAGLE password')
        }
    }

    # Basic auth on every request (the REST API has no login/session)
    $userPass = $User + ':' + $Password
    $script:headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userPass))
        Accept        = 'application/json'
    }

    # --- find existing group ---
    Write-Host ("Reading user defined groups from {0} ..." -f $BaseUrl)
    try {
        $content = Invoke-BeRest -Method Get -Path 'udgs/list' -Body $null
    } catch {
        Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
        exit 1
    }
    # assign first: Windows PowerShell 5.1 returns a JSON array as single object, @(...) directly around the call would nest it
    $response = ConvertFrom-Json -InputObject $content
    $groups = @($response)
    # group names are compared case-insensitively, an exact (case-sensitive) match wins
    $existing = @($groups | Where-Object { $_.name -ceq $GroupName })
    if ($existing.Count -eq 0) {
        $existing = @($groups | Where-Object { $_.name -ieq $GroupName })
    }
    if ($existing.Count -gt 1) {
        throw ("Group name '{0}' is ambiguous: {1} groups found (ids {2})." -f $GroupName, $existing.Count, (($existing | ForEach-Object { $_.id }) -join ', '))
    }

    # --- create or update ---
    if ($existing.Count -eq 1) {
        $group = $existing[0]
        $oldCount = @($group.elements).Count
        $action = "Update user defined group (id {0}): replace {1} entries by {2} node entries" -f $group.id, $oldCount, $elements.Count
        if (-not $PSCmdlet.ShouldProcess($group.name, $action)) {
            exit 0
        }
        # name and address list stay unchanged (null = not changed by the server)
        $body = [ordered]@{ id = $group.id; elements = $elements }
        try {
            $null = Invoke-BeRest -Method Post -Path 'udgs/update' -Body $body
        } catch {
            Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
            exit 1
        }
        Write-Host ("OK      group '{0}' (id {1}) updated: {2} entries replaced by {3} node entries" -f $group.name, $group.id, $oldCount, $elements.Count) -ForegroundColor Green
    } else {
        $action = "Create user defined group with {0} node entries" -f $elements.Count
        if (-not $PSCmdlet.ShouldProcess($GroupName, $action)) {
            exit 0
        }
        $body = [ordered]@{ name = $GroupName; elements = $elements }
        try {
            $content = Invoke-BeRest -Method Post -Path 'udgs/add' -Body $body
        } catch {
            Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
            exit 1
        }
        $newId = ''
        try {
            $created = ConvertFrom-Json -InputObject $content
            if ($created.PSObject.Properties['id']) {
                $newId = " (id {0})" -f $created.id
            }
        } catch {
            $newId = ''
        }
        Write-Host ("OK      group '{0}'{1} created with {2} node entries" -f $GroupName, $newId, $elements.Count) -ForegroundColor Green
    }
    exit 0
} catch {
    Write-Host ("ERROR: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
    exit 2
} finally {
    $Password = $null
    $userPass = $null
}
