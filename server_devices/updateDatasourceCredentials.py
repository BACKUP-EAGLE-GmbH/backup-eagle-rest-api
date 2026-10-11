#######################################################################################################
#
# Python Example - Set a password of all data sources whose name matches a pattern
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Password types (--password-type) and the data sources they apply to:
#   client: client password of ISP data sources
#   https:  password of the REST/HTTPS connection (all data sources)
#   ssh:    SSH password (all data sources)
#   smb:    SMB password of generic data sources
#   token:  REST API token (all data sources)
#   snmpv3: SNMPv3 credentials of devices configured with SNMP version 3
# Data sources that do not support the password type are reported as FAILED by the server.
# Only ACTIVE data sources are returned by the REST API, inactive ones are not changed.
#
# Example usage (list only):
# python updateDatasourceCredentials.py --host="192.168.0.1" --user="admin" --password="admin" --name-pattern="ISP-PROD-*" --password-type="client" --what-if=True
#
# Example usage (prompts for the new password):
# python updateDatasourceCredentials.py --host="192.168.0.1" --user="admin" --password="admin" --name-pattern="veeam-*" --server-type="Veeam" --password-type="https"
#
# Example usage (SNMPv3, prompts for both SNMPv3 passwords):
# python updateDatasourceCredentials.py --host="192.168.0.1" --user="admin" --password="admin" --name-pattern="lib-*" --password-type="snmpv3" --snmp-auth-protocol="sha256" --snmp-privacy-protocol="aes128"
#
# Exit code 0: all matching data sources updated (or --what-if), 1: at least one update failed, 2: general error.
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import re
import fnmatch
import getpass
import requests

PASSWORD_TYPES = ["client", "https", "ssh", "smb", "token", "snmpv3"]
SNMP_AUTH_PROTOCOLS = ["noAuth", "md5", "sha1", "sha256"]
SNMP_PRIVACY_PROTOCOLS = ["noPrivacy", "3ds", "aes128", "aes192", "aes256", "des"]

parser = OptionParser()
parser.add_option("--host", dest="host", help="BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--user", dest="username", help="BACKUP EAGLE username (role admin)")
parser.add_option("--password", dest="password", help="BACKUP EAGLE password")
parser.add_option("--name-pattern", dest="namePattern", help="Pattern for the data source name. Wildcard pattern (e.g. ISP-PROD-*) by default, regular expression with --use-regex=True. Matching is case-insensitive.")
parser.add_option("--use-regex", dest="useRegex", default=False, help="Interpret --name-pattern as regular expression (default: false)")
parser.add_option("--password-type", dest="passwordType", type="choice", choices=PASSWORD_TYPES, help="Which password is set: " + ", ".join(PASSWORD_TYPES))
parser.add_option("--server-type", dest="serverType", help="Wildcard pattern for the type of the data source (e.g. ISP, Veeam). Default: ISP for --password-type=client, otherwise * (all types)")
parser.add_option("--new-password", dest="newPassword", help="New password (all password types except snmpv3). Prompted (twice) if not given.")
parser.add_option("--snmp-auth-protocol", dest="snmpAuthProtocol", type="choice", choices=SNMP_AUTH_PROTOCOLS, help="SNMPv3 authentication protocol: " + ", ".join(SNMP_AUTH_PROTOCOLS))
parser.add_option("--snmp-auth-password", dest="snmpAuthPassword", help="SNMPv3 authentication password. Prompted (twice) if needed and not given.")
parser.add_option("--snmp-privacy-protocol", dest="snmpPrivacyProtocol", type="choice", choices=SNMP_PRIVACY_PROTOCOLS, help="SNMPv3 privacy protocol: " + ", ".join(SNMP_PRIVACY_PROTOCOLS))
parser.add_option("--snmp-privacy-password", dest="snmpPrivacyPassword", help="SNMPv3 privacy password. Prompted (twice) if needed and not given.")
parser.add_option("--what-if", dest="whatIf", default=False, help="Only list the matching data sources, do not change anything (default: false)")
parser.add_option("--yes", dest="yes", default=False, help="Do not ask for confirmation (default: false)")
parser.add_option("--timeout", dest="timeout", type="int", default=60, help="Timeout of each REST call in seconds (default: 60)")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"
options.useRegex = str(options.useRegex).lower() == "true"
options.whatIf = str(options.whatIf).lower() == "true"
options.yes = str(options.yes).lower() == "true"

def fail(message):
    print("ERROR: " + message)
    sys.exit(2)

def validate_input():
    if(options.username is None or options.password is None or options.host is None or options.namePattern is None or options.passwordType is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)
    snmpOptions = [options.snmpAuthProtocol, options.snmpAuthPassword, options.snmpPrivacyProtocol, options.snmpPrivacyPassword]
    if(options.passwordType == "snmpv3"):
        if(options.snmpAuthProtocol is None or options.snmpPrivacyProtocol is None):
            fail("--password-type=snmpv3 requires --snmp-auth-protocol and --snmp-privacy-protocol.")
    elif(any(o is not None for o in snmpOptions)):
        fail("The --snmp-* options are only allowed with --password-type=snmpv3.")
    if(options.useRegex):
        try:
            re.compile(options.namePattern)
        except re.error as e:
            fail("Invalid regular expression: " + str(e))
    if(options.serverType is None):
        # client passwords only exist for ISP data sources
        options.serverType = "ISP" if options.passwordType == "client" else "*"

def read_new_secret(given, label):
    # returns the given secret or prompts twice for it
    if(given is None):
        given = getpass.getpass(label + ": ")
        if(given != getpass.getpass("Repeat " + label + ": ")):
            fail(label + ": entries do not match.")
    if(given == ""):
        fail(label + " must not be empty.")
    return given

def wildcard_match(value, pattern):
    return fnmatch.fnmatchcase(value.lower(), pattern.lower())

def name_matches(name):
    if(options.useRegex):
        return re.search(options.namePattern, name, re.IGNORECASE) is not None
    return wildcard_match(name, options.namePattern)

def server_type_name(dataSource):
    return dataSource.get("serverTypeName") or ""

def error_details(r):
    return "HTTP " + str(r.status_code) + ": " + r.text

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)
    baseUrl = "https://" + options.host + ":10987/api/rest/"

    # --- determine matching data sources ---
    print("Reading data sources from " + baseUrl + " ...")
    r = session.get(baseUrl + "datasource/list", verify=options.verifySSL, timeout=options.timeout)
    if(not r.ok):
        fail(error_details(r))
    dataSources = r.json()

    print("Found " + str(len(dataSources)) + " active data sources:")
    for ds in sorted(dataSources, key=lambda d: (server_type_name(d).lower(), d["name"].lower())):
        print("  %-20s %s (id %s)" % (server_type_name(ds), ds["name"], ds["id"]))

    typeMatching = [ds for ds in dataSources if wildcard_match(server_type_name(ds), options.serverType)]
    matching = sorted([ds for ds in typeMatching if name_matches(ds["name"])], key=lambda d: d["name"].lower())

    print("%d active data sources, %d of type '%s', %d matching '%s'" % (len(dataSources), len(typeMatching), options.serverType, len(matching), options.namePattern))
    if(len(matching) == 0):
        print("WARNING: No matching data source found - nothing to do.")
        sys.exit(0)

    print("Matching data sources:")
    for ds in matching:
        print("  - %s (%s, id %s)" % (ds["name"], server_type_name(ds), ds["id"]))

    if(options.whatIf):
        print("What if: would set the " + options.passwordType + " password of " + str(len(matching)) + " data sources.")
        sys.exit(0)

    # --- build request body (without server name) ---
    if(options.passwordType == "snmpv3"):
        template = {"type": options.passwordType, "snmpAuthProtocol": options.snmpAuthProtocol, "snmpPrivacyProtocol": options.snmpPrivacyProtocol}
        if(options.snmpAuthProtocol != "noAuth"):
            template["snmpAuthPassword"] = read_new_secret(options.snmpAuthPassword, "SNMPv3 authentication password")
        if(options.snmpPrivacyProtocol != "noPrivacy"):
            template["snmpPrivacyPassword"] = read_new_secret(options.snmpPrivacyPassword, "SNMPv3 privacy password")
    else:
        template = {"type": options.passwordType, "password": read_new_secret(options.newPassword, "New " + options.passwordType + " password")}

    if(not options.yes):
        answer = input("Set " + options.passwordType + " password for " + str(len(matching)) + " data sources? [y/N] ")
        if(answer.strip().lower() not in ("y", "yes", "j", "ja")):
            print("Cancelled - nothing changed.")
            sys.exit(0)

    # --- set passwords ---
    ok = 0
    failed = 0
    for ds in matching:
        # the REST API identifies the data source by name (case-insensitive)
        body = dict(template)
        body["server"] = ds["name"]
        try:
            r = session.put(baseUrl + "datasource/updateCredentials", verify=options.verifySSL, json=body, headers={'Content-Type': 'application/json'}, timeout=options.timeout)
            if(r.ok):
                print("OK      " + ds["name"])
                ok += 1
            else:
                print("FAILED  " + ds["name"] + ": " + error_details(r))
                failed += 1
        except requests.exceptions.RequestException as e:
            print("FAILED  " + ds["name"] + ": " + str(e))
            failed += 1

    print("Done: %d updated, %d failed" % (ok, failed))
    sys.exit(1 if failed > 0 else 0)

validate_input()
try:
    main()
except requests.exceptions.RequestException as e:
    fail(str(e))
