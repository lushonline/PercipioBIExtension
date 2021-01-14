// This file contains your Data Connector logic
[Version = "1.0.0"]
section PercipioBIExtension;

// Helper Function
Value.WaitFor = (producer as function, interval as function, optional count as number) as any =>
    let
        list = List.Generate(
            () => {0, null},
            (state) => state{0} <> null and (count = null or state{0} < count),
            (state) => if state{1} <> null then {null, state{1}} else {1 + state{0}, Function.InvokeAfter(() => producer(state{0}), interval(state{0}))},
            (state) => state{1})
    in
        List.Last(list);


EnforceSchema.Strict = 1;               // Add any missing columns, remove extra columns, set table type
EnforceSchema.IgnoreExtraColumns = 2;   // Add missing columns, do not remove extra columns
EnforceSchema.IgnoreMissingColumns = 3; // Do not add or remove columns

SchemaTransformTable = (table as table, schema as table, optional enforceSchema as number) as table =>
    let
        // Default to EnforceSchema.Strict
        _enforceSchema = if (enforceSchema <> null) then enforceSchema else EnforceSchema.Strict,

        // Applies type transforms to a given table
        EnforceTypes = (table as table, schema as table) as table =>
            let
                map = (t) => if Type.Is(t, type list) or Type.Is(t, type record) or t = type any then null else t,
                mapped = Table.TransformColumns(schema, {"Type", map}),
                omitted = Table.SelectRows(mapped, each [Type] <> null),
                existingColumns = Table.ColumnNames(table),
                removeMissing = Table.SelectRows(omitted, each List.Contains(existingColumns, [Name])),
                primativeTransforms = Table.ToRows(removeMissing),
                changedPrimatives = Table.TransformColumnTypes(table, primativeTransforms)
            in
                changedPrimatives,

        // Returns the table type for a given schema
        SchemaToTableType = (schema as table) as type =>
            let
                toList = List.Transform(schema[Type], (t) => [Type=t, Optional=false]),
                toRecord = Record.FromList(toList, schema[Name]),
                toType = Type.ForRecord(toRecord, false)
            in
                type table (toType),

        // Determine if we have extra/missing columns.
        // The enforceSchema parameter determines what we do about them.
        schemaNames = schema[Name],
        foundNames = Table.ColumnNames(table),
        addNames = List.RemoveItems(schemaNames, foundNames),
        extraNames = List.RemoveItems(foundNames, schemaNames),
        tmp = Text.NewGuid(),
        added = Table.AddColumn(table, tmp, each []),
        expanded = Table.ExpandRecordColumn(added, tmp, addNames),
        result = if List.IsEmpty(addNames) then table else expanded,
        fullList =
            if (_enforceSchema = EnforceSchema.Strict) then
                schemaNames
            else if (_enforceSchema = EnforceSchema.IgnoreMissingColumns) then
                foundNames
            else
                schemaNames & extraNames,

        // Select the final list of columns.
        // These will be ordered according to the schema table.
        reordered = Table.SelectColumns(result, fullList, MissingField.Ignore),
        enforcedTypes = EnforceTypes(reordered, schema),
        withType = if (_enforceSchema = EnforceSchema.Strict) then Value.ReplaceType(enforcedTypes, SchemaToTableType(schema)) else enforcedTypes
    in
        withType;

// Schema
LearnerActivitySchema = #table({"Name", "Type"}, {
        {"userId", type text},
        {"firstName", type text},
        {"lastName", type text},
        {"audience", type text},
        {"contentUuid", type text},
        {"contentId", type text},
        {"contentTitle", type text},
        {"contentType", type text},
        {"languageCode", type text},
        {"status", type text},
        {"completedDate", DateTime.Type},
        {"duration", Int32.Type},
        {"estimatedDuration", Int32.Type},
        {"firstAccess", DateTime.Type},
        {"lastAccess", DateTime.Type},
        {"totalAccesses", Int32.Type},
        {"%OfVideoOrBook", Percentage.Type},
        {"emailAddress", type text},
        {"durationHms", type text},
        {"estimatedDurationHms", type text},
        {"userUuid", type text}
    });

// Percipio Functions
GenerateReport = (baseUrl as text, orgId as text, bearerToken as text, timeFrame as text) =>
    let
        endpoint = baseUrl&"/reporting/v1/organizations/"&orgId&"/report-requests/learning-activity",
        headers = [
            #"Authorization" = "Bearer " & bearerToken,
            #"Content-Type" = "application/json"
        ],
        body =
        "{
          ""timeFrame"": """&timeFrame&""",
          ""contentType"": ""AudioBook,Audio Summary,Book,Book Summary,Channel,Course,Linked Content"",
          ""sort"": {
            ""field"": ""lastAccessDate"",
            ""order"": ""desc""
          },
          ""isFileRequiredInSftp"": false,
          ""formatType"": ""JSON""
        }",
        response = Web.Contents(
                        endpoint,
                        [Headers=headers,
                         ManualCredentials = true,
                         ManualStatusHandling={200,202},
                         Content=Text.ToBinary(body)
                         ]),
        buffered = Binary.Buffer(response), /* avoid risk of double request */
        asJson = try Json.Document(buffered, 65001) otherwise null,
        jsonContent = if asJson is action then null else asJson meta Value.Metadata(buffered),
        reportid=jsonContent[id],
        result=Diagnostics.Trace(TraceLevel.Information, "GenerateReport. Response:" & Text.FromBinary(buffered,65001), () => reportid, true)
    in
        result;

PollForReport = (baseUrl as text, orgId as text, bearerToken as text, jobId as text) =>
    let
        endpoint = baseUrl&"/reporting/v1/organizations/"&orgId&"/report-requests/"&jobId,
        headers = [
            #"Authorization" = "Bearer " & bearerToken,
            #"Content-Type" = "application/json"
        ],
        response =Web.Contents(
                endpoint,
                [Headers=headers,
                 ManualCredentials = true
                ]),
        buffered = Binary.Buffer(response), /* avoid risk of double request */
        asJson = try Json.Document(buffered, 65001) otherwise null,
        jsonContent = if asJson is action then null else asJson meta Value.Metadata(buffered),
        reportid = try jsonContent[reportId] otherwise null,
        isinprogess = reportid <> null,
        result = if isinprogess
            then
                let
                    response=Diagnostics.Trace(TraceLevel.Information, "PollForReport. Response:" & Text.FromBinary(buffered,65001), () => null, true)
                in
                    response
            else
                jsonContent
    in
        result;

// Request non existent report
// If the response is a 404 - we know the credentials are valid
ValidateCredentials = (baseUrl as text, orgId as text, bearerToken as text) =>
    let
        endpoint = baseUrl&"/reporting/v1/organizations/"&orgId&"/report-requests/"&orgId,
        headers = [
            #"Authorization" = "Bearer " & bearerToken,
            #"Content-Type" = "application/json"
        ],
        response =Web.Contents(
                endpoint,
                [Headers=headers,
                 ManualStatusHandling={404},
                 ManualCredentials = true
                ]),
        buffered = Binary.Buffer(response) meta Value.Metadata(response), /* avoid risk of double request */
        status = Value.Metadata(buffered)[Response.Status],
        result = if status = 404
            then
                let
                    result1=Diagnostics.Trace(TraceLevel.Information, "Validate Credentials Successful", () => true, true)
                in
                    result1
            else
                Error.Record("HTTP Status",Text.From(status), buffered)
    in
        result;


PollForReportWithRetry = (baseUrl as text, orgId as text, bearerToken as text, jobId as text) =>
    let
        result = Value.WaitFor(
        (i) =>
            let
                response = PollForReport(baseUrl, orgId, bearerToken, jobId)
            in
                response,
        (i) => #duration(0, 0, 0, Number.Power(2, i+1)),
        11)
    in
        result;

GetReportData = (baseUrl as text, orgId as text, bearerToken as text, jobId as text) =>
    let
        Response = PollForReportWithRetry(baseUrl, orgId, bearerToken, jobId),
        ReportData = if Response <> null then
             let   
                ReportDataAsTable = Table.FromRecords(Response,null,MissingField.UseNull),
                TableWithSchema = SchemaTransformTable(ReportDataAsTable, LearnerActivitySchema, EnforceSchema.IgnoreExtraColumns)
            in
                TableWithSchema
        else
             Table.FromRows({{"No records were found"}}, {"Message"})  
    in
        ReportData;

[DataSource.Kind="PercipioBIExtension", Publish="PercipioBIExtension.Publish"]
shared PercipioBIExtension.LearnerActivityData = Value.ReplaceType(PercipioBIExtension.LearnerActivityImpl, PercipioBIExtension.LearnerActivityImplType);

[DataSource.Kind="PercipioBIExtension"]
shared PercipioBIExtension.LearnerActivityDataTestConnection = Value.ReplaceType(PercipioBIExtension.TestConnectionImpl, PercipioBIExtension.LearnerActivityImplType);

PercipioBIExtension.LearnerActivityImplType =
    let
        baseUrl = (type text) meta [
             Documentation.FieldCaption = Extension.LoadString("PercpioBIExtension.Label.baseUrl"),
             Documentation.FieldDescription = Extension.LoadString("PercpioBIExtension.Label.baseUrl"),
             Documentation.AllowedValues = {"https://api.percipio.com", "https://dew1-api.percipio.com" },
             Documentation.DefaultValue = { "https://api.percipio.com" }
        ],
        orgId = (type text) meta [
             Documentation.FieldCaption =  Extension.LoadString("PercpioBIExtension.Label.orgId"),
             Documentation.FieldDescription = Extension.LoadString("PercpioBIExtension.Label.orgId")
        ],
        bearerToken = (type text) meta [
             Documentation.FieldCaption =  Extension.LoadString("PercpioBIExtension.Label.bearerToken"),
             Documentation.FieldDescription = Extension.LoadString("PercpioBIExtension.Label.bearerToken")
        ],
        timeFrame = (type text) meta [
           Documentation.FieldCaption = Extension.LoadString("PercpioBIExtension.Label.timeFrame"),
             Documentation.FieldDescription = Extension.LoadString("PercpioBIExtension.Label.timeFrame"),
             Documentation.AllowedValues = {"DAY", "WEEK", "THIRTY_DAYS", "CALENDAR_MONTH" },
             Documentation.DefaultValue = { "DAY" }
        ],
        t = type function (baseUrl as baseUrl, orgId as orgId, bearerToken as bearerToken, timeFrame as timeFrame) as table
    in
        t meta [
            Documentation.Caption = Extension.LoadString("PercipioBIExtension.LearnerActivity"),
            Documentation.Description = Extension.LoadString("PercipioBIExtension.LearnerActivity"),
            Documentation.DisplayName = Extension.LoadString("PercipioBIExtension.LearnerActivity"),
            Documentation.LongDescription = Extension.LoadString("PercipioBIExtension.LearnerActivity"),
            Documentation.Name = Extension.LoadString("PercipioBIExtension.LearnerActivity")
        ];

PercipioBIExtension.LearnerActivityImpl = (baseUrl as text, orgId as text, bearerToken as text, timeFrame as text) =>
    let
        table = PercipioBIExtension.LearnerActivity(baseUrl, orgId, bearerToken, timeFrame)
    in
        table;

PercipioBIExtension.TestConnectionImpl = (baseUrl as text, orgId as text, bearerToken as text, timeFrame as text) =>
    let
       CheckCredentials = ValidateCredentials(baseUrl, orgId, bearerToken),
       table = Table.FromRows({{"Percipio Credentials Valid"}}, {"Message"})  
    in
        table;


shared PercipioBIExtension.LearnerActivity = (baseUrl as text, orgId as text, bearerToken as text, timeFrame as text) =>
    let
        //1)	Request report be generated
        jobId = GenerateReport(baseUrl, orgId, bearerToken, timeFrame),
        //2)	Retrieve the data
        source = if Value.Is(jobId, type text) then GetReportData(baseUrl, orgId, bearerToken, jobId)
    else
        jobId
    in
        source;

// Data Source Kind description
PercipioBIExtension = [
    // Set the TestConnection handler to enable gateway support.
    // The TestConnection handler will invoke your data source function to 
    // validate the credentials the user has provider. Ideally, this is not 
    // an expensive operation to perform. By default, the dataSourcePath value 
    // will be a json string containing the required parameters of your data  
    // source function. These should be parsed and parsed as individual parameters
    // to the specified data source function.
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath),
            baseUrl= json[baseUrl],
            orgId = json[orgId],
            bearerToken = json[bearerToken],
            timeFrame = json[timeFrame]
        in
            { "PercipioBIExtension.LearnerActivityDataTestConnection", baseUrl, orgId, bearerToken, timeFrame},
    Authentication = [
        Implicit = []
    ]
    // Exclude Label so that it is easier to see which connection in Power BI
    // ,Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
PercipioBIExtension.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/martinholden-skillsoft/PercipioBIExtension/blob/main/README.md",
    SourceImage = PercipioBIExtension.Icons,
    SourceTypeImage = PercipioBIExtension.Icons
];

PercipioBIExtension.Icons = [
    Icon16 = { Extension.Contents("PQExtension216.png"), Extension.Contents("PQExtension220.png"), Extension.Contents("PQExtension224.png"), Extension.Contents("PQExtension232.png") },
    Icon32 = { Extension.Contents("PQExtension232.png"), Extension.Contents("PQExtension240.png"), Extension.Contents("PQExtension248.png"), Extension.Contents("PQExtension264.png") }
];

