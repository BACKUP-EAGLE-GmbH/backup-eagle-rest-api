<#
.SYNOPSIS
    Updates a device group via the BACKUP EAGLE REST API.

.DESCRIPTION
    PUT /api/rest/group/device/<GroupId>

    PowerShell counterpart of updateDeviceGroup.py.
    Requirement: REST server activated in BACKUP EAGLE (rest_server_active=true, default port 10987).

    Supports -WhatIf (shows the request without sending it) and -Confirm.

.PARAMETER GroupId
    Id of the device group.

.PARAMETER Group
    name (required) and entries.
    JSON string or object (e.g. hashtable), which is converted to JSON.

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER Credential
    BACKUP EAGLE user for the REST API. Prompted if not given.

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\updateDeviceGroup.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -GroupId 2 -Group '{"name":"Test","entries":[{"dataSourceClassPattern":"*","versionPattern":"8.1*"}]}'

.NOTES
    Exit code 0: success, 1: REST call failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $GroupId,

    [Parameter(Mandatory = $true)]
    [object] $Group,

    [string] $BaseUrl = 'https://localhost:10987/api/rest',

    [System.Management.Automation.PSCredential] $Credential,

    [switch] $VerifyCertificate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function ConvertTo-JsonBody($Value) {
    if ($Value -is [string]) {
        # validate the JSON before it is sent
        $null = ConvertFrom-Json -InputObject $Value
        $json = $Value
    } else {
        $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    }
    # UTF-8 bytes so that special characters survive
    return ,[System.Text.Encoding]::UTF8.GetBytes($json)
}

function Invoke-BeRest([string] $Method, [string] $Resource, [byte[]] $Body, [string] $ContentType = 'application/json; charset=utf-8') {
    $params = @{
        Uri             = ($BaseUrl.TrimEnd('/') + '/' + $Resource.TrimStart('/'))
        Method          = $Method
        Headers         = $script:headers
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $params.Body = $Body
        $params.ContentType = $ContentType
    }
    if (-not $VerifyCertificate -and $PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
    }
    $response = Invoke-WebRequest @params
    # decode as UTF-8 (Windows PowerShell 5.1 falls back to ISO-8859-1 if the response has no charset)
    return [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
}

try {
    $resource = 'group/device/' + [uri]::EscapeDataString($GroupId)
    $body = ConvertTo-JsonBody $Group

    if (-not $PSCmdlet.ShouldProcess($BaseUrl.TrimEnd('/') + '/' + $resource, 'Update device group')) {
        exit 0
    }

    # --- connection settings ---
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not $VerifyCertificate) {
            if (-not ('TrustAllCertsPolicy' -as [type])) {
                Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
            }
            [Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
    }

    if (-not $Credential) {
        $Credential = Get-Credential -Message 'BACKUP EAGLE user for the REST API'
    }

    # Basic auth on every request (the REST API has no login/session)
    $userPass = $Credential.UserName + ':' + $Credential.GetNetworkCredential().Password
    $script:headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userPass))
        Accept        = 'application/json'
    }

    try {
        $content = Invoke-BeRest -Method Put -Resource $resource -Body $body
    } catch {
        Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
        exit 1
    }

    Write-Output $content
    exit 0
} catch {
    Write-Host ("ERROR: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
    exit 2
}
