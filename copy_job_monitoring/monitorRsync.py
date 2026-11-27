#######################################################################################################
#
# Python Example - Run an rsync job and report its result to BACKUP EAGLE (REST API, database or Mail-In)
# (C) BACKUP EAGLE GmbH
#
# Wrapper for rsync based copy and backup jobs (e.g. as cron job):
#   1. Runs rsync with the arguments given after "--" (--stats is added if missing).
#   2. Evaluates the exit code and the statistics (files, bytes) and collects the error messages.
#   3. Delivers the result with all error messages to BACKUP EAGLE (--delivery):
#        rest      POST /api/rest/genericbackup/import-baresult (default)
#        database  INSERT into the import tables BA_RESULT_IMPORT / BA_RESULT_DETAIL_IMPORT of the BACKUP EAGLE
#                  database. Result and messages are inserted in one transaction, so BACKUP EAGLE never imports
#                  a result without its messages.
#        mail      mail for the generic Mail-In of BACKUP EAGLE ("Node name:", "Job name:", ...). Every error
#                  message is sent as a line "ERROR: ...", so it becomes an error message of the result.
#
# The result appears in BACKUP EAGLE like a result of any other backup software (Client Control, reports,
# dashboards, alerts). With the "Non-started detection" (Report missing backups) BACKUP EAGLE additionally
# alerts if no result arrives at all, e.g. because the cron job was removed or the server was down.
#
# Requirements in BACKUP EAGLE:
#   - A backup server of the type "Generic" whose name is passed as --ba-server.
#   - rest: REST server activated under Configuration > Settings > REST > Rest server active (default port 10987),
#     the change requires a restart of the BACKUP EAGLE server service. A user with the role admin or cc_admin.
#   - database: a database user with INSERT rights on BA_RESULT_IMPORT and BA_RESULT_DETAIL_IMPORT (and the
#     sequences BA_RESULT_IMPORT_S / BA_RESULT_DETAIL_IMPORT_S on PostgreSQL/Oracle) and the Python driver:
#     postgresql: psycopg2 or psycopg (apt install python3-psycopg2), mysql: pymysql (apt install python3-pymysql),
#     oracle: oracledb (pip install oracledb), sqlserver: pymssql or pyodbc with the Microsoft ODBC driver.
#   - mail: Mail-In configured (mailbox and a backup assignment for the sender/recipient of the mails).
#
# Rsync exit codes:
#   0   success                                              -> result OK (RC 0)
#   24  partial transfer due to vanished source files        -> result OK (RC 0) with info lines,
#       (files deleted during the run, e.g. temporary files)    failed with --vanished-is-error=True
#   all other exit codes                                     -> result failed (RC 8)
#
# Passwords can be passed as option or in environment variables (recommended for cron jobs, e.g. read from a file
# that only the job user can read): BACKUP_EAGLE_PASSWORD (REST), BACKUP_EAGLE_DB_PASSWORD (database),
# BACKUP_EAGLE_SMTP_PASSWORD (mail). A missing REST password is prompted in an interactive terminal.
#
# Example usage (REST API):
# python3 monitorRsync.py --host="192.168.0.1" --user="admin" --password="admin" --job-name="DATA_TO_NAS" --ba-server="RSYNC_JOBS" -- -a --delete /data/ nas01:/backup/data/
#
# Example usage in a cron job (REST API, password from a file that only the job user can read):
# 30 1 * * * BACKUP_EAGLE_PASSWORD="$(cat /root/.be_password)" /usr/bin/python3 /opt/scripts/monitorRsync.py --host="192.168.0.1" --user="rsync_monitor" --job-name="DATA_TO_NAS" --ba-server="RSYNC_JOBS" -- -a --delete /data/ nas01:/backup/data/ >> /var/log/rsync_data.log 2>&1
#
# Example usage (BACKUP EAGLE database on PostgreSQL):
# BACKUP_EAGLE_DB_PASSWORD="$(cat /root/.be_db_password)" python3 monitorRsync.py --delivery=database --db-type=postgresql --db-host="dbhost" --db-name="backupeagle" --db-user="be_import" --job-name="DATA_TO_NAS" --ba-server="RSYNC_JOBS" -- -a /data/ nas01:/backup/data/
#
# Example usage (mail to the Mail-In mailbox of BACKUP EAGLE):
# python3 monitorRsync.py --delivery=mail --smtp-server="smtp.example.com" --smtp-port=587 --smtp-starttls=True --smtp-user="linux01@example.com" --mail-from="linux01@example.com" --mail-to="backupeagle-mailin@example.com" --job-name="DATA_TO_NAS" --ba-server="RSYNC_JOBS" -- -a /data/ nas01:/backup/data/
#
# Example usage for testing (runs rsync, prints the result or the mail instead of sending it):
# python3 monitorRsync.py --job-name="TEST" --ba-server="RSYNC_JOBS" --show-result-only=True -- -a /data/ /backup/data/
#
# Exit code 0: copy successful and result sent, 1: delivery failed (result NOT in BACKUP EAGLE),
# 2: general error (e.g. invalid input), 3: copy failed and result sent.
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import os
import re
import json
import time
import socket
import getpass
import smtplib
import datetime
import threading
import subprocess
from email.message import EmailMessage
from email.utils import formatdate, make_msgid

# meaning of the rsync exit codes (see man rsync)
RSYNC_EXIT_CODES = {
    0: "Success.",
    1: "Syntax or usage error.",
    2: "Protocol incompatibility.",
    3: "Errors selecting input/output files, dirs.",
    4: "Requested action not supported.",
    5: "Error starting client-server protocol.",
    6: "Daemon unable to append to log-file.",
    10: "Error in socket I/O.",
    11: "Error in file I/O.",
    12: "Error in rsync protocol data stream.",
    13: "Errors with program diagnostics.",
    14: "Error in IPC code.",
    20: "Received SIGUSR1 or SIGINT.",
    21: "Some error returned by waitpid().",
    22: "Error allocating core memory buffers.",
    23: "Partial transfer due to error.",
    24: "Partial transfer due to vanished source files.",
    25: "The --max-delete limit stopped deletions.",
    30: "Timeout in data send/receive.",
    35: "Timeout waiting for daemon connection.",
}

# rsync --stats lines that are evaluated: (regex, key)
STATS_PATTERNS = [
    (re.compile(r"^Number of files:\s*(\S+)"), "files"),
    (re.compile(r"^Number of (?:regular )?files transferred:\s*(\S+)"), "filesTransferred"),
    (re.compile(r"^Number of deleted files:\s*(\S+)"), "filesDeleted"),
    (re.compile(r"^Total file size:\s*(\S+)"), "totalSize"),
    (re.compile(r"^Total transferred file size:\s*(\S+)"), "transferredSize"),
    (re.compile(r"^Total bytes sent:\s*(\S+)"), "bytesSent"),
    (re.compile(r"^Total bytes received:\s*(\S+)"), "bytesReceived"),
]

# result field -> column of BA_RESULT_IMPORT (only filled fields are inserted)
IMPORT_COLUMNS = [
    ("objectName", "bari_object_name"),
    ("projectName", "bari_project_name"),
    ("startTime", "bari_start_time"),
    ("endTime", "bari_end_time"),
    ("baNode", "bari_node"),
    ("baServer", "bari_server"),
    ("baNodeGroup", "bari_nodegroup"),
    ("rc", "bari_rc"),
    ("bytes", "bari_bytes"),
    ("bytesInspected", "bari_bytes_inspected"),
    ("transferRate", "bari_transfer_rate"),
    ("objectsInspected", "bari_objects_inspected"),
    ("objectsBackedUp", "bari_objects_backed_up"),
    ("objectsDeleted", "bari_objects_deleted"),
    ("transferredSize", "bari_transferredSize"),
    ("backupState", "bari_backupState"),
    ("backupType", "bari_backupType"),
    ("objectType", "bari_objectType"),
]

DEFAULT_DB_PORTS = {"postgresql": 5432, "mysql": 3306, "oracle": 1521, "sqlserver": 1433}

parser = OptionParser(usage="%prog [options] -- <rsync arguments>")
parser.add_option("--job-name", dest="jobName", help="Name of the copy job, shown as schedule/project in BACKUP EAGLE (example: DATA_TO_NAS)")
parser.add_option("--ba-server", dest="baServer", help="Name of the backup server of type \"Generic\" in BACKUP EAGLE the result is assigned to")
parser.add_option("--node-name", dest="nodeName", default=socket.gethostname().split(".")[0], help="Node name in BACKUP EAGLE (default: short host name of this computer)")
parser.add_option("--node-group", dest="nodeGroup", default="RSYNC", help="Node group (domain) in BACKUP EAGLE (default: RSYNC)")
parser.add_option("--object-name", dest="objectName", help="Name of the backed up object (default: the last source of the rsync command)")
parser.add_option("--rsync-binary", dest="rsyncBinary", default="rsync", help="rsync program (default: rsync)")
parser.add_option("--vanished-is-error", dest="vanishedIsError", default=False, help="Treat exit code 24 (vanished source files) as error (default: false)")
parser.add_option("--max-message-lines", dest="maxMessageLines", type="int", default=50, help="Maximum number of error lines sent to BACKUP EAGLE (default: 50)")
parser.add_option("--show-result-only", dest="showResultOnly", default=False, help="Run rsync, but only print the result (or the mail) instead of sending it (default: false)")
parser.add_option("--delivery", dest="delivery", default="rest", help="How the result is delivered: rest (default), database or mail")
parser.add_option("--timeout", dest="timeout", type="int", default=60, help="Timeout of the REST call, database connection or SMTP connection in seconds (default: 60)")
# REST API
parser.add_option("--host", dest="host", help="rest: BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--port", dest="port", type="int", default=10987, help="rest: BACKUP EAGLE REST port (default: 10987)")
parser.add_option("--base-url", dest="baseUrl", help="rest: Base URL of the REST API, overrides --host/--port (default: https://<host>:<port>/api/rest)")
parser.add_option("--user", dest="username", help="rest: BACKUP EAGLE username")
parser.add_option("--password", dest="password", help="rest: BACKUP EAGLE password. Default: environment variable BACKUP_EAGLE_PASSWORD, prompted if not set.")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="rest: Verify SSL certificate of connection (default: false)")
# database
parser.add_option("--db-type", dest="dbType", help="database: type of the BACKUP EAGLE database: postgresql, mysql, oracle or sqlserver")
parser.add_option("--db-host", dest="dbHost", help="database: database host")
parser.add_option("--db-port", dest="dbPort", type="int", help="database: database port (default: 5432 / 3306 / 1521 / 1433)")
parser.add_option("--db-name", dest="dbName", help="database: database name (Oracle: service name)")
parser.add_option("--db-user", dest="dbUser", help="database: database user")
parser.add_option("--db-password", dest="dbPassword", help="database: password of the database user. Default: environment variable BACKUP_EAGLE_DB_PASSWORD")
parser.add_option("--db-odbc-driver", dest="dbOdbcDriver", default="ODBC Driver 18 for SQL Server", help="database: ODBC driver for sqlserver if pyodbc is used (default: ODBC Driver 18 for SQL Server)")
# mail
parser.add_option("--smtp-server", dest="smtpServer", help="mail: SMTP server")
parser.add_option("--smtp-port", dest="smtpPort", type="int", help="mail: SMTP port (default: 25, 465 with --smtp-ssl=True)")
parser.add_option("--smtp-starttls", dest="smtpStarttls", default=False, help="mail: use STARTTLS, e.g. port 587 (default: false)")
parser.add_option("--smtp-ssl", dest="smtpSsl", default=False, help="mail: use implicit TLS, e.g. port 465 (default: false)")
parser.add_option("--smtp-user", dest="smtpUser", help="mail: SMTP user (default: no authentication)")
parser.add_option("--smtp-password", dest="smtpPassword", help="mail: SMTP password. Default: environment variable BACKUP_EAGLE_SMTP_PASSWORD")
parser.add_option("--mail-from", dest="mailFrom", help="mail: sender address")
parser.add_option("--mail-to", dest="mailTo", help="mail: recipient address(es), comma separated: the mailbox read by the Mail-In of BACKUP EAGLE")

(options, rsyncArgs) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"
options.vanishedIsError = str(options.vanishedIsError).lower() == "true"
options.showResultOnly = str(options.showResultOnly).lower() == "true"
options.smtpStarttls = str(options.smtpStarttls).lower() == "true"
options.smtpSsl = str(options.smtpSsl).lower() == "true"
options.delivery = str(options.delivery).lower()
options.dbType = (options.dbType or "").lower()

def fail(message):
    print("ERROR: " + message)
    sys.exit(2)

def validate_input():
    # checks the input before rsync runs, so that a missing value does not show up only after a long running copy
    if(options.jobName is None or options.baServer is None or len(rsyncArgs) == 0):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)
    if(options.delivery not in ("rest", "database", "mail")):
        fail("--delivery must be rest, database or mail.")
    if(options.showResultOnly):
        return
    if(options.delivery == "rest"):
        if((options.host is None and options.baseUrl is None) or options.username is None):
            fail("--host (or --base-url) and --user are required for --delivery=rest.")
        if(options.password is None):
            options.password = os.environ.get("BACKUP_EAGLE_PASSWORD")
        if(options.password is None):
            if(not sys.stdin.isatty()):
                fail("No password given, use --password or the environment variable BACKUP_EAGLE_PASSWORD.")
            options.password = getpass.getpass("BACKUP EAGLE password: ")
    elif(options.delivery == "database"):
        if(options.dbType not in DEFAULT_DB_PORTS):
            fail("--db-type must be postgresql, mysql, oracle or sqlserver for --delivery=database.")
        if(options.dbHost is None or options.dbName is None or options.dbUser is None):
            fail("--db-host, --db-name and --db-user are required for --delivery=database.")
        if(options.dbPassword is None):
            options.dbPassword = os.environ.get("BACKUP_EAGLE_DB_PASSWORD")
        if(options.dbPassword is None):
            fail("No database password given, use --db-password or the environment variable BACKUP_EAGLE_DB_PASSWORD.")
        if(options.dbPort is None):
            options.dbPort = DEFAULT_DB_PORTS[options.dbType]
        # load the driver now: a missing driver must not show up only after the copy
        load_db_driver()
    elif(options.delivery == "mail"):
        if(options.smtpServer is None or options.mailFrom is None or options.mailTo is None):
            fail("--smtp-server, --mail-from and --mail-to are required for --delivery=mail.")
        if(options.smtpUser is not None and options.smtpPassword is None):
            options.smtpPassword = os.environ.get("BACKUP_EAGLE_SMTP_PASSWORD")
            if(options.smtpPassword is None):
                fail("No SMTP password given, use --smtp-password or the environment variable BACKUP_EAGLE_SMTP_PASSWORD.")
        if(options.smtpPort is None):
            options.smtpPort = 465 if options.smtpSsl else 25

def default_object_name(args):
    # rsync [OPTIONS] SRC... DEST: the argument before the destination is the last source
    if(len(args) >= 2 and not args[-2].startswith("-")):
        return args[-2].rstrip("/") or "/"
    return options.jobName

def parse_number(text):
    # "1,234,567" / "1.234.567" (separators depend on locale) or "1.23M" (--human-readable, units of 1000)
    m = re.match(r"^([\d.,']+)([KMGTP]?)", text)
    if(m is None):
        return None
    number, unit = m.group(1), m.group(2)
    if(unit):
        number = number.replace("'", "").replace(",", ".")
        if(number.count(".") > 1):
            number = number.replace(".", "", number.count(".") - 1)
        try:
            return int(float(number) * (1000 ** ("KMGTP".index(unit) + 1)))
        except ValueError:
            return None
    digits = re.sub(r"\D", "", number)
    return int(digits) if digits else None

def read_stream(stream, target, echo):
    # reads the output line by line (UTF-8, invalid bytes are replaced) and prints it
    for raw in iter(stream.readline, b""):
        line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
        echo.write(line + "\n")
        echo.flush()
        target.append(line)
    stream.close()

def run_rsync(args):
    # returns (exit code, stdout lines, stderr lines); stdout and stderr are read in parallel (no deadlock)
    stdoutLines = []
    stderrLines = []
    process = subprocess.Popen([options.rsyncBinary] + args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    threads = [
        threading.Thread(target=read_stream, args=(process.stdout, stdoutLines, sys.stdout)),
        threading.Thread(target=read_stream, args=(process.stderr, stderrLines, sys.stderr)),
    ]
    for t in threads:
        t.start()
    exitCode = process.wait()
    for t in threads:
        t.join()
    return exitCode, stdoutLines, stderrLines

def parse_stats(lines):
    stats = {}
    for line in lines:
        for pattern, key in STATS_PATTERNS:
            m = pattern.match(line.strip())
            if(m):
                value = parse_number(m.group(1))
                if(value is not None):
                    stats[key] = value
    return stats

def quote_argument(arg):
    return "'" + arg.replace("'", "'\\''") + "'" if re.search(r"[\s'\"$`\\]", arg) else arg

# ---------------------------------------------------------------------------------------------------
# delivery: REST API
# ---------------------------------------------------------------------------------------------------

def send_rest(result):
    import requests
    if(options.baseUrl):
        baseUrl = options.baseUrl.rstrip("/") + "/"
    else:
        baseUrl = "https://" + options.host + ":" + str(options.port) + "/api/rest/"
    session = requests.Session()
    session.auth = (options.username, options.password)
    try:
        r = session.post(baseUrl + "genericbackup/import-baresult", verify=options.verifySSL, json=result, headers={'Content-Type': 'application/json'}, timeout=options.timeout)
    except requests.exceptions.RequestException as e:
        raise RuntimeError(str(e))
    if(not r.ok):
        raise RuntimeError(("HTTP " + str(r.status_code) + " " + (r.reason or "") + " " + r.text).strip())
    return baseUrl

# ---------------------------------------------------------------------------------------------------
# delivery: BACKUP EAGLE database
# ---------------------------------------------------------------------------------------------------

def load_db_driver():
    # returns (module, paramstyle) of the first installed driver for the database type
    candidates = {
        "postgresql": ["psycopg2", "psycopg"],
        "mysql": ["pymysql", "mysql.connector"],
        "oracle": ["oracledb"],
        "sqlserver": ["pymssql", "pyodbc"],
    }[options.dbType]
    import importlib
    for name in candidates:
        try:
            module = importlib.import_module(name)
            return module, name
        except ImportError:
            pass
    fail("No Python driver for %s installed, install one of: %s" % (options.dbType, ", ".join(candidates)))

def db_connect():
    module, name = load_db_driver()
    if(name in ("psycopg2", "psycopg")):
        conn = module.connect(host=options.dbHost, port=options.dbPort, dbname=options.dbName, user=options.dbUser, password=options.dbPassword, connect_timeout=options.timeout)
    elif(name == "pymysql"):
        conn = module.connect(host=options.dbHost, port=options.dbPort, database=options.dbName, user=options.dbUser, password=options.dbPassword, connect_timeout=options.timeout, autocommit=False)
    elif(name == "mysql.connector"):
        conn = module.connect(host=options.dbHost, port=options.dbPort, database=options.dbName, user=options.dbUser, password=options.dbPassword, connection_timeout=options.timeout, autocommit=False)
    elif(name == "oracledb"):
        conn = module.connect(user=options.dbUser, password=options.dbPassword, dsn="%s:%d/%s" % (options.dbHost, options.dbPort, options.dbName))
    elif(name == "pymssql"):
        conn = module.connect(server=options.dbHost, port=str(options.dbPort), database=options.dbName, user=options.dbUser, password=options.dbPassword, login_timeout=options.timeout)
    else:
        conn = module.connect("Driver={%s};Server=%s,%d;Database=%s;UID=%s;PWD={%s};TrustServerCertificate=yes" % (options.dbOdbcDriver, options.dbHost, options.dbPort, options.dbName, options.dbUser, options.dbPassword.replace("}", "}}")), timeout=options.timeout, autocommit=False)
    # paramstyle of the driver: "?" placeholders of the SQL statements are converted to it
    style = getattr(module, "paramstyle", "qmark")
    return conn, style

def to_paramstyle(sql, style):
    if(style in ("format", "pyformat")):
        return sql.replace("?", "%s")
    if(style == "numeric"):
        parts = sql.split("?")
        return parts[0] + "".join(":%d%s" % (i, p) for i, p in enumerate(parts[1:], 1))
    if(style == "named"):
        parts = sql.split("?")
        return parts[0] + "".join(":p%d%s" % (i, p) for i, p in enumerate(parts[1:], 1))
    return sql

def bind(values, style):
    # named paramstyle (oracledb) needs a dict, the others a sequence
    if(style == "named"):
        return {"p%d" % i: v for i, v in enumerate(values, 1)}
    return tuple(values)

def limit_text(text, maxLength):
    # names are varchar(255), messages varchar(1024) in the import tables
    return text if len(text) <= maxLength else text[:maxLength - 3] + "..."

def send_database(result):
    columns = []
    values = []
    for field, column in IMPORT_COLUMNS:
        value = result.get(field)
        if(value is None):
            continue
        if(field in ("startTime", "endTime")):
            # local time of this computer (BACKUP EAGLE stores the local server time)
            value = datetime.datetime.fromtimestamp(value / 1000.0)
        elif(isinstance(value, str)):
            value = limit_text(value, 255)
        columns.append(column)
        values.append(value)
    placeholders = ", ".join(["?"] * len(columns))
    dbType = options.dbType

    conn, style = db_connect()
    try:
        cur = conn.cursor()

        def execute(sql, params=()):
            cur.execute(to_paramstyle(sql, style), bind(params, style))

        # result and messages in one transaction: BACKUP EAGLE must never import the result without its messages
        if(dbType == "postgresql"):
            execute("SELECT nextval('ba_result_import_s')")
            resultId = int(cur.fetchone()[0])
            execute("INSERT INTO BA_RESULT_IMPORT (bari_id, " + ", ".join(columns) + ") VALUES (?, " + placeholders + ")", [resultId] + values)
            detailSql = "INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_id, bardi_value, bardi_type, bari_id) VALUES (nextval('ba_result_detail_import_s'), ?, ?, ?)"
        elif(dbType == "oracle"):
            execute("SELECT BA_RESULT_IMPORT_S.NEXTVAL FROM DUAL")
            resultId = int(cur.fetchone()[0])
            execute("INSERT INTO BA_RESULT_IMPORT (bari_id, " + ", ".join(columns) + ") VALUES (?, " + placeholders + ")", [resultId] + values)
            detailSql = "INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_id, bardi_value, bardi_type, bari_id) VALUES (BA_RESULT_DETAIL_IMPORT_S.NEXTVAL, ?, ?, ?)"
        elif(dbType == "sqlserver"):
            execute("INSERT INTO BA_RESULT_IMPORT (" + ", ".join(columns) + ") OUTPUT INSERTED.bari_id VALUES (" + placeholders + ")", values)
            resultId = int(cur.fetchone()[0])
            detailSql = "INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_value, bardi_type, bari_id) VALUES (?, ?, ?)"
        else:
            execute("INSERT INTO BA_RESULT_IMPORT (" + ", ".join(columns) + ") VALUES (" + placeholders + ")", values)
            execute("SELECT LAST_INSERT_ID()")
            resultId = int(cur.fetchone()[0])
            detailSql = "INSERT INTO BA_RESULT_DETAIL_IMPORT (bardi_value, bardi_type, bari_id) VALUES (?, ?, ?)"
        for baObject in result["baObjects"]:
            execute(detailSql, [limit_text(baObject["value"], 1024), int(baObject["type"]), resultId])
        conn.commit()
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    finally:
        conn.close()
    return "%s database (BA_RESULT_IMPORT id %d)" % (dbType, resultId)

# ---------------------------------------------------------------------------------------------------
# delivery: Mail-In
# ---------------------------------------------------------------------------------------------------

def format_byte_amount(value):
    # format understood by the Mail-In parser, e.g. "1.53 GB" (units of 1024, decimal point)
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    amount = float(value)
    unit = 0
    while(amount >= 1024 and unit < len(units) - 1):
        amount /= 1024
        unit += 1
    return ("%.3f" % amount).rstrip("0").rstrip(".") + " " + units[unit]

def build_mail(result):
    # Mail for the generic Mail-In parser of BACKUP EAGLE (classification "Generic_Collector"):
    #   Node name / Job name / Domain name / Backup server / Amount are evaluated as fields of the result.
    #   Every line of the mail becomes a message of the result, lines with error|fehler|warning|warnung|failed are errors.
    #   "Backup successful" sets the result to OK and all lines to info (also e.g. a warning of a successful run).
    failed = result["rc"] != 0
    subject = "BACKUP EAGLE copy job %s on %s: %s" % (result["projectName"], result["baNode"], "FAILED" if failed else "OK")
    lines = [
        "Node name: " + result["baNode"],
        "Job name: " + result["projectName"],
        "Domain name: " + result["baNodeGroup"],
        "Backup server: " + result["baServer"],
    ]
    if(result.get("bytes") is not None):
        lines.append("Amount: " + format_byte_amount(result["bytes"]))
    lines.append("Status: copy job FAILED" if failed else "Status: Backup successful")
    lines.append("Object: " + result["objectName"])
    lines.append("Start time: " + datetime.datetime.fromtimestamp(result["startTime"] / 1000.0).strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("End time: " + datetime.datetime.fromtimestamp(result["endTime"] / 1000.0).strftime("%Y-%m-%d %H:%M:%S"))
    for baObject in result["baObjects"]:
        # line breaks would split a message into several lines
        text = re.sub(r"[\r\n]+", " ", baObject["value"])
        lines.append(("ERROR: " + text) if baObject["type"] > 0 else text)
    return subject, "\n".join(lines) + "\n"

def send_mail(result):
    subject, body = build_mail(result)
    recipients = [a.strip() for a in re.split(r"[,;]", options.mailTo) if a.strip()]
    message = EmailMessage()
    message["From"] = options.mailFrom
    message["To"] = ", ".join(recipients)
    message["Subject"] = subject
    message["Date"] = formatdate(localtime=True)
    message["Message-ID"] = make_msgid()
    message.set_content(body, charset="utf-8")
    if(options.smtpSsl):
        smtp = smtplib.SMTP_SSL(options.smtpServer, options.smtpPort, timeout=options.timeout)
    else:
        smtp = smtplib.SMTP(options.smtpServer, options.smtpPort, timeout=options.timeout)
    try:
        if(options.smtpStarttls):
            smtp.starttls()
        if(options.smtpUser):
            smtp.login(options.smtpUser, options.smtpPassword)
        smtp.send_message(message, from_addr=options.mailFrom, to_addrs=recipients)
    finally:
        try:
            smtp.quit()
        except Exception:
            pass
    return "mail to %s via %s" % (", ".join(recipients), options.smtpServer)

# ---------------------------------------------------------------------------------------------------

def main():
    args = list(rsyncArgs)
    if("--stats" not in args):
        args.append("--stats")
    objectName = options.objectName or default_object_name(rsyncArgs)
    baObjects = [{"value": "Command: " + " ".join(quote_argument(a) for a in [options.rsyncBinary] + args), "type": 0}]

    # --- run rsync ---
    startTime = int(time.time() * 1000)
    try:
        exitCode, stdoutLines, stderrLines = run_rsync(args)
    except OSError as e:
        # e.g. rsync not installed
        exitCode, stdoutLines, stderrLines = -1, [], ["rsync could not be started: " + str(e)]
        print(stderrLines[0])
    endTime = int(time.time() * 1000)

    # --- evaluate ---
    failed = exitCode != 0 and not (exitCode == 24 and not options.vanishedIsError)
    rc = 8 if failed else 0
    if(exitCode == -1):
        baObjects.append({"value": "Rsync could not be started.", "type": rc})
    else:
        baObjects.append({"value": "Rsync exit code %d: %s" % (exitCode, RSYNC_EXIT_CODES.get(exitCode, "Unknown exit code.")), "type": rc})

    stats = parse_stats(stdoutLines)
    if(stats):
        baObjects.append({"value": "Files: total %s, transferred %s, deleted %s" % (stats.get("files", "-"), stats.get("filesTransferred", "-"), stats.get("filesDeleted", "-")), "type": 0})
        baObjects.append({"value": "Bytes: total file size %s, transferred file size %s, sent %s, received %s" % (stats.get("totalSize", "-"), stats.get("transferredSize", "-"), stats.get("bytesSent", "-"), stats.get("bytesReceived", "-")), "type": 0})

    # error messages (stderr), each message only once; warnings of a successful run (exit code 24) are info
    errorLines = []
    for line in stderrLines:
        line = line.strip()
        if(line and line not in errorLines):
            errorLines.append(line)
    if(failed and len(errorLines) == 0):
        errorLines = [line.strip() for line in stdoutLines if line.strip()][-10:]
    errorType = 8 if failed else 0
    for i, line in enumerate(errorLines):
        if(i >= options.maxMessageLines):
            baObjects.append({"value": "... %d more error lines, see the rsync output" % (len(errorLines) - options.maxMessageLines), "type": errorType})
            break
        baObjects.append({"value": line, "type": errorType})

    # --- build result ---
    result = {
        "projectName": options.jobName,
        "baServer": options.baServer,
        "baNodeGroup": options.nodeGroup,
        "baNode": options.nodeName,
        "objectName": objectName,
        "startTime": startTime,
        "endTime": endTime,
        "rc": rc,
        "backupState": "Failed" if failed else "Success",
        "backupType": "Rsync",
        "objectType": "Directory",
        "baObjects": baObjects,
    }
    durationSec = max(1, (endTime - startTime) // 1000)
    if("transferredSize" in stats):
        result["bytes"] = stats["transferredSize"]
        result["transferRate"] = stats["transferredSize"] // durationSec
    if("totalSize" in stats):
        result["bytesInspected"] = stats["totalSize"]
    if("bytesSent" in stats or "bytesReceived" in stats):
        result["transferredSize"] = stats.get("bytesSent", 0) + stats.get("bytesReceived", 0)
    if("files" in stats):
        result["objectsInspected"] = stats["files"]
    if("filesTransferred" in stats):
        result["objectsBackedUp"] = stats["filesTransferred"]
    if("filesDeleted" in stats):
        result["objectsDeleted"] = stats["filesDeleted"]

    if(options.showResultOnly):
        if(options.delivery == "mail"):
            subject, body = build_mail(result)
            print("Subject: " + subject + "\n\n" + body)
        else:
            print(json.dumps(result, indent=4, ensure_ascii=False))
        sys.exit(3 if failed else 0)

    # --- deliver result ---
    print("Delivering result (%s) ..." % options.delivery)
    try:
        if(options.delivery == "database"):
            target = send_database(result)
        elif(options.delivery == "mail"):
            target = send_mail(result)
        else:
            target = send_rest(result)
    except Exception as e:
        print("FAILED: %s" % e)
        sys.exit(1)
    print("Result delivered to %s: %s" % (target, "copy FAILED (RC 8)" if failed else "copy OK (RC 0)"))
    sys.exit(3 if failed else 0)

validate_input()
main()
