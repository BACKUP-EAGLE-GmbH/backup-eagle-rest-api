[![BACKUP EAGLE Logo](https://images.schmitz-rz-consult.de/github/logo_backupeagle.png)](https://www.backup-eagle.com/)

# BACKUP EAGLE® REST API examples
BACKUP EAGLE® REST API examples for PowerShell (Windows) and Python (Linux).

## About BACKUP EAGLE®
BACKUP EAGLE® is a reporting and monitoring solution that monitors and documents your entire backup environment without any additional manual effort.

BACKUP EAGLE® supports various backup systems such as IBM Spectrum Protect, IBM Spectrum Protect Plus, Veeam, DELL EMC NetWorker, IBM BRMS, Microsoft Azure Backup, SEP sesam, Rubrik, dsmISI MAGS, dsmISI Storage, dsmISI Veeam, Oracle RMAN, UC4 / CA Automatic Workload, BMC Control-M, DELL EMC Data Domain, IBM Tape Library, DELL EMC Isilon, DELL EMC PowerProtect Data Manager, Commvault, Cohesity, VMware vCenter and others.

The dashboard provides you with all the essential information on the status of your backup environment in a clear and concise manner. You can see at a glance whether there is still enough storage capacity, whether the backups have run reliably or whether there have been problems during a backup.

For more information visit <a href="https://www.backup-eagle.com/" target="_blank">www.backup-eagle.com</a>.

## Content

Here are the assignments of the individual topics to the sample folders:

| Topic                              | Folder                             |
| ---------------------------------- | ---------------------------------- |
| Backup & restore results           | backup_and_restore_results         |
| Connection test to the REST API    | connection_test                    |
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

Every example exists twice with the same name and the same function:

- `*.ps1`: PowerShell script, use it on **Windows**
- `*.py`: Python script, use it on **Linux**

`server_devices/updateDatasourceCredentials.*` sets a password (client, https, ssh, smb, token or SNMPv3) of all data sources matching a name pattern.

The REST server has to be activated in BACKUP EAGLE® (`rest_server_active=true`, default port 10987).

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

---

## Copyright

© BACKUP EAGLE GmbH 2026

Visit <a href="https://www.backup-eagle.com/" target="_blank">www.backup-eagle.com</a> for more information.

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/company/schmitz-rz-consult-gmbh/)
[![YouTube](https://img.shields.io/badge/YouTube-%23FF0000.svg?style=for-the-badge&logo=YouTube&logoColor=white)](https://www.youtube.com/user/BACKUPEAGLE)
