<#
.SYNOPSIS
    Sets the password of all ISP data sources whose name matches a pattern via the BACKUP EAGLE REST API.

.DESCRIPTION
    1. Reads all active data sources:      GET /api/rest/datasource/list
    2. Keeps ISP data sources (serverTypeName = "ISP") whose name matches -NamePattern.
    3. Sets the ISP client password:       PUT /api/rest/datasource/updateCredentials
       Body: {"type":"client","server":"<name>","password":"<plain text>"}
       (The server encrypts the password, so it has to be sent in plain text over HTTPS.)

    Requirements:
    - REST server activated in BACKUP EAGLE (rest_server_active=true, default port 10987).
    - BACKUP EAGLE user with role admin.
    - Only ACTIVE data sources are returned by the REST API, inactive ones are not changed.

    Supports -WhatIf (lists the matching data sources without changing them) and -Confirm.

.PARAMETER NamePattern
    Pattern for the data source name. Wildcard pattern (e.g. "ISP-PROD-*") by default,
    regular expression with -UseRegex. Matching is case-insensitive.

.PARAMETER UseRegex
    Interpret -NamePattern as regular expression instead of a wildcard pattern.

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER Credential
    BACKUP EAGLE user (admin) for the REST API. Prompted if not given.

.PARAMETER NewPassword
    New ISP password as SecureString. Prompted (twice) if not given.

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\Set-IspDataSourcePassword.ps1 -NamePattern "ISP-PROD-*" -WhatIf

    Lists all ISP data sources matching ISP-PROD-* without changing anything.

.EXAMPLE
    .\Set-IspDataSourcePassword.ps1 -NamePattern "ISP-PROD-*" -BaseUrl https://beserver:10987/api/rest

    Prompts for the BACKUP EAGLE user and the new password and sets it for all matching ISP data sources.

.EXAMPLE
    .\Set-IspDataSourcePassword.ps1 -NamePattern "^ISP-(A|B)\d+$" -UseRegex -Confirm:$false

    Uses a regular expression and does not ask for confirmation per data source.

.NOTES
    Exit code 0: all matching data sources updated (or -WhatIf), 1: at least one update failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string] $NamePattern,

    [switch] $UseRegex,

    [string] $BaseUrl = 'https://localhost:10987/api/rest',

    [System.Management.Automation.PSCredential] $Credential,

    [System.Security.SecureString] $NewPassword,

    [switch] $VerifyCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IspServerTypeName = 'ISP'

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
    if ($response -and ($response -is [System.Net.HttpWebResponse])) {
        try {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $body = $reader.ReadToEnd()
            return "HTTP $([int]$response.StatusCode): $body"
        } catch {
            return "HTTP $([int]$response.StatusCode)"
        }
    }
    return $errorRecord.Exception.Message
}

function Invoke-BeRest([string] $Method, [string] $Path, $Body) {
    $params = @{
        Uri         = ($BaseUrl.TrimEnd('/') + '/' + $Path.TrimStart('/'))
        Method      = $Method
        Headers     = $script:headers
        ContentType = 'application/json; charset=utf-8'
    }
    if ($null -ne $Body) {
        # single JSON object (no array) - UTF-8 bytes so that special characters in passwords survive
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress))
    }
    if (-not $VerifyCertificate -and $PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
    }
    return Invoke-RestMethod @params
}

try {
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

    if (-not $Credential) {
        $Credential = Get-Credential -Message 'BACKUP EAGLE user (role admin) for the REST API'
    }

    # Basic auth on every request (the REST API has no login/session)
    $userPass = $Credential.UserName + ':' + $Credential.GetNetworkCredential().Password
    $script:headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userPass))
        Accept        = 'application/json'
    }

    # --- determine matching ISP data sources ---
    Write-Verbose "Reading data sources from $BaseUrl"
    $dataSources = @(Invoke-BeRest -Method Get -Path 'datasource/list' -Body $null)

    $ispDataSources = @($dataSources | Where-Object { $_.PSObject.Properties['serverTypeName'] -and $_.serverTypeName -eq $IspServerTypeName })

    if ($UseRegex) {
        $matching = @($ispDataSources | Where-Object { $_.name -match $NamePattern })
    } else {
        $matching = @($ispDataSources | Where-Object { $_.name -like $NamePattern })
    }
    $matching = @($matching | Sort-Object name)

    Write-Host ("{0} active data sources, {1} ISP data sources, {2} matching '{3}'" -f $dataSources.Count, $ispDataSources.Count, $matching.Count, $NamePattern)

    if ($matching.Count -eq 0) {
        Write-Warning 'No matching ISP data source found - nothing to do.'
        exit 0
    }

    foreach ($ds in $matching) {
        Write-Host ("  - {0} (id {1})" -f $ds.name, $ds.id)
    }

    if ($WhatIfPreference) {
        # only list - ShouldProcess below reports the planned changes
        $plainPassword = $null
    } else {
        if (-not $NewPassword) {
            $NewPassword = Read-Host -AsSecureString -Prompt 'New ISP password'
            $repeat = Read-Host -AsSecureString -Prompt 'Repeat new ISP password'
            if ((ConvertTo-PlainText $NewPassword) -cne (ConvertTo-PlainText $repeat)) {
                throw 'Passwords do not match.'
            }
        }
        $plainPassword = ConvertTo-PlainText $NewPassword
        if ([string]::IsNullOrEmpty($plainPassword)) {
            throw 'The new password must not be empty.'
        }
    }

    # --- set passwords ---
    $ok = 0
    $failed = 0
    foreach ($ds in $matching) {
        if (-not $PSCmdlet.ShouldProcess($ds.name, 'Set ISP password')) {
            continue
        }
        try {
            # the REST API identifies the data source by name (case-insensitive)
            $body = @{ type = 'client'; server = $ds.name; password = $plainPassword }
            $null = Invoke-BeRest -Method Put -Path 'datasource/updateCredentials' -Body $body
            Write-Host ("OK      {0}" -f $ds.name) -ForegroundColor Green
            $ok++
        } catch {
            Write-Host ("FAILED  {0}: {1}" -f $ds.name, (Get-ErrorDetails $_)) -ForegroundColor Red
            $failed++
        }
    }

    if (-not $WhatIfPreference) {
        Write-Host ("Done: {0} updated, {1} failed" -f $ok, $failed)
    }
    if ($failed -gt 0) {
        exit 1
    }
    exit 0
} catch {
    Write-Host ("ERROR: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
    exit 2
} finally {
    $plainPassword = $null
}
