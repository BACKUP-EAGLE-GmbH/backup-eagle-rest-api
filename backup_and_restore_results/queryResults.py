#######################################################################################################
#
# Python Example - Query backup/restore results
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Example usage:
# python queryResults.py --host="192.168.0.1" --user="admin" --password="admin" --result-options='{\"startTime\":\"2024-11-18T07:00:00\",\"endTime\";\"2024-11-19T07:00:00\",\"serverName\":\"Azure-Server-01\"}' --pretty-print=True
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
parser.add_option("--result-options", dest="resultOptions", help="StartTime (required), endTime (required), domainName, nodeName, serverName, udgId and queryType as json")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Yerify SSL certificate of connection (default: false)")
parser.add_option("--pretty-print", dest="prettyPrint", default=False, help="Pretty printing of the response (default: false)")

(options, args) = parser.parse_args()

def validate_input():
    if(options.username is None or options.password is None or options.host is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)

    url = "https://" + options.host + ":10987/api/rest/baresult/get"
    data = json.loads(options.resultOptions)

    r = session.post(url, verify=options.verifySSL, json=data, headers={'Content-Type': 'application/json'})
    if(options.prettyPrint):
       print(json.dumps(r.json(), indent=4, sort_keys=True))
    else:
       print(r.text)

validate_input()
main()
