<#
.SYNOPSIS
    Queries all nodes via the BACKUP EAGLE REST API.

.DESCRIPTION
    GET /api/rest/banode/list

    PowerShell counterpart of queryNodes.py.
    Requirement: REST server activated in BACKUP EAGLE (rest_server_active=true, default port 10987).

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER Credential
    BACKUP EAGLE user for the REST API. Prompted if not given.

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.PARAMETER PrettyPrint
    Pretty printing of the JSON response.

.EXAMPLE
    .\queryNodes.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -PrettyPrint

.NOTES
    Exit code 0: success, 1: REST call failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'https://localhost:10987/api/rest',

    [System.Management.Automation.PSCredential] $Credential,

    [switch] $VerifyCertificate,

    [switch] $PrettyPrint
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

function Format-Json([string] $Json) {
    if ([string]::IsNullOrWhiteSpace($Json)) {
        return $Json
    }
    return ConvertTo-Json -InputObject (ConvertFrom-Json -InputObject $Json) -Depth 100
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
    $resource = 'banode/list'

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
        $content = Invoke-BeRest -Method Get -Resource $resource
    } catch {
        Write-Host ("FAILED: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
        exit 1
    }

    if ($PrettyPrint) {
        Write-Output (Format-Json $content)
    } else {
        Write-Output $content
    }
    exit 0
} catch {
    Write-Host ("ERROR: {0}" -f (Get-ErrorDetails $_)) -ForegroundColor Red
    exit 2
}
