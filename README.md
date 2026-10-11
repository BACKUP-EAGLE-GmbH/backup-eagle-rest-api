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

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://de.linkedin.com/company/backup-eagle)
[![YouTube](https://img.shields.io/badge/YouTube-%23FF0000.svg?style=for-the-badge&logo=YouTube&logoColor=white)](https://www.youtube.com/user/BACKUPEAGLE)
