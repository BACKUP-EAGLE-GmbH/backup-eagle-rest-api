# Monitoring of copy jobs (rsync, robocopy, xcopy)

Important data is often copied with rsync, robocopy or xcopy by scheduled tasks or cron jobs. These jobs fail silently: a script that does not check the exit code reports nothing, a locked file or a full destination goes unnoticed, and a copy job that does not run at all (deleted scheduled task, server down) is noticed at the latest when a restore is needed.

The wrapper scripts in this folder run the copy tool, evaluate its exit code and output and deliver the result **with all error messages** to BACKUP EAGLE®. The copy job then appears in BACKUP EAGLE® like a backup of any other backup software: with status, runtime, amount of data, number of files and error messages in Client Control, reports, dashboards and alerts. Together with the **Non-started detection** (Report missing backups) of BACKUP EAGLE® you are also alerted if a copy job does not deliver a result at all.

## Content

| File                      | Platform                 | Description                                                                                     |
| ------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------- |
| `monitorRobocopy.ps1`     | Windows (PowerShell)     | Runs robocopy and delivers the result                                                           |
| `monitorXcopy.ps1`        | Windows (PowerShell)     | Runs xcopy and delivers the result                                                              |
| `BackupEagleDelivery.ps1` | Windows (PowerShell)     | Delivery functions (REST, database, mail) used by both PowerShell wrappers, keep it in the same folder. Not called directly. |
| `monitorRsync.py`         | Linux (Python 3)         | Runs rsync and delivers the result (one file, contains the delivery functions itself)          |

## How it works

1. The wrapper runs the copy tool with the given source, destination and options and prints its output (for the log of the scheduled task or cron job).
2. It evaluates the exit code, the statistics (files, bytes) and the error messages. Only the language independent parts of the output are used (numbers, error codes), so the scripts work with every system language.
3. It delivers one result to BACKUP EAGLE®: start and end time, status (OK = RC 0, failed = RC 8), copied and total bytes, number of files, the command line and the error messages.

When is a copy job failed (RC 8)?

| Tool     | Failed if                                                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------- |
| robocopy | exit code 8 or higher (files could not be copied after all retries, fatal error such as missing source)       |
| xcopy    | exit code not 0 **or** any error message. xcopy returns 0 with `/C` even if files could not be copied, and also if a file pattern matches no file. |
| rsync    | exit code not 0. Exit code 24 (source files vanished during the run, e.g. temporary files) is only a warning by default, use `--vanished-is-error=True` to treat it as error. |

What the wrappers add to the command line:

- robocopy: `/NP` (no progress) and `/BYTES` (sizes in bytes), `/NFL /NDL` (no file and directory list, `-FullOutput` keeps the list), `/TEE` if `/LOG` is used. Default options: `/E /R:3 /W:10` (without `/R` robocopy retries a locked file one million times).
- xcopy: `/I` and `/Y`, so that xcopy never waits for an answer in a scheduled task (unless `/-Y` is given; xcopy then stops with exit code 2, which is reported as error). Default options: `/E /H /K`.
- rsync: `--stats`.

## Delivery

The result is delivered in one of three ways (`-Delivery` / `--delivery`):

| Delivery         | How                                                                                       | Use when                                                         |
| ---------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `Rest` (default) | `POST /api/rest/genericbackup/import-baresult`                                            | the copy job can reach the REST API of BACKUP EAGLE®             |
| `Database`       | INSERT into the import tables `BA_RESULT_IMPORT` and `BA_RESULT_DETAIL_IMPORT`             | the REST API is not activated, but the database can be reached   |
| `Mail`           | mail in the format of the generic Mail-In parser, sent to the Mail-In mailbox of BACKUP EAGLE® | the copy job has no direct connection to BACKUP EAGLE® (e.g. DMZ, customer site) |

### How the error messages are transported

- **REST and database:** every message is a detail of the result with the type 0 (info) or 8 (error). The database delivery inserts the result and its messages in **one transaction**, so BACKUP EAGLE® never imports a result without its messages.
- **Mail:** every error message is a line `ERROR: <message>`. The Mail-In turns every line of the mail into a message of the result, lines containing error, fehler, warning, warnung or failed become error messages and set the result to failed. A successful copy job contains the line `Status: Backup successful`, which makes the result OK and all lines info messages (so that e.g. the statistic line "failed 0" does not set the result to failed).

Example of a mail of a failed copy job:

```text
Subject: BACKUP EAGLE copy job DATA_TO_NAS on FILESRV01: FAILED

Node name: FILESRV01
Job name: DATA_TO_NAS
Domain name: ROBOCOPY
Backup server: COPY_JOBS
Amount: 1.208 GB
Status: copy job FAILED
Object: D:\Data
Start time: 2026-11-27 01:30:00
End time: 2026-11-27 01:42:17
Command: robocopy D:\Data \\nas01\backup\Data /MIR /R:3 /W:10 /NP /BYTES /NFL /NDL
ERROR: Robocopy exit code 9: Files were copied successfully. Some files or directories could not be copied (retry limit exceeded).
Files: total 18233, copied 412, skipped 17820, mismatch 0, failed 1, extras 0
ERROR: ERROR 32 (0x00000020) Copying File D:\Data\finance.xlsx - The process cannot access the file because it is being used by another process.
```

## Setup

### 1. BACKUP EAGLE®

- Create a backup server of the type **Generic** (e.g. `COPY_JOBS`) and pass its name as `-BaServer` / `--ba-server`. Results for an unknown server name are discarded. Nodes, node groups and jobs are created automatically with the first result.
- Activate the **Non-started detection** (Report missing backups) so that missing results are alerted, e.g. a result at least every day or in a time window like 22:00 to 02:00.

### 2. Delivery

| Delivery   | Requirements                                                                                                                                                                       |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Rest`     | REST server activated under **Configuration > Settings > REST > Rest server active** (default port 10987, requires a restart of the BACKUP EAGLE® server service). A BACKUP EAGLE® user with the role admin or cc_admin. |
| `Database` | A database user with INSERT rights on `BA_RESULT_IMPORT` and `BA_RESULT_DETAIL_IMPORT`, on PostgreSQL and Oracle also on the sequences `BA_RESULT_IMPORT_S` and `BA_RESULT_DETAIL_IMPORT_S`. PowerShell: SQL Server works without driver, PostgreSQL, MySQL and Oracle need the ODBC driver of the database. Python: `psycopg2` or `psycopg` (PostgreSQL), `pymysql` (MySQL), `oracledb` (Oracle), `pymssql` or `pyodbc` (SQL Server). |
| `Mail`     | Mail-In of BACKUP EAGLE® configured: a mailbox and a backup assignment for the mails. The mails are recognized by the generic classification "Generic_Collector". An SMTP server that accepts the mails of the copy job. |

### 3. Credentials

Never put passwords into the scheduled task or cron job in plain text.

- Windows: store the credentials once, as the Windows user that runs the scheduled task. The file can only be read by this user on this computer.

  ```powershell
  Get-Credential | Export-Clixml C:\scripts\be_cred.xml      # -CredentialFile     (REST)
  Get-Credential | Export-Clixml C:\scripts\db_cred.xml      # -DbCredentialFile   (database, alternatively Windows authentication for SQL Server)
  Get-Credential | Export-Clixml C:\scripts\smtp_cred.xml    # -SmtpCredentialFile (mail)
  ```

- Linux: environment variables, e.g. read from a file that only the job user can read: `BACKUP_EAGLE_PASSWORD` (REST), `BACKUP_EAGLE_DB_PASSWORD` (database), `BACKUP_EAGLE_SMTP_PASSWORD` (mail).

### 4. Scheduled task or cron job

Replace the copy command by the wrapper. With `powershell.exe -File` lists cannot be passed, so pass the options as one string (`-Options "/MIR /R:3 /W:10"`).

## Examples

### Windows (robocopy, xcopy)

```powershell
# REST API
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options "/MIR /R:3 /W:10" -JobName DATA_TO_NAS -BaServer COPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -CredentialFile C:\scripts\be_cred.xml

# BACKUP EAGLE database on SQL Server (Windows authentication of the task user)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer COPY_JOBS -Delivery Database -DbType SqlServer -DbConnectionString "Server=dbhost;Database=backupeagle;Integrated Security=true"

# BACKUP EAGLE database on PostgreSQL (psqlODBC driver)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer COPY_JOBS -Delivery Database -DbType PostgreSQL -DbConnectionString "Driver={PostgreSQL Unicode(x64)};Server=dbhost;Port=5432;Database=backupeagle" -DbCredentialFile C:\scripts\db_cred.xml

# Mail (STARTTLS on port 587)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer COPY_JOBS -Delivery Mail -SmtpServer smtp.example.com -SmtpPort 587 -SmtpUseSsl -SmtpCredentialFile C:\scripts\smtp_cred.xml -MailFrom fileserver01@example.com -MailTo backupeagle-mailin@example.com

# Test: run the copy and only show the result (or the mail) that would be sent
.\monitorRobocopy.ps1 -Source D:\Data -Destination E:\Backup\Data -JobName TEST -BaServer COPY_JOBS -Delivery Mail -ShowResultOnly
```

Connection strings for `-DbConnectionString`:

| Database   | Example                                                                                  |
| ---------- | ---------------------------------------------------------------------------------------- |
| SQL Server | `Server=dbhost,1433;Database=backupeagle;Integrated Security=true` (no driver required)   |
| PostgreSQL | `Driver={PostgreSQL Unicode(x64)};Server=dbhost;Port=5432;Database=backupeagle`           |
| MySQL      | `Driver={MySQL ODBC 9.1 Unicode Driver};Server=dbhost;Port=3306;Database=backupeagle`     |
| Oracle     | `Driver={Oracle in instantclient_23};Dbq=dbhost:1521/ORCL`                                |

All parameters with description: `Get-Help .\monitorRobocopy.ps1 -Full`

### Linux (rsync)

The rsync arguments follow after `--`.

```console
# REST API
BACKUP_EAGLE_PASSWORD="$(cat /root/.be_password)" python3 monitorRsync.py --host="192.168.0.1" --user="rsync_monitor" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a --delete /data/ nas01:/backup/data/

# BACKUP EAGLE database on PostgreSQL
BACKUP_EAGLE_DB_PASSWORD="$(cat /root/.be_db_password)" python3 monitorRsync.py --delivery=database --db-type=postgresql --db-host="dbhost" --db-name="backupeagle" --db-user="be_import" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a /data/ nas01:/backup/data/

# Mail (STARTTLS on port 587)
BACKUP_EAGLE_SMTP_PASSWORD="$(cat /root/.smtp_password)" python3 monitorRsync.py --delivery=mail --smtp-server="smtp.example.com" --smtp-port=587 --smtp-starttls=True --smtp-user="linux01@example.com" --mail-from="linux01@example.com" --mail-to="backupeagle-mailin@example.com" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a /data/ nas01:/backup/data/

# cron job (daily at 01:30), output appended to a log file
30 1 * * * BACKUP_EAGLE_PASSWORD="$(cat /root/.be_password)" /usr/bin/python3 /opt/scripts/monitorRsync.py --host="192.168.0.1" --user="rsync_monitor" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a --delete /data/ nas01:/backup/data/ >> /var/log/rsync_data.log 2>&1

# Test: run rsync and only show the result that would be sent
python3 monitorRsync.py --job-name="TEST" --ba-server="COPY_JOBS" --show-result-only=True -- -a /data/ /backup/data/
```

All options with description: `python3 monitorRsync.py --help`

## Common parameters

| PowerShell                 | Python                    | Description                                                                 |
| -------------------------- | ------------------------- | --------------------------------------------------------------------------- |
| `-JobName`                 | `--job-name`              | Name of the copy job, shown as schedule/job in BACKUP EAGLE® (required)     |
| `-BaServer`                | `--ba-server`             | Name of the backup server of type "Generic" in BACKUP EAGLE® (required)     |
| `-NodeName`                | `--node-name`             | Node name, default: name of this computer                                   |
| `-NodeGroup`               | `--node-group`            | Node group (domain), default: ROBOCOPY / XCOPY / RSYNC                       |
| `-ObjectName`              | `--object-name`           | Name of the backed up object, default: the source                           |
| `-MaxMessageLines`         | `--max-message-lines`     | Maximum number of error lines sent, default: 50                             |
| `-ShowResultOnly`          | `--show-result-only=True` | Run the copy, only print the result instead of sending it                   |
| `-Delivery`                | `--delivery`              | `Rest` (default), `Database` or `Mail`                                       |

## Exit codes

| Exit code | Meaning                                                                               |
| --------- | ------------------------------------------------------------------------------------- |
| 0         | Copy successful, result delivered                                                     |
| 1         | Delivery failed, the result is **not** in BACKUP EAGLE® (if activated, the Non-started detection reports the missing result) |
| 2         | General error, e.g. invalid or missing parameters (checked before the copy runs)      |
| 3         | Copy failed, result delivered                                                         |

## Notes

- **Start and end time:** with `Database` the times are written in the local time of the computer running the copy job, it should use the time zone of the BACKUP EAGLE® server. With `Mail` the Mail-In uses the time the mail was sent as start and end time of the result; the real start and end time are part of the messages.
- **Length limits:** names are cut at 255 characters and messages at 1024 characters (column sizes of the import tables).
- **SQL Server:** the import tables use `varchar`, characters outside the code page of the database are replaced.
- **Mail:** the PowerShell wrappers support STARTTLS (`-SmtpUseSsl`, e.g. port 587) but not implicit TLS on port 465. The Python wrapper supports both (`--smtp-starttls=True`, `--smtp-ssl=True`). Node and job names are shown in lower case for results received via Mail-In.
- **xcopy:** Microsoft recommends robocopy instead of xcopy. robocopy provides more statistics (bytes, failed files) and retries locked files.
- The PowerShell wrappers are tested with Windows PowerShell 5.1, the Python wrapper with Python 3.
