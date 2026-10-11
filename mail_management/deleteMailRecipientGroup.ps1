<#
.SYNOPSIS
    Deletes a mail recipient group via the BACKUP EAGLE REST API.

.DESCRIPTION
    GET /api/rest/mailrecipientgroups/delete?id=<GroupId>

    PowerShell counterpart of deleteMailRecipientGroup.py.
    Requirement: REST server activated in BACKUP EAGLE under Configuration > Settings > REST > Rest server active
    (default port 10987). It is deactivated by default, the change requires a restart of the BACKUP EAGLE server service.

    Supports -WhatIf (shows the request without sending it) and -Confirm.

.PARAMETER GroupId
    Id of the mail recipient group.

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER User
    BACKUP EAGLE user for the REST API. Prompted if neither -User nor -Credential is given.

.PARAMETER Password
    Password of the BACKUP EAGLE user (plain text). Prompted if not given.
    Use -Credential to avoid the password in plain text.

.PARAMETER Credential
    BACKUP EAGLE user and password as PSCredential. Alternative to -User/-Password, both cannot be combined.

.PARAMETER TimeoutSec
    Timeout of the REST call in seconds. Default: 60

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\deleteMailRecipientGroup.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin -GroupId 2

.NOTES
    Exit code 0: success, 1: REST call failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding(DefaultParameterSetName = 'UserPassword', SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $GroupId,

    [string] $BaseUrl = 'https://localhost:10987/api/rest',

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

function Invoke-BeRest([string] $Method, [string] $Resource, [byte[]] $Body, [string] $ContentType = 'application/json; charset=utf-8') {
    $params = @{
        Uri             = ($BaseUrl.TrimEnd('/') + '/' + $Resource.TrimStart('/'))
        Method          = $Method
        Headers         = $script:headers
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
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
    $resource = 'mailrecipientgroups/delete?id=' + [uri]::EscapeDataString($GroupId)

    if (-not $PSCmdlet.ShouldProcess($BaseUrl.TrimEnd('/') + '/' + $resource, 'Delete mail recipient group')) {
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

    # --- authentication (console prompt for missing values, no GUI dialog) ---
    if ($PSCmdlet.ParameterSetName -eq 'Credential') {
        $User = $Credential.UserName
        $Password = $Credential.GetNetworkCredential().Password
    } else {
        if (-not $User) {
            $User = Read-Host -Prompt 'BACKUP EAGLE user'
        }
        if (-not $Password) {
            $securePassword = Read-Host -AsSecureString -Prompt 'BACKUP EAGLE password'
            $Password = (New-Object System.Management.Automation.PSCredential('user', $securePassword)).GetNetworkCredential().Password
        }
    }

    # Basic auth on every request (the REST API has no login/session)
    $userPass = $User + ':' + $Password
    $script:headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userPass))
        Accept        = 'application/json'
    }

    Write-Host ("Connecting to {0} ..." -f $BaseUrl)
    try {
        $content = Invoke-BeRest -Method Get -Resource $resource
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
