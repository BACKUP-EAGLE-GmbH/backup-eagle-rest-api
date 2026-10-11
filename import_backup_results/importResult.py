#######################################################################################################
#
# Python Example - Import backup-/restore results.
# (C) Schmitz RZ Consult GmbH - BACKUP EAGLE
#
# Example usage:
# python importResult.py --host="192.168.0.1" --user="admin" --password="admin" --result='{\"projectName\":\"testschedule\",\"baNode\":\"testnode\",\"baServer\":\"servername\",\"baNodeGroup\":\"domain\",\"objectName\":\"objekt\",\"startTime\":1645605007000,\"endTime\":1645606008000,\"rc\":8,\"schedStatus\":\"status\",\"schedResult\":8,\"schedStartTime\":1,\"bytes\":1024,\"savesetLevel\":22,\"bottleneck\":\"bottleneck\",\"bytesInspected\":1,\"transferRate\":1,\"compression\":1.0,\"readSize\":1,\"pool\":\"pool\",\"objectsInspected\":1,\"objectsAssigned\":1,\"objectsBackedUp\":1,\"objectsUpdated\":1,\"objectsRebound\":1,\"objectsDeleted\":1,\"objectsExpired\":1,\"objectsFailed\":1,\"subfileObjects\":1,\"reductionRatio\":1.0,\"processingTime\":1,\"action\":\"action\",\"transferredSize\":1,\"backupState\":\"state\",\"backupType\":\"backuptype\",\"objectType\":\"objecttype\",\"dedupFactor\":1.0,\"storagePolicy\":\"policy\",\"baObjects\":[{\"value\":\"InfoMessage\",\"type\":0},{\"value\":\"FehlerMeldung\",\"type\":8}]}'
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
parser.add_option("--result", dest="result", help="StartTime (required), endTime (required), baNodeGroup (required), baNode (required), baServer (required), projectName (required), objectName (required), rc (required), bytes, schedStatus, schedResult, schedStartTime, savesetLevel, bottleneck, bytesInspected, transferRate, compression, readSize, pool, objectsInspected, objectsAssigned, objectsBackedUp, objectsUpdated, objectsRebound, objectsDeleted, objectsExpired, objectsFailed, subfileObjects, reductionRatio, processingTime, action, transferredSize, backupState, backupType, objectType, dedupFactor, storagePolicy and baObjects as json.")
parser.add_option("--verify-ssl", dest="verifySSL", default=False, help="Verify SSL certificate of connection (default: false)")

(options, args) = parser.parse_args()
options.verifySSL = str(options.verifySSL).lower() == "true"

def validate_input():
    if(options.username is None or options.password is None or options.host is None or options.result is None):
        print("Invalid input, use -h or --help for help")
        sys.exit(2)

def main():
    session = requests.Session()
    session.auth = (options.username, options.password)

    url = "https://" + options.host + ":10987/api/rest/genericbackup/import-baresult"
    data = json.loads(options.result)
    r = session.post(url, verify=options.verifySSL, json=data, headers={'Content-Type': 'application/json'})
    print(r.text)

validate_input()
main()