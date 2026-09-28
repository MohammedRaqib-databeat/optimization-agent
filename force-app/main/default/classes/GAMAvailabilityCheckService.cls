public with sharing class GAMAvailabilityCheckService {

    /*
     * ================================================================
     * Pre-sale inventory availability check against the real Google
     * Ad Manager network, for a Quote's line items BEFORE it is ever
     * converted to an Order (i.e. before anything is pushed to GAM).
     * Read-only - GAM's ForecastService.getAvailabilityForecast is
     * evaluated against a ProspectiveLineItem that is never created
     * or saved in GAM, so this makes zero external writes.
     *
     * Apex = deterministic evidence engine only: this returns real
     * GAM-computed unit counts and a factual comparison against the
     * requested quantity (FULLY_AVAILABLE / PARTIALLY_AVAILABLE /
     * UNAVAILABLE). It does not recommend a course of action - that
     * is Atlas/human territory, same principle as the rest of this
     * project.
     *
     * Honest MVP limitation: Ad Unit targeting resolution mirrors
     * GAMOrderPushService's approach (Product2.GAM_Ad_Unit_Name__c
     * when configured, else the first ACTIVE Ad Unit in the network) -
     * duplicated here rather than shared, since GAMOrderDeleteService
     * already established the pattern of small duplicated helpers
     * across these GAM service classes instead of a shared utility.
     * ================================================================
     */

    private static final String GAM_NAMED_CREDENTIAL = 'callout:GAM_API/';
    private static final String APPLICATION_NAME = 'Salesforce Media Cloud Optimization Agent';


    public class AvailabilityCheckRequest {
        @InvocableVariable(label='Quote ID' required=true)
        public String quoteId;
    }

    public class LineAvailability {
        @InvocableVariable(label='Ad Quote Line Id')
        public String adQuoteLineId;

        @InvocableVariable(label='Product Name')
        public String productName;

        @InvocableVariable(label='Requested Units')
        public Decimal requestedUnits;

        @InvocableVariable(label='Available Units')
        public Decimal availableUnits;

        @InvocableVariable(label='Possible Units')
        public Decimal possibleUnits;

        @InvocableVariable(label='Matched Units')
        public Decimal matchedUnits;

        @InvocableVariable(label='Unit Type')
        public String unitType;

        @InvocableVariable(label='Availability Status')
        public String availabilityStatus;

        @InvocableVariable(label='Ad Unit Used')
        public String adUnitUsed;
    }

    public class AvailabilityCheckResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Quote ID')
        public String quoteId;

        @InvocableVariable(label='Line Results (JSON)')
        public String lineResultsJson;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }

    public class AvailabilityCheckException extends Exception {}


    @InvocableMethod(
        label='Check Pre-Sale Availability Against Google Ad Manager'
        description='Checks real-time inventory availability in Google Ad Manager for every line on a Quote, before it is converted to an Order. Read-only - creates nothing in GAM or Salesforce.'
    )
    public static List<AvailabilityCheckResult> checkAvailability(List<AvailabilityCheckRequest> requests) {

        List<AvailabilityCheckResult> results = new List<AvailabilityCheckResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        String networkCode = getConfiguredNetworkCode();

        for (AvailabilityCheckRequest request : requests) {

            AvailabilityCheckResult result = new AvailabilityCheckResult();
            result.success = false;
            result.quoteId = request != null ? request.quoteId : null;

            try {
                if (request == null || String.isBlank(request.quoteId)) {
                    throw new AvailabilityCheckException('Quote ID is required.');
                }

                Quote sfQuote = [
                    SELECT Id, ExpirationDate
                    FROM Quote
                    WHERE Id = :Id.valueOf(request.quoteId)
                    LIMIT 1
                ];

                List<AdQuoteLine> adQuoteLines = [
                    SELECT Id, MediaType, AdRequestedQuantity, AdRequestedStartDate, AdRequestedEndDate,
                        QuoteLineItem.Product2.Name, QuoteLineItem.Product2.GAM_Ad_Unit_Name__c,
                        QuoteLineItem.Product2.GAM_Creative_Width__c, QuoteLineItem.Product2.GAM_Creative_Height__c
                    FROM AdQuoteLine
                    WHERE AdQuote.QuoteId = :sfQuote.Id
                    ORDER BY Id
                ];

                if (adQuoteLines.isEmpty()) {
                    throw new AvailabilityCheckException('This Quote has no media plan lines to check.');
                }

                String fallbackAdUnitId = getFirstActiveAdUnitId(networkCode);
                Map<String, String> adUnitIdByConfiguredName = new Map<String, String>();

                List<LineAvailability> lineResults = new List<LineAvailability>();

                for (AdQuoteLine line : adQuoteLines) {

                    Date requestedStartDate = line.AdRequestedStartDate != null ? line.AdRequestedStartDate.date() : Date.today();
                    // GAM's ForecastService is forward-looking only and rejects a
                    // startDateTime in the past - clamp to today when the plan's
                    // requested start date has already elapsed.
                    Date startDate = requestedStartDate > Date.today() ? requestedStartDate : Date.today();
                    Date endDate = line.AdRequestedEndDate != null ? line.AdRequestedEndDate.date()
                        : (sfQuote.ExpirationDate != null ? sfQuote.ExpirationDate : startDate.addDays(90));
                    if (endDate <= startDate) {
                        endDate = startDate.addDays(90);
                    }

                    String configuredAdUnitName = line.QuoteLineItem.Product2.GAM_Ad_Unit_Name__c;
                    String resolvedAdUnitId = fallbackAdUnitId;

                    if (!String.isBlank(configuredAdUnitName)) {
                        if (adUnitIdByConfiguredName.containsKey(configuredAdUnitName)) {
                            resolvedAdUnitId = adUnitIdByConfiguredName.get(configuredAdUnitName);
                        } else {
                            String lookedUpId = findAdUnitIdByName(configuredAdUnitName, networkCode);
                            resolvedAdUnitId = String.isNotBlank(lookedUpId) ? lookedUpId : fallbackAdUnitId;
                            adUnitIdByConfiguredName.put(configuredAdUnitName, resolvedAdUnitId);
                        }
                    }

                    Integer creativeWidth = line.QuoteLineItem.Product2.GAM_Creative_Width__c != null
                        ? line.QuoteLineItem.Product2.GAM_Creative_Width__c.intValue() : 300;
                    Integer creativeHeight = line.QuoteLineItem.Product2.GAM_Creative_Height__c != null
                        ? line.QuoteLineItem.Product2.GAM_Creative_Height__c.intValue() : 250;

                    Long requestedUnits = (line.AdRequestedQuantity != null ? line.AdRequestedQuantity : 1000).longValue();

                    GAMForecastServiceStub.AvailabilityForecast forecast = getAvailabilityForecast(
                        resolvedAdUnitId, startDate, endDate, requestedUnits, creativeWidth, creativeHeight, networkCode
                    );

                    LineAvailability lineResult = new LineAvailability();
                    lineResult.adQuoteLineId = line.Id;
                    lineResult.productName = line.QuoteLineItem.Product2.Name;
                    lineResult.requestedUnits = requestedUnits;
                    lineResult.adUnitUsed = resolvedAdUnitId;
                    lineResult.unitType = forecast.unitType;
                    lineResult.availableUnits = forecast.availableUnits != null ? forecast.availableUnits : 0;
                    lineResult.possibleUnits = forecast.possibleUnits != null ? forecast.possibleUnits : 0;
                    lineResult.matchedUnits = forecast.matchedUnits != null ? forecast.matchedUnits : 0;

                    if (lineResult.availableUnits >= requestedUnits) {
                        lineResult.availabilityStatus = 'FULLY_AVAILABLE';
                    } else if (lineResult.availableUnits > 0) {
                        lineResult.availabilityStatus = 'PARTIALLY_AVAILABLE';
                    } else {
                        lineResult.availabilityStatus = 'UNAVAILABLE';
                    }

                    lineResults.add(lineResult);
                }

                result.success = true;
                result.lineResultsJson = JSON.serialize(lineResults);
                result.explanation = 'Checked availability for ' + lineResults.size() + ' line(s) against Google Ad Manager.';

            } catch (Exception e) {
                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static GAMForecastServiceStub.AvailabilityForecast getAvailabilityForecast(
        String gamAdUnitId, Date startDate, Date endDate, Long requestedUnits,
        Integer creativeWidth, Integer creativeHeight, String networkCode
    ) {

        GAMForecastServiceStub.ForecastServiceInterfacePort port =
            new GAMForecastServiceStub.ForecastServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'ForecastService';
        port.RequestHeader = buildForecastHeader(networkCode);

        GAMForecastServiceStub.LineItem lineItem = new GAMForecastServiceStub.LineItem();
        lineItem.startDateTimeType = 'IMMEDIATELY';
        lineItem.endDateTime = toGamForecastDateTime(endDate);
        lineItem.unlimitedEndDateTime = false;
        lineItem.lineItemType = 'STANDARD';
        lineItem.costType = 'CPM';
        lineItem.creativeRotationType = 'EVEN';

        GAMForecastServiceStub.Goal goal = new GAMForecastServiceStub.Goal();
        goal.goalType = 'LIFETIME';
        goal.unitType = 'IMPRESSIONS';
        goal.units = requestedUnits;
        lineItem.primaryGoal = goal;

        GAMForecastServiceStub.Size size = new GAMForecastServiceStub.Size();
        size.width = creativeWidth;
        size.height = creativeHeight;
        size.isAspectRatio = false;

        GAMForecastServiceStub.CreativePlaceholder placeholder = new GAMForecastServiceStub.CreativePlaceholder();
        placeholder.size = size;
        lineItem.creativePlaceholders = new List<GAMForecastServiceStub.CreativePlaceholder>{ placeholder };

        GAMForecastServiceStub.AdUnitTargeting adUnitTargeting = new GAMForecastServiceStub.AdUnitTargeting();
        adUnitTargeting.adUnitId = gamAdUnitId;
        adUnitTargeting.includeDescendants = true;

        GAMForecastServiceStub.InventoryTargeting inventoryTargeting = new GAMForecastServiceStub.InventoryTargeting();
        inventoryTargeting.targetedAdUnits = new List<GAMForecastServiceStub.AdUnitTargeting>{ adUnitTargeting };

        GAMForecastServiceStub.Targeting targeting = new GAMForecastServiceStub.Targeting();
        targeting.inventoryTargeting = inventoryTargeting;
        lineItem.targeting = targeting;

        GAMForecastServiceStub.ProspectiveLineItem prospectiveLineItem = new GAMForecastServiceStub.ProspectiveLineItem();
        prospectiveLineItem.lineItem = lineItem;

        GAMForecastServiceStub.AvailabilityForecastOptions forecastOptions = new GAMForecastServiceStub.AvailabilityForecastOptions();

        return port.getAvailabilityForecast(prospectiveLineItem, forecastOptions);
    }


    private static String getFirstActiveAdUnitId(String networkCode) {

        GAMForecastServiceStub.ForecastServiceInterfacePort port =
            new GAMForecastServiceStub.ForecastServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'ForecastService';
        port.RequestHeader = buildForecastHeader(networkCode);

        // ForecastService has no InventoryService-style lookup of its
        // own; reuse the same InventoryService the push flow uses.
        GAMInventoryServiceStub.InventoryServiceInterfacePort inventoryPort =
            new GAMInventoryServiceStub.InventoryServiceInterfacePort();
        inventoryPort.endpoint_x = GAM_NAMED_CREDENTIAL + 'InventoryService';

        GAMInventoryServiceStub.SoapRequestHeader inventoryHeader = new GAMInventoryServiceStub.SoapRequestHeader();
        inventoryHeader.networkCode = networkCode;
        inventoryHeader.applicationName = APPLICATION_NAME;
        inventoryPort.RequestHeader = inventoryHeader;

        GAMInventoryServiceStub.Statement statement = new GAMInventoryServiceStub.Statement();
        statement.query = 'WHERE status = \'ACTIVE\' LIMIT 1';

        GAMInventoryServiceStub.AdUnitPage page = inventoryPort.getAdUnitsByStatement(statement);

        if (page == null || page.results == null || page.results.isEmpty()) {
            throw new AvailabilityCheckException('No active Ad Units found in this GAM network to check.');
        }

        return page.results[0].id;
    }


    private static String findAdUnitIdByName(String adUnitName, String networkCode) {

        GAMInventoryServiceStub.InventoryServiceInterfacePort port =
            new GAMInventoryServiceStub.InventoryServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'InventoryService';

        GAMInventoryServiceStub.SoapRequestHeader header = new GAMInventoryServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        port.RequestHeader = header;

        String escapedName = adUnitName.replace('\'', '\\\'');

        GAMInventoryServiceStub.Statement statement = new GAMInventoryServiceStub.Statement();
        statement.query = 'WHERE status = \'ACTIVE\' AND name = \'' + escapedName + '\' LIMIT 1';

        GAMInventoryServiceStub.AdUnitPage page = port.getAdUnitsByStatement(statement);

        if (page == null || page.results == null || page.results.isEmpty()) {
            return null;
        }

        return page.results[0].id;
    }


    private static GAMForecastServiceStub.DateTime_x toGamForecastDateTime(Date d) {

        GAMForecastServiceStub.Date_x gamDate = new GAMForecastServiceStub.Date_x();
        gamDate.year = d.year();
        gamDate.month = d.month();
        gamDate.day = d.day();

        GAMForecastServiceStub.DateTime_x gamDateTime = new GAMForecastServiceStub.DateTime_x();
        gamDateTime.date_x = gamDate;
        gamDateTime.hour = 0;
        gamDateTime.minute = 0;
        gamDateTime.second = 0;
        gamDateTime.timeZoneId = UserInfo.getTimeZone().getID();

        return gamDateTime;
    }


    private static GAMForecastServiceStub.SoapRequestHeader buildForecastHeader(String networkCode) {
        GAMForecastServiceStub.SoapRequestHeader header = new GAMForecastServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }


    private static String getConfiguredNetworkCode() {
        GAM_Config__c config = GAM_Config__c.getOrgDefaults();
        if (config == null || String.isBlank(config.Network_Code__c)) {
            throw new AvailabilityCheckException('No GAM network code is configured yet. Run the GAM onboarding wizard first.');
        }
        return config.Network_Code__c;
    }
}
