#######################################################################################################
#
# Python Example - Enables the activation of projects
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Example usage:
# python enableProject.py --host="192.168.0.1" --user="admin" --password="admin" --enable="true" --project='{\"comment\":\"comment\",\"domainName\":\"domain-name\",\"nodeName\":\"node-name\",\"serverName\":\"server-name\",\"projectName\":\"project-name\"}'
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import requests
import json

parser = OptionParser()
parser.add_option("--host", dest="host", help="BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--user", dest="username", help="BACKUP EAGLE username")
parser.add_option("--password", dest="password", help="BACKUP EAGLE password")
parser.add_option("--enable", dest="enable", help="Enable (true) or disable (false) the project")
parser.add_option("--project", dest="project", help="BAProject with required fields comment, domainName, nodeName and serverName as json data. serverName, domainName and nodeName may contain '*' as wildcard.")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"

def validate_input():
    if(options.username is None or options.password is None or options.host is None or options.enable is None or options.project is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)

    url = "https://" + options.host + ":10987/api/rest/baproject/"
    if(options.enable.lower() == "true"):
        url += "activate-baproject"
    else:
        url += "deactivate-baproject"

    data = json.loads(options.project)
    r = session.post(url, verify=options.verifySSL, json=data, headers={'Content-Type': 'application/json'})
    print(r.text)

validate_input()
main()