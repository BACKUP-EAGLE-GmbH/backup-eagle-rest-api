#######################################################################################################
#
# Python Example - Import node names from a file into a user defined group
# (C) BACKUP EAGLE GmbH
#
# Same behaviour as the node import in the user defined group editor of the BACKUP EAGLE Admin UI:
#   1. Reads the node file: one node per line, lines are trimmed, empty lines are skipped,
#      duplicates (case-insensitive) are removed, at most 1000 nodes (the rest is cut off with a warning).
#   2. Each node "node001" becomes the pattern "*node001*" (disable with --no-wildcard=True).
#   3. Reads all user defined groups:     GET  /api/rest/udgs/list
#   4. Group with the given name exists:  POST /api/rest/udgs/update  (ALL existing entries are replaced)
#      Group does not exist:              POST /api/rest/udgs/add
#      Only the column node name (baNodeName) is filled, all other columns are "*", exclude is false.
#      Name and address list of an existing group stay unchanged.
#
# Example usage:
# python importNodesToUserDefinedGroup.py --host="192.168.0.1" --user="admin" --password="admin" --node-file="nodes.txt" --group-name="Merck-Report-Nodes"
#
# Example usage (prompts for the password, only shows what would be done):
# python importNodesToUserDefinedGroup.py --host="192.168.0.1" --user="admin" --node-file="nodes.txt" --group-name="UDG-1" --what-if=True
#
# Exit code 0: success (or --what-if), 1: REST call failed, 2: general error.
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import os
import locale
import getpass
import requests

# same limit as the node import dialog of the Admin UI
MAX_NODES = 1000

parser = OptionParser()
parser.add_option("--host", dest="host", help="BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--port", dest="port", type="int", default=10987, help="BACKUP EAGLE REST port (default: 10987)")
parser.add_option("--base-url", dest="baseUrl", help="Base URL of the REST API, overrides --host/--port (default: https://<host>:<port>/api/rest)")
parser.add_option("--user", dest="username", help="BACKUP EAGLE username")
parser.add_option("--password", dest="password", help="BACKUP EAGLE password. Prompted if not given.")
parser.add_option("--node-file", dest="nodeFile", help="Text file with one node name per line (UTF-8 or ANSI)")
parser.add_option("--group-name", dest="groupName", help="Name of the user defined group that is created or updated")
parser.add_option("--no-wildcard", dest="noWildcard", default=False, help="Import the node names as they are instead of *<node>* (default: false)")
parser.add_option("--what-if", dest="whatIf", default=False, help="Only show whether the group would be created or updated, do not change anything (default: false)")
parser.add_option("--timeout", dest="timeout", type="int", default=60, help="Timeout of each REST call in seconds (default: 60)")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"
options.noWildcard = str(options.noWildcard).lower() == "true"
options.whatIf = str(options.whatIf).lower() == "true"

def fail(message):
    print("ERROR: " + message)
    sys.exit(2)

def validate_input():
    if((options.host is None and options.baseUrl is None) or options.username is None or options.nodeFile is None or options.groupName is None or options.groupName == ""):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)
    if(not os.path.isfile(options.nodeFile)):
        fail("Node file not found: " + options.nodeFile)
    if(options.password is None):
        options.password = getpass.getpass("BACKUP EAGLE password: ")

def read_node_file(path):
    # returns the distinct, trimmed, non-empty lines of the file
    with open(path, "rb") as f:
        data = f.read()
    try:
        # UTF-8 (BOM is removed)
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        # no valid UTF-8 -> ANSI file (e.g. saved by Excel/Notepad)
        text = data.decode(locale.getpreferredencoding(False), errors="replace")
    seen = set()
    nodes = []
    for line in text.splitlines():
        node = line.strip()
        if(node and node.lower() not in seen):
            seen.add(node.lower())
            nodes.append(node)
    return nodes

def new_group_element(nodePattern):
    # same defaults as the node import of the Admin UI: only the node name is set, everything else matches all
    return {
        "baServerName": "*",
        "baNodeName": nodePattern,
        "baNodeGroupName": "*",
        "baNodeOs": "*",
        "baNodeContact": "*",
        "baNodeActive": "*",
        "baServerActive": "*",
        "isExclude": False,
        "tag": "*"
    }

def error_details(r):
    # the user defined group REST API returns its error message in the HTTP reason phrase, not in the body
    return ("HTTP " + str(r.status_code) + " " + (r.reason or "") + " " + r.text).strip()

def find_group(groups):
    # group names are compared case-insensitively, an exact (case-sensitive) match wins
    existing = [g for g in groups if g.get("name") == options.groupName]
    if(len(existing) == 0):
        existing = [g for g in groups if (g.get("name") or "").lower() == options.groupName.lower()]
    if(len(existing) > 1):
        fail("Group name '%s' is ambiguous: %d groups found (ids %s)." % (options.groupName, len(existing), ", ".join(str(g.get("id")) for g in existing)))
    return existing[0] if existing else None

def main():
    # --- read nodes ---
    nodes = read_node_file(options.nodeFile)
    if(len(nodes) == 0):
        fail("Node file contains no node names: " + options.nodeFile)
    if(len(nodes) > MAX_NODES):
        print("WARNING: Node file contains %d nodes, only the first %d are imported." % (len(nodes), MAX_NODES))
        nodes = nodes[:MAX_NODES]
    elements = [new_group_element(node if options.noWildcard else "*" + node + "*") for node in nodes]
    print("%d nodes read from %s" % (len(nodes), options.nodeFile))

    session = requests.Session()
    session.auth = (options.username, options.password)
    if(options.baseUrl):
        baseUrl = options.baseUrl.rstrip("/") + "/"
    else:
        baseUrl = "https://" + options.host + ":" + str(options.port) + "/api/rest/"

    # --- find existing group ---
    print("Reading user defined groups from " + baseUrl + " ...")
    r = session.get(baseUrl + "udgs/list", verify=options.verifySSL, timeout=options.timeout)
    if(not r.ok):
        print("FAILED: " + error_details(r))
        sys.exit(1)
    r.encoding = "utf-8"
    group = find_group(r.json())

    # --- create or update ---
    if(group is not None):
        oldCount = len(group.get("elements") or [])
        if(options.whatIf):
            print("What if: would update group '%s' (id %s): replace %d entries by %d node entries." % (group["name"], group["id"], oldCount, len(elements)))
            sys.exit(0)
        # name and address list stay unchanged (null = not changed by the server)
        body = {"id": group["id"], "elements": elements}
        r = session.post(baseUrl + "udgs/update", verify=options.verifySSL, json=body, headers={'Content-Type': 'application/json'}, timeout=options.timeout)
        if(not r.ok):
            print("FAILED: " + error_details(r))
            sys.exit(1)
        print("OK      group '%s' (id %s) updated: %d entries replaced by %d node entries" % (group["name"], group["id"], oldCount, len(elements)))
    else:
        if(options.whatIf):
            print("What if: would create group '%s' with %d node entries." % (options.groupName, len(elements)))
            sys.exit(0)
        body = {"name": options.groupName, "elements": elements}
        r = session.post(baseUrl + "udgs/add", verify=options.verifySSL, json=body, headers={'Content-Type': 'application/json'}, timeout=options.timeout)
        if(not r.ok):
            print("FAILED: " + error_details(r))
            sys.exit(1)
        newId = ""
        try:
            newId = " (id %s)" % r.json()["id"]
        except (ValueError, KeyError, TypeError):
            newId = ""
        print("OK      group '%s'%s created with %d node entries" % (options.groupName, newId, len(elements)))
    sys.exit(0)

validate_input()
try:
    main()
except requests.exceptions.RequestException as e:
    fail(str(e))
