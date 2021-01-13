// This file contains your Data Connector logic
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

//Percipio Functions
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
        result=jsonContent[id]
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
        result = if isinprogess then null else jsonContent
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
        (i) => #duration(0, 0, 0, Number.Power(2, i)),
        10)
    in
        result;

GetReportData = (baseUrl as text, orgId as text, bearerToken as text, jobId as text) =>
    let
        Response = PollForReportWithRetry(baseUrl, orgId, bearerToken, jobId),
        ReportData = Table.FromRecords(Response,null,MissingField.UseNull)
    in
        ReportData;

[DataSource.Kind="PercipioBIExtension", Publish="PercipioBIExtension.Publish"]
shared PercipioBIExtension.LearnerActivityData = Value.ReplaceType(PercipioBIExtension.LearnerActivityImpl, PercipioBIExtension.LearnerActivityImplType);

PercipioBIExtension.LearnerActivityImplType = 
    let
        baseUrl = (type text) meta [
             Documentation.FieldCaption = Extension.LoadString("PercpioBIExtension.Label.baseUrl"),
             Documentation.FieldDescription = Extension.LoadString("PercpioBIExtension.Label.baseUrl"),
             Documentation.AllowedValues = {"https://api.percipio.com", "https://dew1-api.percipio.com" }
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
             Documentation.AllowedValues = {"DAY", "WEEK", "THIRTY_DAYS", "CALENDAR_MONTH" }
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
    // TestConnection is required to enable the connector through the Gateway
    TestConnection = (dataSourcePath) => 
        let
            json = Json.Document(dataSourcePath),
            baseUrl= json[baseUrl],
            orgId = json[orgId],
            bearerToken = json[bearerToken],
            timeFrame = json[timeFrame]
        in
            { "PercipioBIExtension.LearnerActivityData", baseUrl, orgId, bearerToken, timeFrame},
    Authentication = [
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
PercipioBIExtension.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = PercipioBIExtension.Icons,
    SourceTypeImage = PercipioBIExtension.Icons
];

PercipioBIExtension.Icons = [
    Icon16 = { Extension.Contents("PQExtension216.png"), Extension.Contents("PQExtension220.png"), Extension.Contents("PQExtension224.png"), Extension.Contents("PQExtension232.png") },
    Icon32 = { Extension.Contents("PQExtension232.png"), Extension.Contents("PQExtension240.png"), Extension.Contents("PQExtension248.png"), Extension.Contents("PQExtension264.png") }
];

