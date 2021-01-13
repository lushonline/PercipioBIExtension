# PERCIPIOBIEXTENSION
Call Percipio Reporting Services API to get Learner Activity report data in Power BI

## Percipio Requirements
1. A Skillsoft [Percipio](https://www.skillsoft.com/platform-solution/percipio/) Site
1. A [Percipio Service Account](https://documentation.skillsoft.com/en_us/pes/3_services/service_accounts/pes_service_accounts.htm) with permission for accessing [REPORTING API](https://documentation.skillsoft.com/en_us/pes/2_understanding_percipio/rest_api/pes_rest_api.htm)

## Percipio Information you will need

| Value       | Required | Description |
| --------- | -------- | ------------------- |
| BASEURL | Required | This is set to the base URL for the Percipio data center. For US hosted use: https://api.percipio.com For EU hosted use: https://dew1-api.percipio.com |
| ORGID     | Required | This is the Percipio Organiation UUID for your Percipio Site  |
| BEARERTOKEN| Required | This is the Percipio Bearer token for a Service Account with permissions for services. |

## How do Install

1. Create these folders if they dont exist:<br>
```C:\Users\<Your_User_Name>\Documents\Microsoft Power BI Desktop\Custom Connectors```

1. Open Power BI Desktop, enable the Data Extensions under "Options and settings" and then "Options"
![](img/security_settings.png)

1. Download the [bin/release/PercipioBIExtension.mez](bin/release/PercipioBIExtension.mez) file from this repository and save to the folderabove.

## How to use it

1. Choose "Get Data" in Power BI

1. Select the "Percipio BI Extension Option"
![](img/getdata.png)

1. Accept the Warning by clicking Continue button
![](img/warning.png)

1. Complete the Percipio Information and select the TimeFrame for the data to include and click OK
![](img/settings.png)

1. Accept the anonymous authentication details, and click Connect
![](img/auth.png)

1. The report request will be sent and the results displayed, and click Load.
![](img/results.png)


## Changelog

Please see [CHANGELOG](CHANGELOG.md) for more information what has changed recently.

## License

MIT © martinholden-skillsoft
