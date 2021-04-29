import ballerina/http;
import ballerina/log;
import ballerinax/googleapis_sheets as sheets;
import ballerinax/googleapis_sheets.'listener as sheetsListener;
import ballerinax/sfdc;

configurable int & readonly port = ?;

// Salesforce client configuration
configurable http:OAuth2RefreshTokenGrantConfig & readonly sfdcOauthConfig = ?;
configurable string & readonly sfdc_baseUrl = ?;

// Google Sheet client configuration
configurable http:OAuth2RefreshTokenGrantConfig  & readonly sheetOauthConfig = ?;
configurable string & readonly spreadsheetId = ?;
configurable string & readonly workSheetName = ?;

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
    spreadsheetId: spreadsheetId
};

// Create Salesforce client.
sfdc:Client baseClient = checkpanic new(sfClientConfiguration);

// Create Google Sheets client.
sheets:Client spreadsheetClient = check new (spreadsheetConfig);

// Create Google Sheets listener client.
listener sheetsListener:Listener gSheetListener = new (congifuration);

service / on gSheetListener {
    remote function onUpdateRow(sheetsListener:GSheetEvent event) returns error? {        

        // Get the updated column positions and row positions
        int? startColumnPosition = event?.eventInfo["startingColumnPosition"];
        int? endColumnPosition = event?.eventInfo["endColumnPosition"];
        int? startingRowPosition = event?.eventInfo["startingRowPosition"];

        if (startColumnPosition is int && endColumnPosition is int && startingRowPosition is int) {
            // Get the updated Column Names 
            string a1Notation = 
                string `${getColumnLetter(startColumnPosition)}1:${getColumnLetter(endColumnPosition)}1`;
                sheets:Range getValuesResult = check spreadsheetClient->getRange(spreadsheetId, workSheetName, 
                    a1Notation);
            (int|string|float)[][] columnNames = getValuesResult.values;

            // Get the updated Values 
            (int|string|float)[][]? data = event?.eventInfo["newValues"];

            // Get the record ID to update
            (string|int|float) recordId = check spreadsheetClient->getCell(spreadsheetId, workSheetName, 
                string `A${startingRowPosition}`);

            if (data is (int|string|float)[][]) {
                map<json> updatedContact = createJson(columnNames[0], data[0]);
                boolean|sfdc:Error res = baseClient->updateContact(recordId.toString(), updatedContact);
                if (res is boolean) {
                    string outputMessage = (res == true) ? "Contact Updated Successfully!" : 
                        "Failed to Update the Contact";
                    log:printInfo(outputMessage);
                } else {
                    log:printError(msg = res.message());
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
