# BACKUP EAGLE® REST API examples

BACKUP EAGLE® can be automated and queried via its REST API. This allows you to integrate BACKUP EAGLE® into your own tools and workflows, for example to retrieve backup and restore results, manage users, groups and reports, or import backup results from other sources.

To make getting started as easy as possible, this repository provides sample scripts for the various REST API endpoints, each available for PowerShell (Windows) and Python (Linux).

## About BACKUP EAGLE®

BACKUP EAGLE® is a vendor-agnostic backup monitoring, reporting, audit and compliance solution for on-premises and cloud environments. It monitors and documents your entire backup environment without any additional manual effort and automatically provides the evidence required for audits and regulations such as NIS-2 and DORA.

BACKUP EAGLE® is available in two editions: BACKUP EAGLE® Enterprise (local installation) and BACKUP EAGLE® Cloud (hosted in Germany, designed for managed service providers).

Supported backup software:

- Acronis Cyber Protect Cloud, Arcserve ShadowProtect SPX, Arctera/Veritas Backup Exec, AvePoint, Cohesity, Commvault, Commvault Metallic, Datto SaaS Protection, Dell EMC Avamar, Dell EMC NetWorker, Dell EMC PowerProtect Data Manager, ELOVADE BackupAssist, General Storage MAGS and Cluster Controller, IBM BRMS, IBM Storage Defender, IBM Storage Protect, IBM Storage Protect Plus, IBM Storage Protect Online Services, m.ax.it Max Backup, Microsoft Azure Backup, N2W, N-able MaxBackup, OpenText MailStore, Oracle RMAN (incl. RMAN catalog), Proxmox Backup Server, Rubrik, SEP sesam, Synology Active Backup, Synology Hyper Backup, Veeam Backup & Replication, Veeam Backup Enterprise Manager, Veeam Backup for Google Cloud, Veeam Backup for Microsoft Azure, Veeam Backup for Microsoft 365, Veeam ONE, Veeam Service Provider Console, Veritas NetBackup, Wortmann TERRA CLOUD Backup
- Cloud platforms: Amazon Web Services, Oracle Cloud Infrastructure
- Custom backup results interface for any other backup tool

Supported storage devices:

- Dell EMC Data Domain, Dell EMC ECS, IBM Tape Libraries (33xx, 35xx, 43xx, 45xx), NetApp, Spectra Logic, Synology

Additional integrations:

- Hyper-V, Proxmox VE, VMware vCenter, Datto PSA

The dashboard provides all essential information on the status of your backup environment at a glance: whether there is still enough storage capacity, whether all backups have run reliably and whether there have been any problems.

For more information visit [www.backup-eagle.com](https://www.backup-eagle.com/).

## Overview

Every example exists twice with the same name and the same function:

- `*.ps1`: PowerShell script, use it on **Windows**
- `*.py`: Python script, use it on **Linux**

The REST server is deactivated by default. Activate it in BACKUP EAGLE® under **Configuration > Settings > REST > Rest server active** (default port 10987). The change requires a restart of the BACKUP EAGLE® server service.

The examples are divided into topics. Each topic has its own folder:

| Topic                              | Folder                             |
| ---------------------------------- | ---------------------------------- |
| Backup & restore results           | backup_and_restore_results         |
| Connection test to the REST API    | connection_test                    |
| Monitoring of copy jobs (rsync, robocopy, xcopy) | copy_job_monitoring  |
| Import of backup results           | import_backup_results              |
| Mail management                    | mail_management                    |
| Nodes, Clients, VMs                | nodes_clients_vms                  |
| Projects & schedules               | projects_and_schedules             |
| Report management                  | report_management                  |
| RMAN catalog management            | rman_catalog_management            |
| Server and device group management | server_and_device_group_management |
| Server & devices                   | server_devices                     |
| User defined group management      | user_defined_group_management      |
| User management                    | user_management                    |
| XML, log & csv upload              | xml_log_csv_upload                 |

`server_devices/updateDatasourceCredentials.*` sets a password (client, https, ssh, smb, token or SNMPv3) of all data sources matching a name pattern.

`user_defined_group_management/importNodesToUserDefinedGroup.*` imports node names from a file (one node per line) into a user defined group. The group is created or its entries are replaced, only the node name is filled (as `*<node>*` by default), all other columns are `*`.

### Monitoring of copy jobs (rsync, robocopy, xcopy)

Important data is often copied with rsync, robocopy or xcopy by scheduled tasks or cron jobs. These jobs fail silently: nobody notices a failed copy, and certainly not a copy that did not run at all. The wrapper scripts in `copy_job_monitoring` run the copy tool, evaluate its exit code and output and deliver the result with all error messages to BACKUP EAGLE®. The copy job then appears in BACKUP EAGLE® like a backup of any other backup software, with status, statistics and error messages in Client Control, reports, dashboards and alerts.

The result can be delivered in three ways (`-Delivery` / `--delivery`):

| Delivery            | How                                                                                     | Use when                                                        |
| ------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `Rest` (default)    | `POST genericbackup/import-baresult`                                                    | the copy job can reach the REST API of BACKUP EAGLE®            |
| `Database`          | INSERT into the import tables `BA_RESULT_IMPORT` and `BA_RESULT_DETAIL_IMPORT`           | the REST API is not activated, but the database can be reached  |
| `Mail`              | mail in the format of the generic Mail-In parser to the Mail-In mailbox of BACKUP EAGLE® | the copy job has no direct connection to BACKUP EAGLE® (e.g. DMZ, customer site) |

The error messages are transported on all three ways: as messages of type error (REST, database) or as lines `ERROR: ...` in the mail, which the Mail-In turns into error messages of the result. The database delivery inserts the result and its messages in one transaction, so BACKUP EAGLE® never imports a result without its messages.

| Script                | Platform | Copy tool | Result failed (RC 8) if                                                     |
| --------------------- | -------- | --------- | --------------------------------------------------------------------------- |
| `monitorRobocopy.ps1` | Windows  | robocopy  | exit code 8 or higher (files could not be copied, fatal error)              |
| `monitorXcopy.ps1`    | Windows  | xcopy     | exit code not 0 or any error message (xcopy returns 0 with `/C` despite errors) |
| `monitorRsync.py`     | Linux    | rsync     | exit code not 0 (24 = vanished source files is only a warning by default)    |

Sent are start and end time, status, copied and total bytes, number of files, the command line and the error messages (e.g. locked files, access denied). The scripts only evaluate the language independent parts of the output and work with every system language. The PowerShell wrappers need `BackupEagleDelivery.ps1` in the same folder.

Setup:

1. Create a backup server of the type **Generic** in BACKUP EAGLE® (e.g. `COPY_JOBS`) and pass its name as `-BaServer` / `--ba-server`. Nodes, node groups and jobs are created automatically with the first result.
2. Prepare the delivery:
   - `Rest`: activate the REST server and use a BACKUP EAGLE® user with the role admin or cc_admin.
   - `Database`: a database user with INSERT rights on `BA_RESULT_IMPORT` and `BA_RESULT_DETAIL_IMPORT` (PostgreSQL/Oracle: also on the sequences `BA_RESULT_IMPORT_S` and `BA_RESULT_DETAIL_IMPORT_S`). PowerShell: SQL Server works without driver, PostgreSQL, MySQL and Oracle need the ODBC driver of the database (`-DbConnectionString "Driver={...};..."`). Python: `psycopg2`/`psycopg`, `pymysql`, `oracledb` or `pymssql`/`pyodbc`. The start and end time are written in the local time of the computer running the copy job, it should use the time zone of the BACKUP EAGLE® server.
   - `Mail`: configure the Mail-In of BACKUP EAGLE® (mailbox and a backup assignment for the mails). The mails are recognized by the generic classification "Generic_Collector". As the Mail-In uses the time the mail was sent, start and end time of the result are the send time, the real times are part of the messages.
3. Replace the copy command in the scheduled task or cron job by the wrapper:

```powershell
# Windows: store the password encrypted once (as the user that runs the scheduled task)
Get-Credential | Export-Clixml C:\scripts\be_cred.xml
# scheduled task action
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -Options "/MIR /R:3 /W:10" -JobName DATA_TO_NAS -BaServer COPY_JOBS -BaseUrl https://192.168.0.1:10987/api/rest -CredentialFile C:\scripts\be_cred.xml
```

```powershell
# Windows: delivery into the BACKUP EAGLE database (SQL Server, Windows authentication of the task user)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorRobocopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer COPY_JOBS -Delivery Database -DbType SqlServer -DbConnectionString "Server=dbhost;Database=backupeagle;Integrated Security=true"
# Windows: delivery by mail (SMTP login stored with Export-Clixml like above)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\monitorXcopy.ps1 -Source D:\Data -Destination \\nas01\backup\Data -JobName DATA_TO_NAS -BaServer COPY_JOBS -Delivery Mail -SmtpServer smtp.example.com -SmtpPort 587 -SmtpUseSsl -SmtpCredentialFile C:\scripts\smtp_cred.xml -MailFrom fileserver01@example.com -MailTo backupeagle-mailin@example.com
```

```console
# Linux: rsync arguments after "--", password e.g. from a file that only the job user can read
BACKUP_EAGLE_PASSWORD="$(cat /root/.be_password)" python3 ./copy_job_monitoring/monitorRsync.py --host="192.168.0.1" --user="admin" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a --delete /data/ nas01:/backup/data/
# Linux: delivery into the BACKUP EAGLE database (PostgreSQL)
BACKUP_EAGLE_DB_PASSWORD="$(cat /root/.be_db_password)" python3 ./copy_job_monitoring/monitorRsync.py --delivery=database --db-type=postgresql --db-host="dbhost" --db-name="backupeagle" --db-user="be_import" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a /data/ nas01:/backup/data/
# Linux: delivery by mail
BACKUP_EAGLE_SMTP_PASSWORD="$(cat /root/.smtp_password)" python3 ./copy_job_monitoring/monitorRsync.py --delivery=mail --smtp-server="smtp.example.com" --smtp-port=587 --smtp-starttls=True --smtp-user="linux01@example.com" --mail-from="linux01@example.com" --mail-to="backupeagle-mailin@example.com" --job-name="DATA_TO_NAS" --ba-server="COPY_JOBS" -- -a /data/ nas01:/backup/data/
```

4. Activate the **Non-started detection** (Report missing backups) in BACKUP EAGLE®. It alerts if a job does not deliver a result in the expected interval or time window, e.g. because the scheduled task was deleted, the server was down or the script hangs.

Test a job with `-ShowResultOnly` / `--show-result-only=True`: the copy runs, the result (or the mail for the delivery `Mail`) is only printed instead of sent. Exit codes of the wrappers: 0 copy successful and result sent, 1 delivery failed (result not in BACKUP EAGLE®), 2 general error, 3 copy failed and result sent.

## Usage

### Windows (PowerShell)

#### Requirements

Windows PowerShell 5.1 (included in Windows) or PowerShell 7. No further installation is required.

If the execution of scripts is blocked, allow it for the current session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Scripts downloaded from the internet may additionally have to be unblocked with `Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File`.

#### Example usage

Open a new PowerShell console and insert:

```powershell
.\mail_management\queryMailRecipients.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin -PrettyPrint
```

If `-User` or `-Password` is missing, the script prompts for it in the console. Instead of `-User`/`-Password` a credential object can be passed (both cannot be combined):

```powershell
$cred = Get-Credential
.\mail_management\queryMailRecipients.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -Credential $cred
```

JSON data can be passed as string or as PowerShell object (hashtable):

```powershell
.\server_and_device_group_management\createServerGroup.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin -Group '{"name":"ISP","entries":[{"serverTypePattern":"ISP"}]}'
.\server_and_device_group_management\createServerGroup.ps1 -BaseUrl https://192.168.0.1:10987/api/rest -User admin -Password admin -Group @{ name = 'ISP'; entries = @(@{ serverTypePattern = 'ISP' }) }
```

Get the description, all parameters and an example of a script with `Get-Help`:

```powershell
Get-Help .\mail_management\queryMailRecipients.ps1 -Full
```

Scripts that change data support `-WhatIf` (shows the request without sending it) and `-Confirm`.

Mapping of the common parameters:

| Python                    | PowerShell                                                      |
| ------------------------- | --------------------------------------------------------------- |
| `--host="192.168.0.1"`    | `-BaseUrl https://192.168.0.1:10987/api/rest` (default: localhost) |
| `--user`, `--password`    | `-User`, `-Password` or `-Credential` (prompted if not given)   |
| -                         | `-TimeoutSec 60` (timeout of the REST call, default: 60 seconds) |
| `--verify-ssl=True` (default: no verification) | `-VerifyCertificate` (default: no verification) |
| `--pretty-print=True`     | `-PrettyPrint`                                                  |
| `--group-id="2"` etc.     | `-GroupId 2` etc.                                               |
| `--enable="true"`         | `-Enable $true`                                                 |
| `--file="result.xml"`     | `-Path .\result.xml`                                            |

Exit codes: 0 success, 1 REST call failed, 2 general error (e.g. invalid JSON), 3 upload file does not exist.

### Linux (Python)

#### Requirements

Install Python 3 and the `requests` module via console:

```console
sudo apt-get update
sudo apt-get install python3 python3-requests
```

#### Example usage

Write in the terminal:

```console
python3 ./mail_management/queryMailRecipients.py --host="192.168.0.1" --user="admin" --password="admin" --pretty-print=True
```

## Postman

In addition to the scripts, we provide a collection for <a href="https://www.postman.com/" target="_blank">Postman</a>, so that you can easily use and test REST API requests without writing any code. The collection contains requests for all REST API endpoints, including some that are not covered by the sample scripts (e.g. maintenance windows, license, tenant and credentials management).

The files are located in the folder `postman`:

| File                                          | Content                                                     |
| --------------------------------------------- | ----------------------------------------------------------- |
| `BACKUP_EAGLE_REST_API.postman_collection.json` | Requests for all REST API endpoints, grouped by topic     |
| `BACKUP_EAGLE.postman_environment.json`       | Environment with the variables `baseUrl`, `username` and `password` |

Usage:

1. Import both files in Postman (**File > Import**).
2. Select the environment **BACKUP EAGLE** and set `baseUrl` (e.g. `https://192.168.0.1:10987/api/rest`), `username` and `password` for your BACKUP EAGLE® server.
3. BACKUP EAGLE® uses a self-signed certificate by default. Disable the SSL certificate verification in Postman (**Settings > General > SSL certificate verification**).
4. Send any request of the collection.

---

## Copyright

© BACKUP EAGLE GmbH 2026

Visit <a href="https://www.backup-eagle.com/" target="_blank">www.backup-eagle.com</a> for more information.

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://de.linkedin.com/company/backup-eagle)
[![YouTube](https://img.shields.io/badge/YouTube-%23FF0000.svg?style=for-the-badge&logo=YouTube&logoColor=white)](https://www.youtube.com/user/BACKUPEAGLE)
