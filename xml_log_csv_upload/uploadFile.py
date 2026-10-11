#######################################################################################################
#
# Python Example - Upload a XML, log or csv file
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Example usage:
# python uploadFile.py --host="192.168.0.1" --user="admin" --password="admin" --file="backup_result.xml"
#
# For more information see BACKUP EAGLE REST API documentation
#
#######################################################################################################

from optparse import OptionParser
import sys
import requests
import os.path
import mimetypes

parser = OptionParser()
parser.add_option("--host", dest="host", help="BACKUP EAGLE host, (example: 192.168.0.1)")
parser.add_option("--user", dest="username", help="BACKUP EAGLE username")
parser.add_option("--password", dest="password", help="BACKUP EAGLE password")
parser.add_option("--file", dest="file", help="File which should be transferred to the BACKUP EAGLE server.")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"

def validate_input():
    if(options.username is None or options.password is None or options.host is None or options.file is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)
    if not os.path.exists(options.file):
        print("File does not exist!")
        sys.exit(3)

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)

    url = "https://" + options.host + ":10987/api/rest/upload/default"
    files = [('file', (os.path.basename(options.file), open(options.file, 'rb'), 'application/octet-stream'))]
    r = session.post(url, verify=options.verifySSL, files=files)
    print(r.text)

validate_input()
main()