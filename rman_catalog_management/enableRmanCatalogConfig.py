#######################################################################################################
#
# Python Example - De-/activate a RMAN catalog config
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Example usage:
# python enableRmanCatalogConfig.py --host="192.168.0.1" --user="admin" --password="admin" --config-id="1" --enable="true"
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import requests

parser = OptionParser()
parser.add_option("--host", dest="host", help="BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--user", dest="username", help="BACKUP EAGLE username")
parser.add_option("--password", dest="password", help="BACKUP EAGLE password")
parser.add_option("--config-id", dest="configId", help="Id of the RMAN catalog config")
parser.add_option("--enable", dest="enable", help="Enable (true) or disable (false) the config")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"

def validate_input():
    if(options.username is None or options.password is None or options.host is None or options.configId is None or options.enable is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)

    url = "https://" + options.host + ":10987/api/rest/config/rman/" + options.configId
    if(options.enable.lower() == "true"):
        url += "?active=true"
    else:
        url += "?active=false"
    r = session.put(url, verify=options.verifySSL)
    print(r.text)

validate_input()
main()