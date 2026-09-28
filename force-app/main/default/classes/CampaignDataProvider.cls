public with sharing class CampaignDataProvider {

    /*
     * ================================================================
     * SALESFORCE FILE DATASET PREFIXES
     * ================================================================
     */

    private static final String DAILY_FILE_PREFIX =
        '01_line_item_daily_delivery';

    private static final String SEGMENT_FILE_PREFIX =
        '02_line_item_segment_delivery';

    private static final String INVENTORY_FILE_PREFIX =
        '03_inventory_availability_daily';

    private static final String TARGETING_FILE_PREFIX =
        '04_line_item_targeting_configuration';

    private static final String CONTENTION_FILE_PREFIX =
        '05_orders_line_items_contention';


    /*
     * ================================================================
     * DAILY DELIVERY MODEL
     * ================================================================
     */

    public class CampaignDay {

        public Date reportDate;
        public String dayOfWeek;

        public String lineItemId;
        public String advertiser;
        public String lineItemType;

        public Decimal primaryGoalUnits;
        public String primaryGoalType;

        public Date lineItemStartDate;
        public Date lineItemEndDate;

        public String costType;
        public String creative;
        public String adUnit;

        public Decimal dailyTargetImpressions;

        public Decimal adServerImpressions;
        public Decimal codeServedCount;
        public Decimal adServerClicks;
        public Decimal adServerRevenue;

        public Decimal availableImpressions;
        public Decimal totalUnfilledImpressions;

        public Decimal adServerCtr;
        public Decimal adServerFillRate;
        public Decimal adServerAverageEcpm;

        public Decimal cumulativeImpressions;
        public Decimal cumulativeTargetImpressions;
        public Decimal pacingPercentage;

        public Decimal sevenDayAverageImpressions;
        public Decimal projectedEndImpressions;
        public Decimal projectedGoalAttainmentPercentage;

        public Decimal activeViewMeasurableImpressions;
        public Decimal activeViewViewableImpressions;
        public Decimal activeViewViewabilityRate;

        public Decimal conversions;
        public Decimal videoStarts;
        public Decimal videoCompletes;

        public String deliveryRisk;
    }


    /*
     * ================================================================
     * SEGMENT DELIVERY MODEL
     * ================================================================
     */

    public class SegmentPerformance {

        public Date reportDate;
        public String lineItemId;
        public String advertiserName;

        public String segmentType;
        public String segmentId;
        public String segmentName;

        public String country;
        public String state;
        public String city;
        public String dma;

        public String audienceId;
        public String audienceName;

        public String deviceCategory;
        public String platform;

        public String placementId;
        public String placementName;
        public String adUnitPath;

        public String creativeName;
        public String creativeSize;
        public String daypart;

        public Decimal adRequests;
        public Decimal impressions;
        public Decimal clicks;
        public Decimal revenue;
        public Decimal unfilledImpressions;

        public Decimal measurableImpressions;
        public Decimal viewableImpressions;

        public Decimal ctrPercentage;
        public Decimal fillRatePercentage;
        public Decimal cpm;
        public Decimal viewabilityPercentage;
    }


    /*
     * ================================================================
     * INVENTORY AVAILABILITY MODEL
     * ================================================================
     */

    public class InventoryAvailability {

        public Date reportDate;

        public String inventoryId;
        public String placementId;
        public String placementName;
        public String adUnitPath;

        public String country;
        public String state;
        public String city;
        public String dma;

        public String deviceCategory;
        public String platform;
        public String creativeSize;
        public String inventoryType;

        public Decimal availableImpressions;
        public Decimal bookedImpressions;
        public Decimal reservedImpressions;
        public Decimal remainingAvailableImpressions;

        public Decimal adRequests;
        public Decimal historicalImpressions;

        public Decimal fillRatePercentage;
        public Decimal viewabilityPercentage;
        public Decimal ctrPercentage;
        public Decimal cpm;

        public Boolean isActive;
    }


    /*
     * ================================================================
     * TARGETING CONFIGURATION MODEL
     * ================================================================
     */

    public class TargetingConfiguration {

        public String lineItemId;

        public String targetingType;
        public String targetingId;
        public String targetingName;

        public String includeExclude;
        public String matchType;

        public Boolean active;
    }


    /*
     * ================================================================
     * CONTENTION MODEL
     * ================================================================
     */

    public class ContentionRecord {

        public String orderId;
        public String orderName;
        public String advertiserName;

        public String lineItemId;

        public Integer priority;
        public String lineItemStatus;

        public String goalType;
        public Decimal goalUnits;

        public Date startDate;
        public Date endDate;

        public Decimal bookedRate;

        /*
         * "currency" is reserved in Apex.
         * Therefore this field is deliberately named currencyCode.
         */
        public String currencyCode;

        public Integer frequencyCapPerUserPerDay;

        public String competitiveExclusionGroup;
    }


    /*
     * ================================================================
     * FORECASTING METHOD
     * ================================================================
     */

    public static List<CampaignDay> getLineItemData(
        String requestedLineItemId
    ) {

        String wantedId =
            requireLineItemId(requestedLineItemId);

        ContentVersion fileVersion =
            findLatestFile(DAILY_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No daily delivery CSV was found in Salesforce Files. ' +
                'Expected a file beginning with "' +
                DAILY_FILE_PREFIX +
                '".'
            );
        }

        List<CampaignDay> allRecords =
            parseDailyFile(fileVersion);

        List<CampaignDay> result =
            new List<CampaignDay>();

        for (CampaignDay record : allRecords) {

            if (
                record != null &&
                record.lineItemId == wantedId
            ) {
                result.add(record);
            }
        }

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'No daily delivery records were found for Line Item ID "' +
                wantedId +
                '".'
            );
        }

        sortCampaignDays(result);

        return result;
    }


    /*
     * ================================================================
     * ALL DAILY DELIVERY RECORDS
     * ================================================================
     */

    public static List<CampaignDay> getAllLineItemData() {

        ContentVersion fileVersion =
            findLatestFile(DAILY_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No daily delivery CSV was found for optimization.'
            );
        }

        List<CampaignDay> result =
            parseDailyFile(fileVersion);

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'The daily delivery CSV contains no usable records.'
            );
        }

        sortCampaignDays(result);

        return result;
    }


    /*
     * ================================================================
     * SEGMENT PERFORMANCE
     * ================================================================
     */

    public static List<SegmentPerformance> getSegmentPerformance(
        String requestedLineItemId
    ) {

        String wantedId =
            requireLineItemId(requestedLineItemId);

        ContentVersion fileVersion =
            findLatestFile(SEGMENT_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No segment delivery CSV was found.'
            );
        }

        List<SegmentPerformance> allRecords =
            parseSegmentFile(fileVersion);

        List<SegmentPerformance> result =
            new List<SegmentPerformance>();

        for (SegmentPerformance record : allRecords) {

            if (
                record != null &&
                record.lineItemId == wantedId
            ) {
                result.add(record);
            }
        }

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'No segment delivery records were found for Line Item ID "' +
                wantedId +
                '".'
            );
        }

        return result;
    }


    /*
     * ================================================================
     * INVENTORY AVAILABILITY
     *
     * This CSV does not contain LineItemID.
     * Therefore, this method returns the complete inventory dataset.
     * The optimizer must match inventory against targeting dimensions.
     * ================================================================
     */

    public static List<InventoryAvailability> getInventoryAvailability(
        String requestedLineItemId
    ) {

        requireLineItemId(requestedLineItemId);

        ContentVersion fileVersion =
            findLatestFile(INVENTORY_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No inventory availability CSV was found.'
            );
        }

        List<InventoryAvailability> result =
            parseInventoryFile(fileVersion);

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'The inventory availability CSV contains no usable records.'
            );
        }

        return result;
    }


    /*
     * ================================================================
     * TARGETING CONFIGURATION
     * ================================================================
     */

    public static List<TargetingConfiguration> getTargetingConfiguration(
        String requestedLineItemId
    ) {

        String wantedId =
            requireLineItemId(requestedLineItemId);

        ContentVersion fileVersion =
            findLatestFile(TARGETING_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No targeting configuration CSV was found.'
            );
        }

        List<TargetingConfiguration> allRecords =
            parseTargetingFile(fileVersion);

        List<TargetingConfiguration> result =
            new List<TargetingConfiguration>();

        for (TargetingConfiguration record : allRecords) {

            if (
                record != null &&
                record.lineItemId == wantedId
            ) {
                result.add(record);
            }
        }

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'No targeting configuration records were found for Line Item ID "' +
                wantedId +
                '".'
            );
        }

        return result;
    }


    /*
     * ================================================================
     * CONTENTION DATA
     * ================================================================
     */

    public static List<ContentionRecord> getContentionData(
        String requestedLineItemId
    ) {

        String wantedId =
            requireLineItemId(requestedLineItemId);

        ContentVersion fileVersion =
            findLatestFile(CONTENTION_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No contention CSV was found.'
            );
        }

        List<ContentionRecord> allRecords =
            parseContentionFile(fileVersion);

        List<ContentionRecord> result =
            new List<ContentionRecord>();

        for (ContentionRecord record : allRecords) {

            if (
                record != null &&
                record.lineItemId == wantedId
            ) {
                result.add(record);
            }
        }

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'No contention records were found for Line Item ID "' +
                wantedId +
                '".'
            );
        }

        return result;
    }


    /*
     * ================================================================
     * ALL CONTENTION RECORDS
     *
     * Unfiltered by Line Item ID, needed to resolve an Order Name to
     * the Line Item IDs it contains.
     * ================================================================
     */

    public static List<ContentionRecord> getAllContentionData() {

        ContentVersion fileVersion =
            findLatestFile(CONTENTION_FILE_PREFIX);

        if (fileVersion == null) {
            throw new CampaignDataException(
                'No contention CSV was found.'
            );
        }

        List<ContentionRecord> result =
            parseContentionFile(fileVersion);

        if (result.isEmpty()) {
            throw new CampaignDataException(
                'The contention CSV contains no usable records.'
            );
        }

        return result;
    }


    /*
     * ================================================================
     * FILE LOOKUP
     * ================================================================
     */

    private static ContentVersion findLatestFile(
        String titlePrefix
    ) {

        String titlePattern =
            titlePrefix + '%';

        List<ContentVersion> versions = [
            SELECT
                Id,
                Title,
                PathOnClient,
                FileExtension,
                CreatedDate,
                IsLatest,
                VersionData
            FROM ContentVersion
            WHERE
                Title LIKE :titlePattern
                AND FileExtension = 'csv'
                AND IsLatest = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            return null;
        }

        return versions[0];
    }


    /*
     * ================================================================
     * FILE READER
     * ================================================================
     */

    private static String readFile(
        ContentVersion fileVersion
    ) {

        if (fileVersion == null) {
            throw new CampaignDataException(
                'The Salesforce File could not be located.'
            );
        }

        if (fileVersion.VersionData == null) {
            throw new CampaignDataException(
                'The Salesforce File contains no VersionData.'
            );
        }

        try {

            String content =
                fileVersion.VersionData.toString();

            if (String.isBlank(content)) {
                throw new CampaignDataException(
                    'The Salesforce File is empty.'
                );
            }

            return content;

        } catch (CampaignDataException e) {

            throw e;

        } catch (Exception e) {

            throw new CampaignDataException(
                'Unable to read Salesforce File "' +
                fileVersion.Title +
                '". Error: ' +
                e.getMessage()
            );
        }
    }


    /*
     * ================================================================
     * DAILY FILE PARSER
     * ================================================================
     */

    private static List<CampaignDay> parseDailyFile(
        ContentVersion fileVersion
    ) {

        List<List<String>> rows =
            parseCsv(readFile(fileVersion));

        validateRows(rows);

        Map<String, Integer> columns =
            buildColumnIndex(rows[0]);

        validateRequiredColumns(
            columns,
            new List<String>{
                'ReportDate',
                'LineItemID',
                'AdvertiserName',
                'LineItemType',
                'GoalUnits',
                'GoalType',
                'StartDate',
                'EndDate',
                'CostType',
                'CreativeName',
                'AdUnitPath',
                'Impressions',
                'CodeServedCount',
                'Clicks',
                'Revenue',
                'UnfulfilledImpressions'
            }
        );

        List<CampaignDay> result =
            new List<CampaignDay>();

        for (
            Integer rowIndex = 1;
            rowIndex < rows.size();
            rowIndex++
        ) {

            List<String> row =
                rows[rowIndex];

            if (isEmptyRow(row)) {
                continue;
            }

            CampaignDay record =
                new CampaignDay();

            record.reportDate =
                parseDate(getValue(row, columns, 'ReportDate'));

            record.dayOfWeek =
                getValue(row, columns, 'DayOfWeek');

            record.lineItemId =
                getValue(row, columns, 'LineItemID');

            record.advertiser =
                getValue(row, columns, 'AdvertiserName');

            record.lineItemType =
                getValue(row, columns, 'LineItemType');

            record.primaryGoalUnits =
                parseDecimal(getValue(row, columns, 'GoalUnits'));

            record.primaryGoalType =
                getValue(row, columns, 'GoalType');

            record.lineItemStartDate =
                parseDate(getValue(row, columns, 'StartDate'));

            record.lineItemEndDate =
                parseDate(getValue(row, columns, 'EndDate'));

            record.costType =
                getValue(row, columns, 'CostType');

            record.creative =
                getValue(row, columns, 'CreativeName');

            record.adUnit =
                getValue(row, columns, 'AdUnitPath');

            record.dailyTargetImpressions =
                parseDecimal(
                    getValue(row, columns, 'Daily Target Impressions')
                );

            record.adServerImpressions =
                parseDecimal(
                    getValue(row, columns, 'Impressions')
                );

            record.codeServedCount =
                parseDecimal(
                    getValue(row, columns, 'CodeServedCount')
                );

            record.adServerClicks =
                parseDecimal(
                    getValue(row, columns, 'Clicks')
                );

            record.adServerRevenue =
                parseDecimal(
                    getValue(row, columns, 'Revenue')
                );

            record.availableImpressions =
                parseDecimal(
                    getValue(row, columns, 'AvailableImpressions')
                );

            record.totalUnfilledImpressions =
                parseDecimal(
                    getValue(row, columns, 'UnfulfilledImpressions')
                );

            record.adServerCtr =
                parseDecimal(
                    getValue(row, columns, 'CTRPercent')
                );

            record.adServerFillRate =
                parseDecimal(
                    getValue(row, columns, 'FillRatePercent')
                );

            record.adServerAverageEcpm =
                parseDecimal(
                    getValue(row, columns, 'CPM')
                );

            record.cumulativeImpressions =
                parseDecimal(
                    getValue(row, columns, 'CumulativeImpressions')
                );

            record.cumulativeTargetImpressions =
                parseDecimal(
                    getValue(row, columns, 'CumulativeTargetImpressions')
                );

            record.pacingPercentage =
                parseDecimal(
                    getValue(row, columns, 'PacingPercent')
                );

            record.sevenDayAverageImpressions =
                parseDecimal(
                    getValue(row, columns, 'SevenDayAvgImpressions')
                );

            record.projectedEndImpressions =
                parseDecimal(
                    getValue(row, columns, 'ProjectedEndImpressions')
                );

            record.projectedGoalAttainmentPercentage =
                parseDecimal(
                    getValue(
                        row,
                        columns,
                        'ProjectedGoalAttainmentPercent'
                    )
                );

            record.activeViewMeasurableImpressions =
                parseDecimal(
                    getValue(row, columns, 'MeasurableImpressions')
                );

            record.activeViewViewableImpressions =
                parseDecimal(
                    getValue(row, columns, 'ViewableImpressions')
                );

            record.activeViewViewabilityRate =
                parseDecimal(
                    getValue(row, columns, 'ViewabilityPercent')
                );

            record.conversions =
                parseDecimal(
                    getValue(row, columns, 'Conversions')
                );

            record.videoStarts =
                parseDecimal(
                    getValue(row, columns, 'VideoStarts')
                );

            record.videoCompletes =
                parseDecimal(
                    getValue(row, columns, 'VideoCompletes')
                );

            record.deliveryRisk =
                getValue(row, columns, 'DeliveryRisk');

            result.add(record);
        }

        return result;
    }


    /*
     * ================================================================
     * SEGMENT FILE PARSER
     * ================================================================
     */

    private static List<SegmentPerformance> parseSegmentFile(
        ContentVersion fileVersion
    ) {

        List<List<String>> rows =
            parseCsv(readFile(fileVersion));

        validateRows(rows);

        Map<String, Integer> columns =
            buildColumnIndex(rows[0]);

        validateRequiredColumns(
            columns,
            new List<String>{
                'ReportDate',
                'LineItemID',
                'AdvertiserName',
                'SegmentType',
                'SegmentID',
                'SegmentName',
                'AdUnitPath',
                'CreativeName',
                'CreativeSize',
                'AdRequests',
                'Impressions',
                'Clicks',
                'Revenue'
            }
        );

        List<SegmentPerformance> result =
            new List<SegmentPerformance>();

        for (
            Integer rowIndex = 1;
            rowIndex < rows.size();
            rowIndex++
        ) {

            List<String> row =
                rows[rowIndex];

            if (isEmptyRow(row)) {
                continue;
            }

            SegmentPerformance record =
                new SegmentPerformance();

            record.reportDate =
                parseDate(getValue(row, columns, 'ReportDate'));

            record.lineItemId =
                getValue(row, columns, 'LineItemID');

            record.advertiserName =
                getValue(row, columns, 'AdvertiserName');

            record.segmentType =
                getValue(row, columns, 'SegmentType');

            record.segmentId =
                getValue(row, columns, 'SegmentID');

            record.segmentName =
                getValue(row, columns, 'SegmentName');

            record.country =
                getValue(row, columns, 'Country');

            record.state =
                getValue(row, columns, 'State');

            record.city =
                getValue(row, columns, 'City');

            record.dma =
                getValue(row, columns, 'DMA');

            record.audienceId =
                getValue(row, columns, 'AudienceID');

            record.audienceName =
                getValue(row, columns, 'AudienceName');

            record.deviceCategory =
                getValue(row, columns, 'DeviceCategory');

            record.platform =
                getValue(row, columns, 'Platform');

            record.placementId =
                getValue(row, columns, 'PlacementID');

            record.placementName =
                getValue(row, columns, 'PlacementName');

            record.adUnitPath =
                getValue(row, columns, 'AdUnitPath');

            record.creativeName =
                getValue(row, columns, 'CreativeName');

            record.creativeSize =
                getValue(row, columns, 'CreativeSize');

            record.daypart =
                getValue(row, columns, 'Daypart');

            record.adRequests =
                parseDecimal(
                    getValue(row, columns, 'AdRequests')
                );

            record.impressions =
                parseDecimal(
                    getValue(row, columns, 'Impressions')
                );

            record.clicks =
                parseDecimal(
                    getValue(row, columns, 'Clicks')
                );

            record.revenue =
                parseDecimal(
                    getValue(row, columns, 'Revenue')
                );

            record.unfilledImpressions =
                parseDecimal(
                    getValue(row, columns, 'UnfilledImpressions')
                );

            record.measurableImpressions =
                parseDecimal(
                    getValue(row, columns, 'MeasurableImpressions')
                );

            record.viewableImpressions =
                parseDecimal(
                    getValue(row, columns, 'ViewableImpressions')
                );

            record.ctrPercentage =
                parseDecimal(
                    getValue(row, columns, 'CTRPercent')
                );

            record.fillRatePercentage =
                parseDecimal(
                    getValue(row, columns, 'FillRatePercent')
                );

            record.cpm =
                parseDecimal(
                    getValue(row, columns, 'CPM')
                );

            record.viewabilityPercentage =
                parseDecimal(
                    getValue(row, columns, 'ViewabilityPercent')
                );

            result.add(record);
        }

        return result;
    }


    /*
     * ================================================================
     * INVENTORY FILE PARSER
     * ================================================================
     */

    private static List<InventoryAvailability> parseInventoryFile(
        ContentVersion fileVersion
    ) {

        List<List<String>> rows =
            parseCsv(readFile(fileVersion));

        validateRows(rows);

        Map<String, Integer> columns =
            buildColumnIndex(rows[0]);

        validateRequiredColumns(
            columns,
            new List<String>{
                'ReportDate',
                'InventoryID',
                'PlacementID',
                'PlacementName',
                'AdUnitPath',
                'CreativeSize',
                'AvailableImpressions',
                'BookedImpressions',
                'ReservedImpressions',
                'RemainingAvailableImpressions'
            }
        );

        List<InventoryAvailability> result =
            new List<InventoryAvailability>();

        for (
            Integer rowIndex = 1;
            rowIndex < rows.size();
            rowIndex++
        ) {

            List<String> row =
                rows[rowIndex];

            if (isEmptyRow(row)) {
                continue;
            }

            InventoryAvailability record =
                new InventoryAvailability();

            record.reportDate =
                parseDate(getValue(row, columns, 'ReportDate'));

            record.inventoryId =
                getValue(row, columns, 'InventoryID');

            record.placementId =
                getValue(row, columns, 'PlacementID');

            record.placementName =
                getValue(row, columns, 'PlacementName');

            record.adUnitPath =
                getValue(row, columns, 'AdUnitPath');

            record.country =
                getValue(row, columns, 'Country');

            record.state =
                getValue(row, columns, 'State');

            record.city =
                getValue(row, columns, 'City');

            record.dma =
                getValue(row, columns, 'DMA');

            record.deviceCategory =
                getValue(row, columns, 'DeviceCategory');

            record.platform =
                getValue(row, columns, 'Platform');

            record.creativeSize =
                getValue(row, columns, 'CreativeSize');

            record.inventoryType =
                getValue(row, columns, 'InventoryType');

            record.availableImpressions =
                parseDecimal(
                    getValue(row, columns, 'AvailableImpressions')
                );

            record.bookedImpressions =
                parseDecimal(
                    getValue(row, columns, 'BookedImpressions')
                );

            record.reservedImpressions =
                parseDecimal(
                    getValue(row, columns, 'ReservedImpressions')
                );

            record.remainingAvailableImpressions =
                parseDecimal(
                    getValue(
                        row,
                        columns,
                        'RemainingAvailableImpressions'
                    )
                );

            record.adRequests =
                parseDecimal(
                    getValue(row, columns, 'AdRequests')
                );

            record.historicalImpressions =
                parseDecimal(
                    getValue(row, columns, 'HistoricalImpressions')
                );

            record.fillRatePercentage =
                parseDecimal(
                    getValue(row, columns, 'FillRatePercent')
                );

            record.viewabilityPercentage =
                parseDecimal(
                    getValue(row, columns, 'ViewabilityPercent')
                );

            record.ctrPercentage =
                parseDecimal(
                    getValue(row, columns, 'CTRPercent')
                );

            record.cpm =
                parseDecimal(
                    getValue(row, columns, 'CPM')
                );

            record.isActive =
                parseBoolean(
                    getValue(row, columns, 'IsActive')
                );

            result.add(record);
        }

        return result;
    }


    /*
     * ================================================================
     * TARGETING FILE PARSER
     * ================================================================
     */

    private static List<TargetingConfiguration> parseTargetingFile(
        ContentVersion fileVersion
    ) {

        List<List<String>> rows =
            parseCsv(readFile(fileVersion));

        validateRows(rows);

        Map<String, Integer> columns =
            buildColumnIndex(rows[0]);

        validateRequiredColumns(
            columns,
            new List<String>{
                'LineItemID',
                'TargetingType',
                'TargetingID',
                'TargetingName',
                'IncludeExclude',
                'MatchType',
                'Active'
            }
        );

        List<TargetingConfiguration> result =
            new List<TargetingConfiguration>();

        for (
            Integer rowIndex = 1;
            rowIndex < rows.size();
            rowIndex++
        ) {

            List<String> row =
                rows[rowIndex];

            if (isEmptyRow(row)) {
                continue;
            }

            TargetingConfiguration record =
                new TargetingConfiguration();

            record.lineItemId =
                getValue(row, columns, 'LineItemID');

            record.targetingType =
                getValue(row, columns, 'TargetingType');

            record.targetingId =
                getValue(row, columns, 'TargetingID');

            record.targetingName =
                getValue(row, columns, 'TargetingName');

            record.includeExclude =
                getValue(row, columns, 'IncludeExclude');

            record.matchType =
                getValue(row, columns, 'MatchType');

            record.active =
                parseBoolean(
                    getValue(row, columns, 'Active')
                );

            result.add(record);
        }

        return result;
    }


    /*
     * ================================================================
     * CONTENTION FILE PARSER
     * ================================================================
     */

    private static List<ContentionRecord> parseContentionFile(
        ContentVersion fileVersion
    ) {

        List<List<String>> rows =
            parseCsv(readFile(fileVersion));

        validateRows(rows);

        Map<String, Integer> columns =
            buildColumnIndex(rows[0]);

        validateRequiredColumns(
            columns,
            new List<String>{
                'OrderID',
                'OrderName',
                'AdvertiserName',
                'LineItemID',
                'Priority',
                'LineItemStatus',
                'GoalType',
                'GoalUnits',
                'StartDate',
                'EndDate',
                'BookedRate',
                'Currency'
            }
        );

        List<ContentionRecord> result =
            new List<ContentionRecord>();

        for (
            Integer rowIndex = 1;
            rowIndex < rows.size();
            rowIndex++
        ) {

            List<String> row =
                rows[rowIndex];

            if (isEmptyRow(row)) {
                continue;
            }

            ContentionRecord record =
                new ContentionRecord();

            record.orderId =
                getValue(row, columns, 'OrderID');

            record.orderName =
                getValue(row, columns, 'OrderName');

            record.advertiserName =
                getValue(row, columns, 'AdvertiserName');

            record.lineItemId =
                getValue(row, columns, 'LineItemID');

            record.priority =
                parseInteger(
                    getValue(row, columns, 'Priority')
                );

            record.lineItemStatus =
                getValue(row, columns, 'LineItemStatus');

            record.goalType =
                getValue(row, columns, 'GoalType');

            record.goalUnits =
                parseDecimal(
                    getValue(row, columns, 'GoalUnits')
                );

            record.startDate =
                parseDate(
                    getValue(row, columns, 'StartDate')
                );

            record.endDate =
                parseDate(
                    getValue(row, columns, 'EndDate')
                );

            record.bookedRate =
                parseDecimal(
                    getValue(row, columns, 'BookedRate')
                );

            record.currencyCode =
                getValue(row, columns, 'Currency');

            record.frequencyCapPerUserPerDay =
                parseInteger(
                    getValue(
                        row,
                        columns,
                        'FrequencyCapPerUserPerDay'
                    )
                );

            record.competitiveExclusionGroup =
                getValue(
                    row,
                    columns,
                    'CompetitiveExclusionGroup'
                );

            result.add(record);
        }

        return result;
    }


    /*
     * ================================================================
     * CSV VALIDATION
     * ================================================================
     */

    private static void validateRows(
        List<List<String>> rows
    ) {

        if (
            rows == null ||
            rows.size() < 2
        ) {
            throw new CampaignDataException(
                'CSV must contain a header row and at least one data row.'
            );
        }
    }


    private static Map<String, Integer> buildColumnIndex(
        List<String> header
    ) {

        Map<String, Integer> result =
            new Map<String, Integer>();

        if (header == null) {
            throw new CampaignDataException(
                'CSV header row is missing.'
            );
        }

        for (
            Integer index = 0;
            index < header.size();
            index++
        ) {

            if (header[index] == null) {
                continue;
            }

            String columnName =
                header[index].trim();

            if (!String.isBlank(columnName)) {
                result.put(columnName, index);
            }
        }

        return result;
    }


    private static void validateRequiredColumns(
        Map<String, Integer> columns,
        List<String> requiredColumns
    ) {

        List<String> missingColumns =
            new List<String>();

        for (String columnName : requiredColumns) {

            if (
                columns == null ||
                !columns.containsKey(columnName)
            ) {
                missingColumns.add(columnName);
            }
        }

        if (!missingColumns.isEmpty()) {
            throw new CampaignDataException(
                'CSV schema validation failed. Missing column(s): ' +
                String.join(missingColumns, ', ')
            );
        }
    }


    private static Boolean isEmptyRow(
        List<String> row
    ) {

        if (row == null || row.isEmpty()) {
            return true;
        }

        for (String value : row) {

            if (!String.isBlank(value)) {
                return false;
            }
        }

        return true;
    }


    private static String requireLineItemId(
        String lineItemId
    ) {

        if (String.isBlank(lineItemId)) {
            throw new CampaignDataException(
                'Line Item ID is required.'
            );
        }

        return lineItemId.trim();
    }


    private static String getValue(
        List<String> row,
        Map<String, Integer> columns,
        String columnName
    ) {

        if (
            row == null ||
            columns == null ||
            !columns.containsKey(columnName)
        ) {
            return '';
        }

        Integer index =
            columns.get(columnName);

        if (
            index == null ||
            index < 0 ||
            index >= row.size()
        ) {
            return '';
        }

        if (row[index] == null) {
            return '';
        }

        return row[index].trim();
    }


    /*
     * ================================================================
     * TYPE PARSERS
     * ================================================================
     */

    private static Date parseDate(
        String value
    ) {

        if (String.isBlank(value)) {
            return null;
        }

        try {

            return Date.valueOf(value.trim());

        } catch (Exception e) {

            throw new CampaignDataException(
                'Invalid date value "' +
                value +
                '". Expected YYYY-MM-DD.'
            );
        }
    }


    private static Decimal parseDecimal(
        String value
    ) {

        if (String.isBlank(value)) {
            return null;
        }

        try {

            String cleaned =
                value
                    .trim()
                    .replace(',', '');

            return Decimal.valueOf(cleaned);

        } catch (Exception e) {

            throw new CampaignDataException(
                'Invalid numeric value "' +
                value +
                '".'
            );
        }
    }


    private static Integer parseInteger(
        String value
    ) {

        if (String.isBlank(value)) {
            return null;
        }

        try {

            String cleaned =
                value
                    .trim()
                    .replace(',', '');

            return Integer.valueOf(cleaned);

        } catch (Exception e) {

            throw new CampaignDataException(
                'Invalid integer value "' +
                value +
                '".'
            );
        }
    }


    private static Boolean parseBoolean(
        String value
    ) {

        if (String.isBlank(value)) {
            return null;
        }

        String normalized =
            value.trim().toLowerCase();

        if (
            normalized == 'true' ||
            normalized == '1' ||
            normalized == 'yes'
        ) {
            return true;
        }

        if (
            normalized == 'false' ||
            normalized == '0' ||
            normalized == 'no'
        ) {
            return false;
        }

        throw new CampaignDataException(
            'Invalid Boolean value "' +
            value +
            '". Expected true or false.'
        );
    }


    /*
     * ================================================================
     * CSV PARSER
     *
     * Supports:
     * - quoted values
     * - commas inside quoted values
     * - escaped quotes
     * - LF and CRLF line endings
     * ================================================================
     */

    private static List<List<String>> parseCsv(
        String csvText
    ) {

        List<List<String>> rows =
            new List<List<String>>();

        List<String> currentRow =
            new List<String>();

        String currentField =
            '';

        Boolean insideQuotes =
            false;

        for (
            Integer index = 0;
            index < csvText.length();
            index++
        ) {

            String character =
                csvText.substring(
                    index,
                    index + 1
                );

            if (character == '"') {

                if (insideQuotes) {

                    if (
                        index + 1 < csvText.length() &&
                        csvText.substring(
                            index + 1,
                            index + 2
                        ) == '"'
                    ) {

                        currentField += '"';
                        index++;

                    } else {

                        insideQuotes = false;
                    }

                } else {

                    insideQuotes = true;
                }

                continue;
            }

            if (
                character == ',' &&
                !insideQuotes
            ) {

                currentRow.add(currentField);
                currentField = '';

                continue;
            }

            if (
                (
                    character == '\n' ||
                    character == '\r'
                ) &&
                !insideQuotes
            ) {

                if (
                    character == '\r' &&
                    index + 1 < csvText.length() &&
                    csvText.substring(
                        index + 1,
                        index + 2
                    ) == '\n'
                ) {
                    index++;
                }

                currentRow.add(currentField);
                currentField = '';

                if (!currentRow.isEmpty()) {
                    rows.add(currentRow);
                }

                currentRow =
                    new List<String>();

                continue;
            }

            currentField += character;
        }

        if (
            !currentRow.isEmpty() ||
            currentField != ''
        ) {

            currentRow.add(currentField);
            rows.add(currentRow);
        }

        return rows;
    }


    /*
     * ================================================================
     * SORT DAILY RECORDS
     * ================================================================
     */

    private static void sortCampaignDays(
        List<CampaignDay> records
    ) {

        if (
            records == null ||
            records.size() < 2
        ) {
            return;
        }

        for (
            Integer i = 1;
            i < records.size();
            i++
        ) {

            CampaignDay current =
                records[i];

            Integer j =
                i - 1;

            while (
                j >= 0 &&
                shouldComeAfter(
                    records[j],
                    current
                )
            ) {

                records[j + 1] =
                    records[j];

                j--;
            }

            records[j + 1] =
                current;
        }
    }


    private static Boolean shouldComeAfter(
        CampaignDay left,
        CampaignDay right
    ) {

        if (
            left == null ||
            left.reportDate == null
        ) {
            return false;
        }

        if (
            right == null ||
            right.reportDate == null
        ) {
            return false;
        }

        return left.reportDate > right.reportDate;
    }


    /*
     * ================================================================
     * EXCEPTION
     * ================================================================
     */

    public class CampaignDataException
        extends Exception {
    }
}