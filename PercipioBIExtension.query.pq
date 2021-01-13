// Use this file to write queries to test your data connector
let
    Source = PercipioBIExtension.LearnerActivityData("https://api.percipio.com",
                                                     "b001e4aa-7ac9-4d15-8ddc-b0c58f6982dd",
                                                     "REDACTED",
                                                     "THIRTY_DAYS")
in
    Source