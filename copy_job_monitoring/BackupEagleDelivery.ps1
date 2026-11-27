<#
.SYNOPSIS
    Delivery of a backup result to BACKUP EAGLE: REST API, BACKUP EAGLE database or Mail-In.

.DESCRIPTION
    Helper functions used by monitorRobocopy.ps1 and monitorXcopy.ps1 (dot-sourced, keep this file in the same folder).
    Not meant to be called directly.

    Delivery types:
      Rest      POST /api/rest/genericbackup/import-baresult
      Database  INSERT into the import tables BA_RESULT_IMPORT and BA_RESULT_DETAIL_IMPORT of the BACKUP EAGLE database
                (SQL Server via System.Data.SqlClient, PostgreSQL/MySQL/Oracle via ODBC). The result and its messages
                are inserted in one transaction, so BACKUP EAGLE never imports a result without its messages.
                BACKUP EAGLE converts the imported rows with the generic action "Convert imported results".
      Mail      Mail in the format of the generic Mail-In parser of BACKUP EAGLE ("Node name:", "Job name:", ...).
                Every error message is sent as a line "ERROR: ...", so it becomes an error message of the result.
                A successful result contains "Backup successful", so that no other line can set it to failed.
#>

Set-StrictMode -Version Latest

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
    # message with the inner exceptions, e.g. "Failure sending mail. - Unable to connect to the remote server"
    $exception = $errorRecord.Exception
    while ($exception.InnerException -and $exception -is [System.Management.Automation.MethodInvocationException]) {
        $exception = $exception.InnerException
    }
    $messages = New-Object System.Collections.Generic.List[string]
    while ($exception) {
        if (-not $messages.Contains($exception.Message)) {
            $messages.Add($exception.Message)
        }
        $exception = $exception.InnerException
    }
    return ($messages -join ' - ')
}

function Get-UnixTimeMs([DateTime] $time) {
    return [DateTimeOffset]::new($time.ToUniversalTime()).ToUnixTimeMilliseconds()
}

function Import-CredentialFile([string] $path) {
    # credential file created with: Get-Credential | Export-Clixml <path> (readable only by the same user on the same computer)
    $credential = Import-Clixml -LiteralPath $path
    return @{ User = $credential.UserName; Password = $credential.GetNetworkCredential().Password }
}

function Test-DeliverySettings($settings) {
    # checks the parameters of the selected delivery type before the copy job runs, returns an error text or $null
    switch ($settings.Delivery) {
        'Database' {
            if (-not $settings.DbType) { return '-DbType is required for -Delivery Database.' }
            if (-not $settings.DbConnectionString) { return '-DbConnectionString is required for -Delivery Database.' }
        }
        'Mail' {
            if (-not $settings.SmtpServer) { return '-SmtpServer is required for -Delivery Mail.' }
            if (-not $settings.MailFrom) { return '-MailFrom is required for -Delivery Mail.' }
            if (-not $settings.MailTo) { return '-MailTo is required for -Delivery Mail.' }
        }
    }
    return $null
}

function Initialize-Delivery($settings) {
    # Reads credentials (and prompts for missing REST credentials) before the copy job runs, so that a missing
    # password does not show up only after a long running copy.
    $settings.Headers = $null
    $settings.DbLogin = $null
    $settings.SmtpLogin = $null
    if ($settings.Delivery -eq 'Rest') {
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            if (-not $settings.VerifyCertificate) {
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
        if ($settings.Credential) {
            $beUser = $settings.Credential.UserName
            $bePassword = $settings.Credential.GetNetworkCredential().Password
        } elseif ($settings.CredentialFile) {
            $fileCredential = Import-CredentialFile $settings.CredentialFile
            $beUser = $fileCredential.User
            $bePassword = $fileCredential.Password
        } else {
            # console prompt for missing values, no GUI dialog
            $beUser = $settings.User
            $bePassword = $settings.Password
            if (-not $beUser) {
                $beUser = Read-Host -Prompt 'BACKUP EAGLE user'
            }
            if (-not $bePassword) {
                $securePassword = Read-Host -AsSecureString -Prompt 'BACKUP EAGLE password'
                $bePassword = (New-Object System.Management.Automation.PSCredential('user', $securePassword)).GetNetworkCredential().Password
            }
        }
        # Basic auth on every request (the REST API has no login/session)
        $settings.Headers = @{
            Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($beUser + ':' + $bePassword))
            Accept        = 'application/json'
        }
    } elseif ($settings.Delivery -eq 'Database' -and $settings.DbCredentialFile) {
        $settings.DbLogin = Import-CredentialFile $settings.DbCredentialFile
    } elseif ($settings.Delivery -eq 'Mail' -and $settings.SmtpCredentialFile) {
        $settings.SmtpLogin = Import-CredentialFile $settings.SmtpCredentialFile
    }
}

function Send-ResultRest($result, $settings) {
    $params = @{
        Uri             = ($settings.BaseUrl.TrimEnd('/') + '/genericbackup/import-baresult')
        Method          = 'Post'
        Headers         = $settings.Headers
        UseBasicParsing = $true
        TimeoutSec      = $settings.TimeoutSec
        Body            = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $result -Depth 10 -Compress))
        ContentType     = 'application/json; charset=utf-8'
    }
    if (-not $settings.VerifyCertificate -and $PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
    }
    $null = Invoke-WebRequest @params
    return $settings.BaseUrl
}

# result field -> column of BA_RESULT_IMPORT (only filled fields are inserted)
$script:ImportColumns = [ordered]@{
    objectName       = 'bari_object_name'
    projectName      = 'bari_project_name'
    startTime        = 'bari_start_time'
    endTime          = 'bari_end_time'
    baNode           = 'bari_node'
    baServer         = 'bari_server'
    baNodeGroup      = 'bari_nodegroup'
    rc               = 'bari_rc'
    bytes            = 'bari_bytes'
    bytesInspected   = 'bari_bytes_inspected'
    transferRate     = 'bari_transfer_rate'
    objectsInspected = 'bari_objects_inspected'
    objectsBackedUp  = 'bari_objects_backed_up'
    objectsFailed    = 'bari_objects_failed'
    objectsDeleted   = 'bari_objects_deleted'
    transferredSize  = 'bari_transferredSize'
    backupState      = 'bari_backupState'
    backupType       = 'bari_backupType'
    objectType       = 'bari_objectType'
}

function Limit-Text([string] $text, [int] $maxLength) {
    # names are varchar(255), messages varchar(1024) in the import tables
    if ($text.Length -gt $maxLength) {
        return $text.Substring(0, $maxLength - 3) + '...'
    }
    return $text
}

function New-DbCommand($connection, $transaction, [string] $sql, [object[]] $values) {
    # SQL is written with "?" placeholders (ODBC), SqlClient needs named parameters @p1, @p2, ...
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandTimeout = 60
    if ($connection -is [System.Data.SqlClient.SqlConnection]) {
        $parts = $sql.Split('?')
        $builder = New-Object System.Text.StringBuilder($parts[0])
        for ($index = 1; $index -lt $parts.Count; $index++) {
            $null = $builder.Append('@p' + $index).Append($parts[$index])
        }
        $sql = $builder.ToString()
        $index = 0
        foreach ($value in $values) {
            $index++
            $null = $command.Parameters.AddWithValue('@p' + $index, $value)
        }
    } else {
        foreach ($value in $values) {
            $parameter = $command.CreateParameter()
            $parameter.Value = $value
            if ($value -is [DateTime]) {
                $parameter.DbType = [System.Data.DbType]::DateTime
            }
            $null = $command.Parameters.Add($parameter)
        }
    }
    $command.CommandText = $sql
    return $command
}

function Send-ResultDatabase($result, $settings) {
    $dbType = $settings.DbType
    $connectionString = $settings.DbConnectionString
    # SQL Server without ODBC driver in the connection string: native SqlClient, everything else via ODBC
    $useSqlClient = ($dbType -eq 'SqlServer') -and ($connectionString -notmatch '(?i)(^|;)\s*(driver|dsn)\s*=')
    if ($useSqlClient) {
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connectionString)
        if ($settings.DbLogin) {
            $builder['User ID'] = $settings.DbLogin.User
            $builder['Password'] = $settings.DbLogin.Password
        }
        $connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
    } else {
        $builder = New-Object System.Data.Odbc.OdbcConnectionStringBuilder($connectionString)
        if ($settings.DbLogin) {
            $builder['UID'] = $settings.DbLogin.User
            $builder['PWD'] = $settings.DbLogin.Password
        }
        $connection = New-Object System.Data.Odbc.OdbcConnection($builder.ConnectionString)
    }

    # values of BA_RESULT_IMPORT: times as local time of this computer (BACKUP EAGLE stores local server time)
    $columns = New-Object System.Collections.Generic.List[string]
    $values = New-Object System.Collections.Generic.List[object]
    foreach ($field in $script:ImportColumns.Keys) {
        if (-not $result.Contains($field) -or $null -eq $result[$field]) {
            continue
        }
        $value = $result[$field]
        if ($field -eq 'startTime' -or $field -eq 'endTime') {
            $value = [DateTimeOffset]::FromUnixTimeMilliseconds($value).LocalDateTime
        } elseif ($value -is [string]) {
            $value = Limit-Text $value 255
        }
        $columns.Add($script:ImportColumns[$field])
        $values.Add($value)
    }

    $connection.Open()
    try {
        # result and messages in one transaction: BACKUP EAGLE must never import the result without its messages
        $transaction = $connection.BeginTransaction()
        try {
            $placeholders = (@('?') * $columns.Count) -join ', '
            switch ($dbType) {
                'PostgreSQL' {
                    $id = [long](New-DbCommand $connection $transaction "SELECT nextval('ba_result_import_s')" @()).ExecuteScalar()
                    $sql = "INSERT INTO BA_RESULT_IMPORT (bari_id, " + ($columns -join ', ') + ") VALUES (?, $placeholders)"
                    $null = (New-DbCommand $connection $transaction $sql (@($id) + $values.ToArray())).ExecuteNonQuery()
                    $detailSql = "INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_id, bardi_value, bardi_type, bari_id) VALUES (nextval('ba_result_detail_import_s'), ?, ?, ?)"
                }
                'Oracle' {
                    $id = [long](New-DbCommand $connection $transaction 'SELECT BA_RESULT_IMPORT_S.NEXTVAL FROM DUAL' @()).ExecuteScalar()
                    $sql = "INSERT INTO BA_RESULT_IMPORT (bari_id, " + ($columns -join ', ') + ") VALUES (?, $placeholders)"
                    $null = (New-DbCommand $connection $transaction $sql (@($id) + $values.ToArray())).ExecuteNonQuery()
                    $detailSql = 'INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_id, bardi_value, bardi_type, bari_id) VALUES (BA_RESULT_DETAIL_IMPORT_S.NEXTVAL, ?, ?, ?)'
                }
                'SqlServer' {
                    $sql = "INSERT INTO BA_RESULT_IMPORT (" + ($columns -join ', ') + ") OUTPUT INSERTED.bari_id VALUES ($placeholders)"
                    $id = [long](New-DbCommand $connection $transaction $sql $values.ToArray()).ExecuteScalar()
                    $detailSql = 'INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_value, bardi_type, bari_id) VALUES (?, ?, ?)'
                }
                'MySQL' {
                    $sql = "INSERT INTO BA_RESULT_IMPORT (" + ($columns -join ', ') + ") VALUES ($placeholders)"
                    $null = (New-DbCommand $connection $transaction $sql $values.ToArray()).ExecuteNonQuery()
                    $id = [long](New-DbCommand $connection $transaction 'SELECT LAST_INSERT_ID()' @()).ExecuteScalar()
                    $detailSql = 'INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_value, bardi_type, bari_id) VALUES (?, ?, ?)'
                }
            }
            foreach ($baObject in $result.baObjects) {
                $null = (New-DbCommand $connection $transaction $detailSql @((Limit-Text $baObject.value 1024), [int]$baObject.type, $id)).ExecuteNonQuery()
            }
            $transaction.Commit()
        } catch {
            try { $transaction.Rollback() } catch { }
            throw
        }
    } finally {
        $connection.Close()
    }
    return "$dbType database (BA_RESULT_IMPORT id $id)"
}

function Format-ByteAmount([long] $bytes) {
    # format understood by the Mail-In parser, e.g. "1.53 GB" (units of 1024, decimal point)
    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $value = [double]$bytes
    $unit = 0
    while ($value -ge 1024 -and $unit -lt $units.Count - 1) {
        $value = $value / 1024
        $unit++
    }
    return $value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) + ' ' + $units[$unit]
}

function New-ResultMail($result) {
    # Mail for the generic Mail-In parser of BACKUP EAGLE (classification "Generic_Collector"):
    #   Node name / Job name / Domain name / Backup server / Amount are evaluated as fields of the result.
    #   Every line of the mail becomes a message of the result, lines with error|fehler|warning|warnung|failed are errors.
    #   "Backup successful" sets the result to OK and all lines to info (also e.g. "failed 0" of a statistic).
    $failed = $result.rc -ne 0
    $status = if ($failed) { 'FAILED' } else { 'OK' }
    $subject = "BACKUP EAGLE copy job {0} on {1}: {2}" -f $result.projectName, $result.baNode, $status
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Node name: ' + $result.baNode)
    $lines.Add('Job name: ' + $result.projectName)
    $lines.Add('Domain name: ' + $result.baNodeGroup)
    $lines.Add('Backup server: ' + $result.baServer)
    if ($result.Contains('bytes') -and $null -ne $result.bytes) {
        $lines.Add('Amount: ' + (Format-ByteAmount $result.bytes))
    }
    if ($failed) {
        $lines.Add('Status: copy job FAILED')
    } else {
        $lines.Add('Status: Backup successful')
    }
    $lines.Add('Object: ' + $result.objectName)
    $lines.Add('Start time: ' + [DateTimeOffset]::FromUnixTimeMilliseconds($result.startTime).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss'))
    $lines.Add('End time: ' + [DateTimeOffset]::FromUnixTimeMilliseconds($result.endTime).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss'))
    foreach ($baObject in $result.baObjects) {
        # line breaks would split a message into several lines
        $text = ([string]$baObject.value) -replace '[\r\n]+', ' '
        if ($baObject.type -gt 0) {
            $lines.Add('ERROR: ' + $text)
        } else {
            $lines.Add($text)
        }
    }
    return @{ Subject = $subject; Body = ($lines -join "`r`n") }
}

function Send-ResultMail($result, $settings) {
    $mail = New-ResultMail $result
    $message = New-Object System.Net.Mail.MailMessage
    $message.From = $settings.MailFrom
    foreach ($recipient in @($settings.MailTo | ForEach-Object { $_ -split '[,;]' } | Where-Object { $_.Trim() })) {
        $message.To.Add($recipient.Trim())
    }
    $message.Subject = $mail.Subject
    $message.Body = $mail.Body
    $message.SubjectEncoding = [System.Text.Encoding]::UTF8
    $message.BodyEncoding = [System.Text.Encoding]::UTF8
    $message.IsBodyHtml = $false
    $client = New-Object System.Net.Mail.SmtpClient($settings.SmtpServer, $settings.SmtpPort)
    $client.Timeout = $settings.TimeoutSec * 1000
    # STARTTLS (implicit TLS on port 465 is not supported by System.Net.Mail)
    $client.EnableSsl = [bool]$settings.SmtpUseSsl
    if ($settings.SmtpLogin) {
        $client.Credentials = New-Object System.Net.NetworkCredential($settings.SmtpLogin.User, $settings.SmtpLogin.Password)
    }
    try {
        $client.Send($message)
    } finally {
        $message.Dispose()
        $client.Dispose()
    }
    return "mail to $($settings.MailTo -join ', ') via $($settings.SmtpServer)"
}

function Send-BackupEagleResult($result, $settings) {
    # returns a description of the target, throws on error
    switch ($settings.Delivery) {
        'Rest' { return Send-ResultRest $result $settings }
        'Database' { return Send-ResultDatabase $result $settings }
        'Mail' { return Send-ResultMail $result $settings }
    }
}

function Show-BackupEagleResult($result, $settings) {
    # -ShowResultOnly: shows what would be sent with the selected delivery type
    if ($settings.Delivery -eq 'Mail') {
        $mail = New-ResultMail $result
        Write-Output ('Subject: ' + $mail.Subject)
        Write-Output ''
        Write-Output $mail.Body
    } else {
        Write-Output (ConvertTo-Json -InputObject $result -Depth 10)
    }
}
