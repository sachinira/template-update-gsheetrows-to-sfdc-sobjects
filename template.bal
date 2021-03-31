import ballerina/http;
import ballerina/log;
import ballerinax/googleapis_drive as drive;
import ballerinax/googleapis_sheets as sheets;
import ballerinax/googleapis_sheets.'listener as sheetsListener;
import ballerinax/sfdc;

// Event Trigger class
public class EventTrigger {
    public isolated function onNewSheetCreatedEvent(string fileId) {}

    public isolated function onSheetDeletedEvent(string fileId) {}

    public isolated function onFileUpdateEvent(string fileId) {}
}

// Google Drive/Sheets listener configuration
configurable http:OAuth2DirectTokenConfig & readonly driveOauthConfig = ?;
configurable int & readonly port = ?;
configurable string & readonly callbackURL = ?;

// Salesforce client configuration
configurable http:OAuth2DirectTokenConfig & readonly sfdcOauthConfig = ?;
configurable string & readonly sfdc_baseUrl = ?;

// Google Sheet client configuration
configurable http:OAuth2DirectTokenConfig & readonly sheetOauthConfig = ?;
configurable string & readonly spreadsheetId = ?;
configurable string & readonly workSheetName = ?;

// Initialize Google Drive client 
drive:Configuration driveClientConfiguration = {
    clientConfig: driveOauthConfig
};

// Initialize Salesforce client 
sfdc:SalesforceConfiguration sfClientConfiguration = {
    baseUrl: sfdc_baseUrl,
    clientConfig: sfdcOauthConfig
};

// Initialize Google Sheets client 
sheets:SpreadsheetConfiguration spreadsheetConfig = {
    oauthClientConfig: sheetOauthConfig
};

// Initialize Google Sheets listener 
sheetsListener:SheetListenerConfiguration congifuration = {
    port: port,
    callbackURL: callbackURL,
    driveClientConfiguration: driveClientConfiguration,
    eventService: new EventTrigger()
};

// Create Salesforce client.
sfdc:BaseClient baseClient = checkpanic new (sfClientConfiguration);

// Create Google Sheets client.
sheets:Client spreadsheetClient = check new (spreadsheetConfig);

// Create Google Sheets listener client.
listener sheetsListener:GoogleSheetEventListener gSheetListener = new (congifuration);

service / on gSheetListener {
    resource function post onEdit (http:Caller caller, http:Request request) returns error? {
        sheetsListener:EventInfo eventInfo = check gSheetListener.getOnEditEventType(caller, request);
        
        if (eventInfo?.eventType == sheetsListener:UPDATE_ROW && eventInfo?.editEventInfo != ()) {
            // Get the updated column positions and row positions
            int? startColumnPosition = eventInfo?.editEventInfo?.startingColumnPosition;
            int? endColumnPosition = eventInfo?.editEventInfo?.startingColumnPosition;
            int? startingRowPosition = eventInfo?.editEventInfo?.startingRowPosition;

            if (startColumnPosition is int && endColumnPosition is int && startingRowPosition is int) {
                
                // Get the updated Column Names 
                string a1Notation = 
                    string `${getColumnLetter(startColumnPosition)}1:${getColumnLetter(endColumnPosition)}1`;
                sheets:Range getValuesResult = check spreadsheetClient->getRange(spreadsheetId, workSheetName, 
                    a1Notation);
                (int|string|float)[][] columnNames = getValuesResult.values;

                // Get the updated Values 
                (int|string|float)[][]? data = eventInfo?.editEventInfo?.newValues;

                // Get the record ID to update
                (string|int|float) recordId = check spreadsheetClient->getCell(spreadsheetId, workSheetName, 
                    string `A${startingRowPosition}`);

                if (data is (int|string|float)[][]) {
                    map<json> updatedContact = createJson(columnNames[0], data[0]);
                    boolean|sfdc:Error res = baseClient->updateContact(recordId.toString(), updatedContact);
                    if (res is boolean) {
                        string outputMessage = (res == true) ? "Contact Updated Successfully!" : 
                            "Failed to Update the Contact";
                        log:print(outputMessage);
                    } else {
                        log:printError(msg = res.message());
                    }
                }
            }
        }
    }
}

function getColumnLetter(int position) returns string {
    string[] columnNames = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", 
        "R", "S", "T", "U", "V", "W", "X", "Y", "Z"];
    return columnNames[position-1];
}

function createJson((int|string|float)[] columnNames, (string|int|float)[] values) returns map<json> {
    map<json> jsonMap = {};
    foreach int index in 0 ..< columnNames.length() {
            jsonMap[columnNames[index].toString()] = values[index];
    }
    return jsonMap;
}
