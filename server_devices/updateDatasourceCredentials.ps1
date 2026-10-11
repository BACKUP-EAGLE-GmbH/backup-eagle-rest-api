<#
.SYNOPSIS
    Sets a password of all data sources whose name matches a pattern via the BACKUP EAGLE REST API.

.DESCRIPTION
    1. Reads all active data sources:      GET /api/rest/datasource/list
    2. Keeps the data sources whose name matches -NamePattern (and whose type matches -ServerType).
    3. Sets the password per data source:  PUT /api/rest/datasource/updateCredentials
       Body: {"type":"<PasswordType>","server":"<name>","password":"<plain text>"}
       (The server encrypts the password, so it has to be sent in plain text over HTTPS.)

    Password types (-PasswordType) and the data sources they apply to:
    - client: client password of ISP data sources
    - https:  password of the REST/HTTPS connection (all data sources)
    - ssh:    SSH password (all data sources)
    - smb:    SMB password of generic data sources
    - token:  REST API token (all data sources)
    - snmpv3: SNMPv3 credentials of devices configured with SNMP version 3
              (uses -SnmpAuthProtocol/-SnmpAuthPassword/-SnmpPrivacyProtocol/-SnmpPrivacyPassword)
    Data sources that do not support the password type are reported as FAILED by the server.

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

.PARAMETER PasswordType
    Which password is set: client, https, ssh, smb, token or snmpv3 (see description).

.PARAMETER ServerType
    Wildcard pattern for the type of the data source (serverTypeName, e.g. "ISP", "Veeam").
    Default: "ISP" for -PasswordType client, otherwise "*" (all types).

.PARAMETER NewPassword
    New password as SecureString (all password types except snmpv3). Prompted (twice) if not given.

.PARAMETER SnmpAuthProtocol
    SNMPv3 authentication protocol (only -PasswordType snmpv3): noAuth, md5, sha1 or sha256.

.PARAMETER SnmpAuthPassword
    SNMPv3 authentication password as SecureString. Prompted (twice) if needed and not given.

.PARAMETER SnmpPrivacyProtocol
    SNMPv3 privacy protocol (only -PasswordType snmpv3): noPrivacy, 3ds, aes128, aes192, aes256 or des.

.PARAMETER SnmpPrivacyPassword
    SNMPv3 privacy password as SecureString. Prompted (twice) if needed and not given.

.PARAMETER BaseUrl
    Base URL of the REST API. Default: https://localhost:10987/api/rest

.PARAMETER User
    BACKUP EAGLE user (admin) for the REST API. Prompted if neither -User nor -Credential is given.

.PARAMETER Password
    Password of the BACKUP EAGLE user (plain text). Prompted if not given.
    Use -Credential to avoid the password in plain text.

.PARAMETER Credential
    BACKUP EAGLE user (admin) and password as PSCredential. Alternative to -User/-Password, both cannot be combined.

.PARAMETER TimeoutSec
    Timeout of each REST call in seconds. Default: 60

.PARAMETER VerifyCertificate
    Validate the server certificate. By default the certificate is not validated, because BACKUP EAGLE
    uses a self-signed certificate by default.

.EXAMPLE
    .\updateDatasourceCredentials.ps1 -NamePattern "ISP-PROD-*" -PasswordType client -User admin -Password admin -WhatIf

    Lists all ISP data sources matching ISP-PROD-* without changing anything.

.EXAMPLE
    .\updateDatasourceCredentials.ps1 -NamePattern "ISP-PROD-*" -PasswordType client -BaseUrl https://beserver:10987/api/rest

    Prompts for the BACKUP EAGLE user, its password and the new password and sets the ISP client password.

.EXAMPLE
    .\updateDatasourceCredentials.ps1 -NamePattern "veeam-*" -ServerType Veeam -PasswordType https -User admin -Password admin

    Sets the REST/HTTPS password of all Veeam data sources whose name starts with "veeam-".

.EXAMPLE
    .\updateDatasourceCredentials.ps1 -NamePattern "lib-*" -PasswordType snmpv3 -SnmpAuthProtocol sha256 -SnmpPrivacyProtocol aes128 -User admin -Password admin

    Sets the SNMPv3 credentials of all devices starting with "lib-" (prompts for both SNMPv3 passwords).

.EXAMPLE
    .\updateDatasourceCredentials.ps1 -NamePattern "^ISP-(A|B)\d+$" -UseRegex -PasswordType client -Credential (Get-Credential) -Confirm:$false

    Uses a regular expression, a PSCredential and does not ask for confirmation per data source.

.NOTES
    Exit code 0: all matching data sources updated (or -WhatIf), 1: at least one update failed, 2: general error.
    Works with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding(DefaultParameterSetName = 'UserPassword', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string] $NamePattern,

    [switch] $UseRegex,

    [Parameter(Mandatory = $true)]
    [ValidateSet('client', 'https', 'ssh', 'smb', 'token', 'snmpv3')]
    [string] $PasswordType,

    [string] $ServerType,

    [System.Security.SecureString] $NewPassword,

    [ValidateSet('noAuth', 'md5', 'sha1', 'sha256')]
    [string] $SnmpAuthProtocol,

    [System.Security.SecureString] $SnmpAuthPassword,

    [ValidateSet('noPrivacy', '3ds', 'aes128', 'aes192', 'aes256', 'des')]
    [string] $SnmpPrivacyProtocol,

    [System.Security.SecureString] $SnmpPrivacyPassword,

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

function ConvertTo-PlainText([System.Security.SecureString] $secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-NewSecret([System.Security.SecureString] $Given, [string] $Label) {
    # returns the given secret or prompts twice for it, always as plain text (required by the REST API)
    if (-not $Given) {
        $Given = Read-Host -AsSecureString -Prompt $Label
        $repeat = Read-Host -AsSecureString -Prompt ('Repeat ' + $Label)
        if ((ConvertTo-PlainText $Given) -cne (ConvertTo-PlainText $repeat)) {
            throw "$Label`: entries do not match."
        }
    }
    $plain = ConvertTo-PlainText $Given
    if ([string]::IsNullOrEmpty($plain)) {
        throw "$Label must not be empty."
    }
    return $plain
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
        TimeoutSec  = $TimeoutSec
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

function Get-ServerTypeName($dataSource) {
    if ($dataSource.PSObject.Properties['serverTypeName'] -and $dataSource.serverTypeName) {
        return [string]$dataSource.serverTypeName
    }
    return ''
}

try {
    # --- check parameters ---
    if ($PasswordType -eq 'snmpv3') {
        if (-not $SnmpAuthProtocol -or -not $SnmpPrivacyProtocol) {
            throw '-PasswordType snmpv3 requires -SnmpAuthProtocol and -SnmpPrivacyProtocol.'
        }
    } elseif ($SnmpAuthProtocol -or $SnmpAuthPassword -or $SnmpPrivacyProtocol -or $SnmpPrivacyPassword) {
        throw 'The -Snmp* parameters are only allowed with -PasswordType snmpv3.'
    }
    if (-not $PSBoundParameters.ContainsKey('ServerType')) {
        # client passwords only exist for ISP data sources
        if ($PasswordType -eq 'client') {
            $ServerType = 'ISP'
        } else {
            $ServerType = '*'
        }
    }

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
            $User = Read-Host -Prompt 'BACKUP EAGLE user (role admin)'
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

    # --- determine matching data sources ---
    Write-Host ("Reading data sources from {0} ..." -f $BaseUrl)
    # assign first: Windows PowerShell 5.1 returns a JSON array as single object, @(...) directly around the call would nest it
    $response = Invoke-BeRest -Method Get -Path 'datasource/list' -Body $null
    $dataSources = @($response)

    Write-Host ("Found {0} active data sources:" -f $dataSources.Count)
    foreach ($ds in @($dataSources | Sort-Object { Get-ServerTypeName $_ }, name)) {
        Write-Host ("  {0,-20} {1} (id {2})" -f (Get-ServerTypeName $ds), $ds.name, $ds.id)
    }

    $typeMatching = @($dataSources | Where-Object { (Get-ServerTypeName $_) -like $ServerType })

    if ($UseRegex) {
        $matching = @($typeMatching | Where-Object { $_.name -match $NamePattern })
    } else {
        $matching = @($typeMatching | Where-Object { $_.name -like $NamePattern })
    }
    $matching = @($matching | Sort-Object name)

    Write-Host ("{0} active data sources, {1} of type '{2}', {3} matching '{4}'" -f $dataSources.Count, $typeMatching.Count, $ServerType, $matching.Count, $NamePattern)

    if ($matching.Count -eq 0) {
        Write-Warning 'No matching data source found - nothing to do.'
        exit 0
    }

    Write-Host 'Matching data sources:'
    foreach ($ds in $matching) {
        Write-Host ("  - {0} ({1}, id {2})" -f $ds.name, (Get-ServerTypeName $ds), $ds.id)
    }

    # --- build request body (without server name) ---
    $template = $null
    if (-not $WhatIfPreference) {
        if ($PasswordType -eq 'snmpv3') {
            $template = @{ type = $PasswordType; snmpAuthProtocol = $SnmpAuthProtocol; snmpPrivacyProtocol = $SnmpPrivacyProtocol }
            if ($SnmpAuthProtocol -ne 'noAuth') {
                $template.snmpAuthPassword = Read-NewSecret $SnmpAuthPassword 'SNMPv3 authentication password'
            }
            if ($SnmpPrivacyProtocol -ne 'noPrivacy') {
                $template.snmpPrivacyPassword = Read-NewSecret $SnmpPrivacyPassword 'SNMPv3 privacy password'
            }
        } else {
            $template = @{ type = $PasswordType; password = (Read-NewSecret $NewPassword ("New $PasswordType password")) }
        }
    }

    # --- set passwords ---
    $ok = 0
    $failed = 0
    foreach ($ds in $matching) {
        if (-not $PSCmdlet.ShouldProcess($ds.name, "Set $PasswordType password")) {
            continue
        }
        try {
            # the REST API identifies the data source by name (case-insensitive)
            $body = $template.Clone()
            $body.server = $ds.name
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
    $template = $null
    $body = $null
}
