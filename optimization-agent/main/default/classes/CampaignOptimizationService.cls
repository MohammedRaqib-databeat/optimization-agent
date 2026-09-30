public with sharing class CampaignOptimizationService {

    /*
     * ================================================================
     * CAMPAIGN OPTIMIZATION EVIDENCE ENGINE
     * ================================================================
     *
     * PURPOSE
     * -------
     * This action is an analytical/evidence action for Agentforce.
     *
     * Apex responsibilities:
     *   1. Retrieve source data.
     *   2. Calculate factual historical metrics.
     *   3. Calculate portfolio comparison metrics.
     *   4. Summarize segment observations.
     *   5. Summarize inventory observations.
     *   6. Return current targeting configuration.
     *   7. Return contention context.
     *   8. Identify data-quality / compatibility limitations.
     *   9. Package all evidence for Agentforce / Atlas reasoning.
     *
     * Atlas / Agentforce responsibilities:
     *   1. Interpret the evidence.
     *   2. Compare observed alternatives.
     *   3. Decide whether optimization is justified.
     *   4. Select a supported candidate when evidence is sufficient.
     *   5. Explain the decision.
     *   6. Assign reasoning/confidence based on the evidence.
     *
     * IMPORTANT
     * ---------
     * Apex DOES NOT:
     *   - select a final recommendation
     *   - invent uplift
     *   - invent targeting
     *   - invent allocation
     *   - invent configuration changes
     *   - hardcode campaign IDs
     *   - hardcode campaign metrics
     *   - hardcode a recommendation hierarchy
     *   - modify Salesforce/ad-server/GAM data
     *
     * Human approval is required before any future apply action.
     *
     * ================================================================
     */


    /*
     * ================================================================
     * INVOCABLE REQUEST
     * ================================================================
     */

    public class OptimizationRequest {

        @InvocableVariable(
            label='Line Item ID'
            required=true
        )
        public String lineItemId;
    }


    /*
     * ================================================================
     * INVOCABLE RESULT
     * ================================================================
     *
     * The existing primitive fields are retained for Agentforce
     * compatibility.
     *
     * The important new field is:
     *
     *     optimizationEvidence
     *
     * It contains the structured evidence package that Atlas can reason
     * over.
     *
     * Apex intentionally leaves final recommendation fields null:
     *
     *     recommendedAction
     *     actionType
     *     rationale
     *     expectedImpact
     *     recommendationCategory
     *     proposedConfiguration
     *     confidence
     *     risk
     *
     * Those are reasoning outputs, not deterministic Apex outputs.
     * ================================================================
     */

    public class OptimizationResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Line Item ID')
        public String lineItemId;

        @InvocableVariable(label='Advertiser')
        public String advertiser;

        @InvocableVariable(label='Line Item Type')
        public String lineItemType;

        @InvocableVariable(label='Creative')
        public String creative;

        @InvocableVariable(label='Ad Unit')
        public String adUnit;

        @InvocableVariable(label='Goal Type')
        public String goalType;

        @InvocableVariable(label='Goal Units')
        public Decimal goalUnits;

        @InvocableVariable(label='Historical Impressions')
        public Decimal historicalImpressions;

        @InvocableVariable(label='Historical Clicks')
        public Decimal historicalClicks;

        @InvocableVariable(label='Historical Revenue')
        public Decimal historicalRevenue;

        @InvocableVariable(label='Historical Ad Requests')
        public Decimal historicalAdRequests;

        @InvocableVariable(label='Historical Code Served Count')
        public Decimal historicalCodeServedCount;

        @InvocableVariable(label='Historical Unfilled Impressions')
        public Decimal historicalUnfilledImpressions;

        @InvocableVariable(label='CTR Percentage')
        public Decimal ctrPercentage;

        @InvocableVariable(label='CPM')
        public Decimal cpm;

        @InvocableVariable(label='Fill Rate Percentage')
        public Decimal fillRatePercentage;

        @InvocableVariable(label='Average Daily Impressions')
        public Decimal averageDailyImpressions;

        @InvocableVariable(label='Recent 7 Day Average Impressions')
        public Decimal recent7DayAverageImpressions;

        @InvocableVariable(label='Recent Delivery Trend Percentage')
        public Decimal recentDeliveryTrendPercentage;

        @InvocableVariable(label='Portfolio Median CTR Percentage')
        public Decimal portfolioMedianCtrPercentage;

        @InvocableVariable(label='Portfolio Median CPM')
        public Decimal portfolioMedianCpm;

        @InvocableVariable(label='Portfolio Median Fill Rate Percentage')
        public Decimal portfolioMedianFillRatePercentage;

        @InvocableVariable(label='CTR Versus Benchmark Percentage')
        public Decimal ctrVersusBenchmarkPercentage;

        @InvocableVariable(label='CPM Versus Benchmark Percentage')
        public Decimal cpmVersusBenchmarkPercentage;

        @InvocableVariable(label='Fill Rate Versus Benchmark Percentage')
        public Decimal fillRateVersusBenchmarkPercentage;

        @InvocableVariable(label='Delivery Signal')
        public String deliverySignal;

        @InvocableVariable(label='Engagement Signal')
        public String engagementSignal;

        @InvocableVariable(label='Supply Signal')
        public String supplySignal;

        @InvocableVariable(label='Yield Signal')
        public String yieldSignal;

        /*
         * These are intentionally null from Apex.
         * Atlas / Agentforce should determine them.
         */
        @InvocableVariable(label='Optimization Health')
        public String optimizationHealth;

        @InvocableVariable(label='Optimization Urgency')
        public String optimizationUrgency;

        @InvocableVariable(label='Recommended Action')
        public String recommendedAction;

        @InvocableVariable(label='Action Type')
        public String actionType;

        @InvocableVariable(label='Rationale')
        public String rationale;

        @InvocableVariable(label='Expected Impact')
        public String expectedImpact;

        @InvocableVariable(label='Human Approval Required')
        public Boolean humanApprovalRequired;

        @InvocableVariable(label='Apply Status')
        public String applyStatus;

        @InvocableVariable(label='Recommendation Category')
        public String recommendationCategory;

        @InvocableVariable(label='Current Configuration')
        public String currentConfiguration;

        @InvocableVariable(label='Proposed Configuration')
        public String proposedConfiguration;

        @InvocableVariable(label='Evidence')
        public String evidence;

        @InvocableVariable(label='Confidence')
        public String confidence;

        @InvocableVariable(label='Risk')
        public String risk;

        @InvocableVariable(label='Recommendation Basis')
        public String recommendationBasis;

        @InvocableVariable(label='Explanation')
        public String explanation;

        /*
         * NEW:
         * Complete machine-readable evidence package for Atlas.
         */
        @InvocableVariable(label='Optimization Evidence')
        public String optimizationEvidence;

        @InvocableVariable(label='Data Quality Status')
        public String dataQualityStatus;

        @InvocableVariable(label='Data Quality Issues')
        public String dataQualityIssues;

        @InvocableVariable(label='Observed Candidate Count')
        public Integer observedCandidateCount;
    }


    /*
     * ================================================================
     * INTERNAL LINE-ITEM METRICS
     * ================================================================
     */

    private class LineItemMetrics {

        public String lineItemId;
        public String advertiser;
        public String lineItemType;
        public String creative;
        public String adUnit;

        public String goalType;
        public Decimal goalUnits;

        public Decimal impressions = 0;
        public Decimal clicks = 0;
        public Decimal revenue = 0;
        public Decimal codeServed = 0;
        public Decimal unfilled = 0;

        public Decimal measurable = 0;
        public Decimal viewable = 0;

        public Integer historicalDays = 0;

        public Decimal averageDailyImpressions = 0;
        public Decimal recent7DayAverage = 0;
        public Decimal recentTrend;

        public Decimal ctr;
        public Decimal cpm;
        public Decimal fillRate;
        public Decimal viewability;

        public Date startDate;
        public Date endDate;
        public Date latestReportDate;
    }


    /*
     * ================================================================
     * PORTFOLIO BENCHMARK
     * ================================================================
     */

    private class Benchmark {

        public Decimal medianCtr;
        public Decimal medianCpm;
        public Decimal medianFillRate;
    }


    /*
     * ================================================================
     * SEGMENT SUMMARY
     * ================================================================
     *
     * Each SegmentType is aggregated independently.
     *
     * We do NOT combine unrelated analytical dimensions.
     *
     * Example:
     *
     * Geography rows remain geography observations.
     * Audience rows remain audience observations.
     * Placement rows remain placement observations.
     *
     * This is analytical evidence, not a blended score.
     * ================================================================
     */

    private class SegmentSummary {

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

        public Decimal impressions = 0;
        public Decimal clicks = 0;
        public Decimal revenue = 0;
        public Decimal unfilled = 0;
        public Decimal measurable = 0;
        public Decimal viewable = 0;
        public Decimal requests = 0;

        public Integer recordCount = 0;

        public Decimal ctr;
        public Decimal cpm;
        public Decimal fillRate;
        public Decimal viewability;
    }


    /*
     * ================================================================
     * INVENTORY SUMMARY
     * ================================================================
     */

    private class InventorySummary {

        public String inventoryId;
        public String placementId;
        public String placementName;
        public String adUnitPath;
        public String creativeSize;

        public String country;
        public String state;
        public String city;
        public String dma;

        public String deviceCategory;
        public String platform;
        public String inventoryType;

        public Decimal available = 0;
        public Decimal booked = 0;
        public Decimal reserved = 0;
        public Decimal remaining = 0;

        public Decimal requests = 0;
        public Decimal historicalImpressions = 0;

        public Decimal fillRate;
        public Decimal viewability;
        public Decimal ctr;
        public Decimal cpm;

        public Integer recordCount = 0;

        public Boolean isActive;
    }


    /*
     * ================================================================
     * TARGETING SUMMARY
     * ================================================================
     */

    private class TargetingSummary {

        public Map<String, List<CampaignDataProvider.TargetingConfiguration>> byType =
            new Map<String, List<CampaignDataProvider.TargetingConfiguration>>();

        public List<String> activeTypes =
            new List<String>();
    }


    /*
     * ================================================================
     * CONTENTION SUMMARY
     * ================================================================
     */

    private class ContentionSummary {

        public Boolean exists = false;

        public Integer priority;
        public String status;

        public List<Map<String, Object>> records =
            new List<Map<String, Object>>();
    }


    /*
     * ================================================================
     * DATA QUALITY
     * ================================================================
     */

    private class DataQualitySummary {

        public String status = 'AVAILABLE';

        public List<String> issues =
            new List<String>();

        public Integer dailyRowCount = 0;
        public Integer segmentRowCount = 0;
        public Integer inventoryRowCount = 0;
        public Integer targetingRowCount = 0;
        public Integer contentionRowCount = 0;

        public Boolean segmentEvidenceAvailable = false;
        public Boolean inventoryEvidenceAvailable = false;
        public Boolean targetingEvidenceAvailable = false;
        public Boolean contentionEvidenceAvailable = false;
    }


    /*
     * ================================================================
     * INVOCABLE METHOD
     * ================================================================
     */

    @InvocableMethod(
        label='Analyze Campaign Optimization Evidence'
        description='Returns historical campaign performance, benchmarks, segment observations, inventory observations, targeting configuration, contention context, and data-quality evidence for Agentforce/Atlas reasoning.'
    )
    public static List<OptimizationResult> optimize(
        List<OptimizationRequest> requests
    ) {

        List<OptimizationResult> results =
            new List<OptimizationResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }


        /*
         * ------------------------------------------------------------
         * LOAD DAILY DATA
         * ------------------------------------------------------------
         */

        List<CampaignDataProvider.CampaignDay> allDailyRows;

        try {

            allDailyRows =
                CampaignDataProvider.getAllLineItemData();

        } catch (Exception e) {

            for (
                OptimizationRequest request :
                requests
            ) {

                OptimizationResult errorResult =
                    new OptimizationResult();

                errorResult.success = false;
                errorResult.status = 'ERROR';

                errorResult.lineItemId =
                    request == null
                        ? null
                        : request.lineItemId;

                errorResult.humanApprovalRequired = true;
                errorResult.applyStatus = 'NOT_APPLICABLE';

                errorResult.explanation =
                    e.getMessage();

                results.add(errorResult);
            }

            return results;
        }


        /*
         * ------------------------------------------------------------
         * AGGREGATE ALL LINE ITEMS
         * ------------------------------------------------------------
         */

        Map<String, LineItemMetrics> metricsByLineItem =
            aggregateLineItems(
                allDailyRows
            );


        Benchmark benchmark =
            calculateBenchmark(
                metricsByLineItem.values()
            );


        /*
         * ------------------------------------------------------------
         * PROCESS REQUESTS
         * ------------------------------------------------------------
         */

        for (
            OptimizationRequest request :
            requests
        ) {

            OptimizationResult result =
                new OptimizationResult();

            result.success = false;
            result.humanApprovalRequired = true;
            result.applyStatus = 'NOT_APPLICABLE';

            try {

                if (
                    request == null ||
                    String.isBlank(request.lineItemId)
                ) {

                    throw new OptimizationException(
                        'Line Item ID is required.'
                    );
                }


                String requestedId =
                    request.lineItemId.trim();


                if (
                    !metricsByLineItem.containsKey(
                        requestedId
                    )
                ) {

                    throw new OptimizationException(
                        'No historical dataset records were found for Line Item ID "' +
                        requestedId +
                        '".'
                    );
                }


                LineItemMetrics target =
                    metricsByLineItem.get(
                        requestedId
                    );


                /*
                 * ----------------------------------------------------
                 * BASE METRICS
                 * ----------------------------------------------------
                 */

                populateBaseMetrics(
                    result,
                    target
                );


                populateBenchmarks(
                    result,
                    target,
                    benchmark
                );


                calculateSignals(
                    result,
                    target,
                    benchmark
                );


                /*
                 * ----------------------------------------------------
                 * LOAD DETAILED DATA
                 * ----------------------------------------------------
                 */

                List<CampaignDataProvider.SegmentPerformance> segmentRows =
                    safeGetSegmentPerformance(
                        requestedId
                    );

                List<CampaignDataProvider.InventoryAvailability> inventoryRows =
                    safeGetInventoryAvailability(
                        requestedId
                    );

                List<CampaignDataProvider.TargetingConfiguration> targetingRows =
                    safeGetTargetingConfiguration(
                        requestedId
                    );

                List<CampaignDataProvider.ContentionRecord> contentionRows =
                    safeGetContentionData(
                        requestedId
                    );


                /*
                 * ----------------------------------------------------
                 * SUMMARIZE DETAILED DATA
                 * ----------------------------------------------------
                 */

                List<SegmentSummary> segmentSummaries =
                    aggregateSegments(
                        segmentRows
                    );

                List<InventorySummary> inventorySummaries =
                    aggregateInventory(
                        inventoryRows
                    );

                TargetingSummary targetingSummary =
                    buildTargetingSummary(
                        targetingRows
                    );

                ContentionSummary contentionSummary =
                    buildContentionSummary(
                        contentionRows
                    );


                /*
                 * ----------------------------------------------------
                 * DATA QUALITY
                 * ----------------------------------------------------
                 */

                DataQualitySummary dataQuality =
                    evaluateDataQuality(
                        target,
                        segmentRows,
                        inventoryRows,
                        targetingRows,
                        contentionRows,
                        segmentSummaries,
                        inventorySummaries,
                        targetingSummary,
                        contentionSummary
                    );


                result.dataQualityStatus =
                    dataQuality.status;

                result.dataQualityIssues =
                    joinIssues(
                        dataQuality.issues
                    );


                /*
                 * ----------------------------------------------------
                 * OBSERVED CANDIDATE COUNT
                 *
                 * This is NOT a ranked recommendation count.
                 *
                 * It simply describes how many observed segment and
                 * inventory options are present in the evidence.
                 * ----------------------------------------------------
                 */

                result.observedCandidateCount =
                    segmentSummaries.size() +
                    inventorySummaries.size();


                /*
                 * ----------------------------------------------------
                 * CURRENT CONFIGURATION
                 *
                 * Raw factual context only.
                 * No proposed change is generated.
                 * ----------------------------------------------------
                 */

                result.currentConfiguration =
                    buildCurrentConfigurationText(
                        targetingRows
                    );


                /*
                 * ----------------------------------------------------
                 * EVIDENCE TEXT
                 * ----------------------------------------------------
                 */

                result.evidence =
                    buildEvidenceSummary(
                        target,
                        benchmark,
                        segmentSummaries,
                        inventorySummaries,
                        targetingRows,
                        contentionSummary,
                        dataQuality
                    );


                /*
                 * ----------------------------------------------------
                 * ATLAS EVIDENCE PACKAGE
                 * ----------------------------------------------------
                 */

                result.optimizationEvidence =
                    buildOptimizationEvidence(
                        target,
                        benchmark,
                        segmentSummaries,
                        inventorySummaries,
                        targetingRows,
                        contentionSummary,
                        dataQuality,
                        result
                    );


                /*
                 * ----------------------------------------------------
                 * DETERMINISTIC HEALTH / URGENCY CLASSIFICATION
                 *
                 * Health/urgency is a risk-tiering calculation, not a
                 * recommendation. It is calculated once, deterministically,
                 * in Apex (mirroring CampaignForecastService's deliveryRisk
                 * pattern) so it is identical across every run, every
                 * model, and every user - not re-interpreted by Atlas
                 * from a natural-language heuristic on each request.
                 * ----------------------------------------------------
                 */

                calculateOptimizationHealth(
                    result
                );

                /*
                 * ----------------------------------------------------
                 * NO FINAL RECOMMENDATION FROM APEX
                 * ----------------------------------------------------
                 */

                result.recommendedAction = null;
                result.actionType = null;
                result.rationale = null;
                result.expectedImpact = null;

                result.recommendationCategory = null;
                result.proposedConfiguration = null;
                result.confidence = null;
                result.risk = null;
                result.recommendationBasis = null;

                result.explanation =
                    'Historical optimization evidence is available for Atlas reasoning. Apex calculated the factual metrics and returned the observed alternatives and constraints without selecting or applying a final recommendation.';

                result.humanApprovalRequired = true;
                result.applyStatus = 'PENDING_HUMAN_REVIEW';

                result.success = true;
                result.status =
                    'OPTIMIZATION_EVIDENCE_AVAILABLE';

            } catch (Exception e) {

                result.success = false;
                result.status = 'ERROR';

                result.explanation =
                    e.getMessage();
            }


            results.add(result);
        }


        return results;
    }


    /*
     * ================================================================
     * DAILY DATA AGGREGATION
     * ================================================================
     */

    private static Map<String, LineItemMetrics> aggregateLineItems(
        List<CampaignDataProvider.CampaignDay> rows
    ) {

        Map<String, LineItemMetrics> result =
            new Map<String, LineItemMetrics>();

        Map<String, List<CampaignDataProvider.CampaignDay>> rowsByLineItem =
            new Map<String, List<CampaignDataProvider.CampaignDay>>();


        if (
            rows == null ||
            rows.isEmpty()
        ) {
            return result;
        }


        for (
            CampaignDataProvider.CampaignDay row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.lineItemId)
            ) {
                continue;
            }


            String id =
                row.lineItemId.trim();


            if (
                !result.containsKey(id)
            ) {

                LineItemMetrics metrics =
                    new LineItemMetrics();

                metrics.lineItemId = id;

                result.put(
                    id,
                    metrics
                );

                rowsByLineItem.put(
                    id,
                    new List<CampaignDataProvider.CampaignDay>()
                );
            }


            rowsByLineItem
                .get(id)
                .add(row);


            LineItemMetrics item =
                result.get(id);


            item.impressions +=
                zeroIfNull(
                    row.adServerImpressions
                );

            item.clicks +=
                zeroIfNull(
                    row.adServerClicks
                );

            item.revenue +=
                zeroIfNull(
                    row.adServerRevenue
                );

            item.codeServed +=
                zeroIfNull(
                    row.codeServedCount
                );

            item.unfilled +=
                zeroIfNull(
                    row.totalUnfilledImpressions
                );

            item.measurable +=
                zeroIfNull(
                    row.activeViewMeasurableImpressions
                );

            item.viewable +=
                zeroIfNull(
                    row.activeViewViewableImpressions
                );


            if (
                String.isBlank(item.advertiser)
            ) {
                item.advertiser = row.advertiser;
            }

            if (
                String.isBlank(item.lineItemType)
            ) {
                item.lineItemType = row.lineItemType;
            }

            if (
                String.isBlank(item.creative)
            ) {
                item.creative = row.creative;
            }

            if (
                String.isBlank(item.adUnit)
            ) {
                item.adUnit = row.adUnit;
            }

            if (
                String.isBlank(item.goalType)
            ) {
                item.goalType = row.primaryGoalType;
            }

            if (
                item.goalUnits == null &&
                row.primaryGoalUnits != null
            ) {
                item.goalUnits =
                    row.primaryGoalUnits;
            }

            if (
                item.startDate == null &&
                row.lineItemStartDate != null
            ) {
                item.startDate =
                    row.lineItemStartDate;
            }

            if (
                item.endDate == null &&
                row.lineItemEndDate != null
            ) {
                item.endDate =
                    row.lineItemEndDate;
            }

            if (
                item.latestReportDate == null ||
                (
                    row.reportDate != null &&
                    row.reportDate >
                    item.latestReportDate
                )
            ) {
                item.latestReportDate =
                    row.reportDate;
            }
        }


        /*
         * ------------------------------------------------------------
         * DERIVED METRICS
         * ------------------------------------------------------------
         */

        for (
            String lineItemId :
            rowsByLineItem.keySet()
        ) {

            LineItemMetrics item =
                result.get(
                    lineItemId
                );

            List<CampaignDataProvider.CampaignDay> itemRows =
                rowsByLineItem.get(
                    lineItemId
                );


            sortCampaignDays(
                itemRows
            );


            Set<Date> dates =
                new Set<Date>();


            for (
                CampaignDataProvider.CampaignDay row :
                itemRows
            ) {

                if (
                    row != null &&
                    row.reportDate != null
                ) {
                    dates.add(
                        row.reportDate
                    );
                }
            }


            item.historicalDays =
                dates.size();


            if (
                item.historicalDays > 0
            ) {

                item.averageDailyImpressions =
                    item.impressions /
                    Decimal.valueOf(
                        item.historicalDays
                    );
            }


            calculateRecentMetrics(
                item,
                itemRows
            );


            item.ctr =
                safePercentage(
                    item.clicks,
                    item.impressions
                );

            item.cpm =
                calculateCpm(
                    item.revenue,
                    item.impressions
                );

            item.fillRate =
                calculateFillRateFromCodeServed(
                    item.impressions,
                    item.codeServed
                );

            item.viewability =
                safePercentage(
                    item.viewable,
                    item.measurable
                );
        }


        return result;
    }


    /*
     * ================================================================
     * RECENT METRICS
     * ================================================================
     */

    private static void calculateRecentMetrics(
        LineItemMetrics item,
        List<CampaignDataProvider.CampaignDay> rows
    ) {

        if (
            rows == null ||
            rows.isEmpty()
        ) {
            return;
        }


        Integer recentCount =
            rows.size() < 7
                ? rows.size()
                : 7;


        Integer recentStart =
            rows.size() -
            recentCount;


        Decimal recentTotal = 0;


        for (
            Integer i = recentStart;
            i < rows.size();
            i++
        ) {

            recentTotal +=
                zeroIfNull(
                    rows[i].adServerImpressions
                );
        }


        item.recent7DayAverage =
            recentTotal /
            Decimal.valueOf(
                recentCount
            );


        if (
            rows.size() >=
            recentCount * 2
        ) {

            Integer previousStart =
                recentStart -
                recentCount;

            Decimal previousTotal = 0;


            for (
                Integer i = previousStart;
                i < recentStart;
                i++
            ) {

                previousTotal +=
                    zeroIfNull(
                        rows[i].adServerImpressions
                    );
            }


            Decimal previousAverage =
                previousTotal /
                Decimal.valueOf(
                    recentCount
                );


            if (
                previousAverage > 0
            ) {

                item.recentTrend =
                    (
                        (
                            item.recent7DayAverage -
                            previousAverage
                        ) /
                        previousAverage
                    ) * 100;
            }
        }
    }


    /*
     * ================================================================
     * PORTFOLIO BENCHMARKS
     * ================================================================
     */

    private static Benchmark calculateBenchmark(
        List<LineItemMetrics> items
    ) {

        List<Decimal> ctrValues =
            new List<Decimal>();

        List<Decimal> cpmValues =
            new List<Decimal>();

        List<Decimal> fillValues =
            new List<Decimal>();

        for (
            LineItemMetrics item :
            items
        ) {

            if (
                item == null ||
                item.impressions <= 0
            ) {
                continue;
            }

            if (
                item.ctr != null
            ) {
                ctrValues.add(item.ctr);
            }

            if (
                item.cpm != null
            ) {
                cpmValues.add(item.cpm);
            }

            if (
                item.fillRate != null
            ) {
                fillValues.add(item.fillRate);
            }
        }


        Benchmark benchmark =
            new Benchmark();


        benchmark.medianCtr =
            calculateMedian(
                ctrValues
            );

        benchmark.medianCpm =
            calculateMedian(
                cpmValues
            );

        benchmark.medianFillRate =
            calculateMedian(
                fillValues
            );


        return benchmark;
    }


    /*
     * ================================================================
     * BASE RESULT
     * ================================================================
     */

    private static void populateBaseMetrics(
        OptimizationResult result,
        LineItemMetrics item
    ) {

        result.lineItemId =
            item.lineItemId;

        result.advertiser =
            item.advertiser;

        result.lineItemType =
            item.lineItemType;

        result.creative =
            item.creative;

        result.adUnit =
            item.adUnit;

        result.goalType =
            item.goalType;

        result.goalUnits =
            item.goalUnits;

        result.historicalImpressions =
            item.impressions;

        result.historicalClicks =
            item.clicks;

        result.historicalRevenue =
            item.revenue;

        /*
         * Daily dataset does not expose AdRequests.
         */
        result.historicalAdRequests = null;

        result.historicalCodeServedCount =
            item.codeServed;

        result.historicalUnfilledImpressions =
            item.unfilled;

        result.ctrPercentage =
            item.ctr;

        result.cpm =
            item.cpm;

        result.fillRatePercentage =
            item.fillRate;

        result.averageDailyImpressions =
            item.averageDailyImpressions;

        result.recent7DayAverageImpressions =
            item.recent7DayAverage;

        result.recentDeliveryTrendPercentage =
            item.recentTrend;
    }


    /*
     * ================================================================
     * BENCHMARK OUTPUT
     * ================================================================
     */

    private static void populateBenchmarks(
        OptimizationResult result,
        LineItemMetrics item,
        Benchmark benchmark
    ) {

        result.portfolioMedianCtrPercentage =
            benchmark.medianCtr;

        result.portfolioMedianCpm =
            benchmark.medianCpm;

        result.portfolioMedianFillRatePercentage =
            benchmark.medianFillRate;


        result.ctrVersusBenchmarkPercentage =
            calculateRelativePercentage(
                item.ctr,
                benchmark.medianCtr
            );

        result.cpmVersusBenchmarkPercentage =
            calculateRelativePercentage(
                item.cpm,
                benchmark.medianCpm
            );

        result.fillRateVersusBenchmarkPercentage =
            calculateRelativePercentage(
                item.fillRate,
                benchmark.medianFillRate
            );
    }


    /*
     * ================================================================
     * FACTUAL SIGNALS
     * ================================================================
     *
     * These are descriptive comparisons only.
     *
     * They do NOT imply a recommendation.
     * ================================================================
     */

    private static void calculateSignals(
        OptimizationResult result,
        LineItemMetrics item,
        Benchmark benchmark
    ) {

        if (
            item.goalUnits != null &&
            item.goalUnits > 0
        ) {

            if (
                item.impressions >=
                item.goalUnits
            ) {

                result.deliverySignal =
                    'DELIVERY_AT_OR_ABOVE_RECORDED_GOAL';

            } else {

                result.deliverySignal =
                    'DELIVERY_BELOW_RECORDED_GOAL';
            }

        } else {

            result.deliverySignal =
                'RECORDED_GOAL_NOT_AVAILABLE';
        }


        result.engagementSignal =
            compareMetricToBenchmark(
                item.ctr,
                benchmark.medianCtr,
                'CTR'
            );


        result.supplySignal =
            compareMetricToBenchmark(
                item.fillRate,
                benchmark.medianFillRate,
                'FILL_RATE'
            );


        result.yieldSignal =
            compareMetricToBenchmark(
                item.cpm,
                benchmark.medianCpm,
                'CPM'
            );
    }


    /*
     * ================================================================
     * OPTIMIZATION HEALTH / URGENCY
     * ================================================================
     *
     * Deterministic risk-tiering, computed once from the same
     * descriptive signals and data-quality status returned in the
     * evidence package. This is a classification calculation
     * (like deliveryRisk in CampaignForecastService), not a
     * recommendation - it does not select a targeting change, invent
     * a candidate, or imply an action was taken.
     *
     * Thresholds:
     *   Healthy       - delivery at/above recorded goal (or goal not
     *                    evaluable) AND at most 1 of the 3 benchmark
     *                    signals (engagement/supply/yield) is below the
     *                    portfolio median.
     *   At Risk       - delivery below recorded goal AND all 3 of the
     *                    benchmark signals are below median, OR data
     *                    quality status is LIMITED.
     *   Needs Attention - everything else (the middle tier).
     * ================================================================
     */

    private static void calculateOptimizationHealth(
        OptimizationResult result
    ) {

        Integer belowMedianCount =
            countBelowMedianSignals(
                result
            );

        Boolean deliveryBelowGoal =
            result.deliverySignal ==
            'DELIVERY_BELOW_RECORDED_GOAL';

        Boolean dataQualityLimited =
            result.dataQualityStatus == 'LIMITED';

        Optimization_Threshold__mdt thresholds =
            OptimizationDecisionEngine.getThresholds();

        if (
            dataQualityLimited ||
            (
                deliveryBelowGoal &&
                belowMedianCount >= thresholds.At_Risk_Below_Median_Count__c
            )
        ) {

            result.optimizationHealth = 'At Risk';
            result.optimizationUrgency = 'High';

        } else if (
            !deliveryBelowGoal &&
            belowMedianCount <= thresholds.Healthy_Max_Below_Median_Count__c
        ) {

            result.optimizationHealth = 'Healthy';
            result.optimizationUrgency = 'Low';

        } else {

            result.optimizationHealth = 'Needs Attention';
            result.optimizationUrgency = 'Medium';
        }
    }


    private static Integer countBelowMedianSignals(
        OptimizationResult result
    ) {

        Integer count = 0;

        List<String> signals =
            new List<String>{
                result.engagementSignal,
                result.supplySignal,
                result.yieldSignal
            };

        for (
            String signal :
            signals
        ) {

            if (
                signal != null &&
                signal.endsWith('_BELOW_PORTFOLIO_MEDIAN')
            ) {
                count++;
            }
        }

        return count;
    }


    private static String compareMetricToBenchmark(
        Decimal actual,
        Decimal benchmark,
        String metricName
    ) {

        if (
            actual == null ||
            benchmark == null ||
            benchmark <= 0
        ) {

            return
                metricName +
                '_NOT_EVALUABLE';
        }


        if (
            actual >= benchmark
        ) {

            return
                metricName +
                '_AT_OR_ABOVE_PORTFOLIO_MEDIAN';
        }


        return
            metricName +
            '_BELOW_PORTFOLIO_MEDIAN';
    }


    /*
     * ================================================================
     * SEGMENT AGGREGATION
     * ================================================================
     */

    private static List<SegmentSummary> aggregateSegments(
        List<CampaignDataProvider.SegmentPerformance> rows
    ) {

        Map<String, SegmentSummary> summaries =
            new Map<String, SegmentSummary>();


        if (
            rows == null
        ) {
            return new List<SegmentSummary>();
        }


        for (
            CampaignDataProvider.SegmentPerformance row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.segmentType) ||
                String.isBlank(row.segmentId)
            ) {
                continue;
            }


            String key =
                row.segmentType.trim().toUpperCase() +
                '|' +
                row.segmentId.trim();


            if (
                !summaries.containsKey(key)
            ) {

                SegmentSummary summary =
                    new SegmentSummary();

                summary.segmentType =
                    row.segmentType;

                summary.segmentId =
                    row.segmentId;

                summary.segmentName =
                    firstNonBlank(
                        row.segmentName,
                        row.placementName,
                        row.creativeSize,
                        row.daypart
                    );

                summary.country =
                    row.country;

                summary.state =
                    row.state;

                summary.city =
                    row.city;

                summary.dma =
                    row.dma;

                summary.audienceId =
                    row.audienceId;

                summary.audienceName =
                    row.audienceName;

                summary.deviceCategory =
                    row.deviceCategory;

                summary.platform =
                    row.platform;

                summary.placementId =
                    row.placementId;

                summary.placementName =
                    row.placementName;

                summary.adUnitPath =
                    row.adUnitPath;

                summary.creativeName =
                    row.creativeName;

                summary.creativeSize =
                    row.creativeSize;

                summary.daypart =
                    row.daypart;


                summaries.put(
                    key,
                    summary
                );
            }


            SegmentSummary summary =
                summaries.get(key);


            summary.impressions +=
                zeroIfNull(
                    row.impressions
                );

            summary.clicks +=
                zeroIfNull(
                    row.clicks
                );

            summary.revenue +=
                zeroIfNull(
                    row.revenue
                );

            summary.unfilled +=
                zeroIfNull(
                    row.unfilledImpressions
                );

            summary.measurable +=
                zeroIfNull(
                    row.measurableImpressions
                );

            summary.viewable +=
                zeroIfNull(
                    row.viewableImpressions
                );

            summary.requests +=
                zeroIfNull(
                    row.adRequests
                );

            summary.recordCount++;
        }


        for (
            SegmentSummary summary :
            summaries.values()
        ) {

            summary.ctr =
                safePercentage(
                    summary.clicks,
                    summary.impressions
                );

            summary.cpm =
                calculateCpm(
                    summary.revenue,
                    summary.impressions
                );


            summary.fillRate =
                safePercentage(
                    summary.impressions,
                    summary.requests
                );


            if (
                summary.fillRate == null
            ) {

                summary.fillRate =
                    calculateFillRate(
                        summary.impressions,
                        summary.unfilled
                    );
            }


            summary.viewability =
                safePercentage(
                    summary.viewable,
                    summary.measurable
                );
        }


        return new List<SegmentSummary>(
            summaries.values()
        );
    }


    /*
     * ================================================================
     * INVENTORY AGGREGATION
     * ================================================================
     */

    private static List<InventorySummary> aggregateInventory(
        List<CampaignDataProvider.InventoryAvailability> rows
    ) {

        Map<String, InventorySummary> summaries =
            new Map<String, InventorySummary>();


        if (
            rows == null
        ) {
            return new List<InventorySummary>();
        }


        for (
            CampaignDataProvider.InventoryAvailability row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.inventoryId)
            ) {
                continue;
            }


            String key =
                row.inventoryId.trim();


            if (
                !summaries.containsKey(key)
            ) {

                InventorySummary summary =
                    new InventorySummary();

                summary.inventoryId =
                    row.inventoryId;

                summary.placementId =
                    row.placementId;

                summary.placementName =
                    row.placementName;

                summary.adUnitPath =
                    row.adUnitPath;

                summary.creativeSize =
                    row.creativeSize;

                summary.country =
                    row.country;

                summary.state =
                    row.state;

                summary.city =
                    row.city;

                summary.dma =
                    row.dma;

                summary.deviceCategory =
                    row.deviceCategory;

                summary.platform =
                    row.platform;

                summary.inventoryType =
                    row.inventoryType;

                summary.isActive =
                    row.isActive;


                summaries.put(
                    key,
                    summary
                );
            }


            InventorySummary summary =
                summaries.get(key);


            summary.available +=
                zeroIfNull(
                    row.availableImpressions
                );

            summary.booked +=
                zeroIfNull(
                    row.bookedImpressions
                );

            summary.reserved +=
                zeroIfNull(
                    row.reservedImpressions
                );

            summary.remaining +=
                zeroIfNull(
                    row.remainingAvailableImpressions
                );

            summary.requests +=
                zeroIfNull(
                    row.adRequests
                );

            summary.historicalImpressions +=
                zeroIfNull(
                    row.historicalImpressions
                );

            summary.recordCount++;


            if (
                row.fillRatePercentage != null
            ) {

                summary.fillRate =
                    row.fillRatePercentage;

            }


            if (
                row.viewabilityPercentage != null
            ) {

                summary.viewability =
                    row.viewabilityPercentage;

            }


            if (
                row.ctrPercentage != null
            ) {

                summary.ctr =
                    row.ctrPercentage;

            }


            if (
                row.cpm != null
            ) {

                summary.cpm =
                    row.cpm;

            }
        }


        return new List<InventorySummary>(
            summaries.values()
        );
    }


    /*
     * ================================================================
     * TARGETING SUMMARY
     * ================================================================
     */

    private static TargetingSummary buildTargetingSummary(
        List<CampaignDataProvider.TargetingConfiguration> rows
    ) {

        TargetingSummary summary =
            new TargetingSummary();


        if (
            rows == null
        ) {
            return summary;
        }


        for (
            CampaignDataProvider.TargetingConfiguration row :
            rows
        ) {

            if (
                row == null ||
                !row.active
            ) {
                continue;
            }


            String type =
                String.isBlank(
                    row.targetingType
                )
                    ? 'UNKNOWN'
                    : row.targetingType.trim().toUpperCase();


            if (
                !summary.byType.containsKey(type)
            ) {

                summary.byType.put(
                    type,
                    new List<CampaignDataProvider.TargetingConfiguration>()
                );

                summary.activeTypes.add(
                    type
                );
            }


            summary.byType
                .get(type)
                .add(row);
        }


        return summary;
    }


    /*
     * ================================================================
     * CONTENTION SUMMARY
     * ================================================================
     */

    private static ContentionSummary buildContentionSummary(
        List<CampaignDataProvider.ContentionRecord> rows
    ) {

        ContentionSummary summary =
            new ContentionSummary();


        if (
            rows == null ||
            rows.isEmpty()
        ) {
            return summary;
        }


        for (
            CampaignDataProvider.ContentionRecord row :
            rows
        ) {

            if (
                row == null
            ) {
                continue;
            }


            summary.exists = true;

            if (
                summary.priority == null
            ) {
                summary.priority =
                    row.priority;
            }

            if (
                String.isBlank(summary.status)
            ) {
                summary.status =
                    row.lineItemStatus;
            }


            Map<String, Object> contentionRecord =
                new Map<String, Object>();

            contentionRecord.put(
                'orderId',
                row.orderId
            );

            contentionRecord.put(
                'orderName',
                row.orderName
            );

            contentionRecord.put(
                'advertiserName',
                row.advertiserName
            );

            contentionRecord.put(
                'lineItemId',
                row.lineItemId
            );

            contentionRecord.put(
                'priority',
                row.priority
            );

            contentionRecord.put(
                'lineItemStatus',
                row.lineItemStatus
            );

            contentionRecord.put(
                'goalType',
                row.goalType
            );

            contentionRecord.put(
                'goalUnits',
                row.goalUnits
            );

            contentionRecord.put(
                'startDate',
                row.startDate
            );

            contentionRecord.put(
                'endDate',
                row.endDate
            );

            contentionRecord.put(
                'bookedRate',
                row.bookedRate
            );

            contentionRecord.put(
                'currencyCode',
                row.currencyCode
            );

            contentionRecord.put(
                'frequencyCapPerUserPerDay',
                row.frequencyCapPerUserPerDay
            );

            contentionRecord.put(
                'competitiveExclusionGroup',
                row.competitiveExclusionGroup
            );


            summary.records.add(
                contentionRecord
            );
        }


        return summary;
    }


    /*
     * ================================================================
     * DATA QUALITY EVALUATION
     * ================================================================
     */

    private static DataQualitySummary evaluateDataQuality(
        LineItemMetrics target,
        List<CampaignDataProvider.SegmentPerformance> segmentRows,
        List<CampaignDataProvider.InventoryAvailability> inventoryRows,
        List<CampaignDataProvider.TargetingConfiguration> targetingRows,
        List<CampaignDataProvider.ContentionRecord> contentionRows,
        List<SegmentSummary> segmentSummaries,
        List<InventorySummary> inventorySummaries,
        TargetingSummary targetingSummary,
        ContentionSummary contentionSummary
    ) {

        DataQualitySummary quality =
            new DataQualitySummary();


        quality.dailyRowCount =
            target == null
                ? 0
                : target.historicalDays;

        quality.segmentRowCount =
            segmentRows == null
                ? 0
                : segmentRows.size();

        quality.inventoryRowCount =
            inventoryRows == null
                ? 0
                : inventoryRows.size();

        quality.targetingRowCount =
            targetingRows == null
                ? 0
                : targetingRows.size();

        quality.contentionRowCount =
            contentionRows == null
                ? 0
                : contentionRows.size();


        quality.segmentEvidenceAvailable =
            segmentSummaries != null &&
            !segmentSummaries.isEmpty();

        quality.inventoryEvidenceAvailable =
            inventorySummaries != null &&
            !inventorySummaries.isEmpty();

        quality.targetingEvidenceAvailable =
            targetingSummary != null &&
            !targetingSummary.activeTypes.isEmpty();

        quality.contentionEvidenceAvailable =
            contentionSummary != null &&
            contentionSummary.exists;


        /*
         * ------------------------------------------------------------
         * Missing evidence is not automatically an error.
         * It simply constrains what Atlas can conclude.
         * ------------------------------------------------------------
         */

        if (
            !quality.segmentEvidenceAvailable
        ) {

            quality.issues.add(
                'No segment-performance observations were available for the requested line item.'
            );
        }


        if (
            !quality.inventoryEvidenceAvailable
        ) {

            quality.issues.add(
                'No inventory-availability observations were available from the inventory dataset.'
            );
        }
        else {

            quality.issues.add(
                'Inventory observations are not line-item-keyed by the source contract; inventory eligibility for the requested line item is not proven by inventory rows alone.'
            );
        }


        if (
            !quality.targetingEvidenceAvailable
        ) {

            quality.issues.add(
                'No active targeting configuration was available for the requested line item.'
            );
        }


        if (
            !quality.contentionEvidenceAvailable
        ) {

            quality.issues.add(
                'No contention record was available for the requested line item.'
            );
        }


        if (
            target == null ||
            target.impressions == null ||
            target.impressions <= 0
        ) {

            quality.status =
                'LIMITED';
        }


        /*
         * ------------------------------------------------------------
         * Check advertiser consistency in segment data.
         * ------------------------------------------------------------
         */

        if (
            target != null &&
            !String.isBlank(target.advertiser) &&
            segmentRows != null
        ) {

            for (
                CampaignDataProvider.SegmentPerformance row :
                segmentRows
            ) {

                if (
                    row == null ||
                    String.isBlank(row.advertiserName)
                ) {
                    continue;
                }


                if (
                    row.advertiserName.trim() !=
                    target.advertiser.trim()
                ) {

                    quality.issues.add(
                        'A segment record contains an advertiser value that differs from the line-item daily dataset.'
                    );

                    break;
                }
            }
        }


        if (
            !quality.issues.isEmpty() &&
            quality.status == 'AVAILABLE'
        ) {

            quality.status =
                'AVAILABLE_WITH_LIMITATIONS';
        }


        return quality;
    }


    /*
     * ================================================================
     * CURRENT CONFIGURATION
     * ================================================================
     */

    private static String buildCurrentConfigurationText(
        List<CampaignDataProvider.TargetingConfiguration> rows
    ) {

        if (
            rows == null ||
            rows.isEmpty()
        ) {

            return
                'No active targeting configuration was returned.';
        }


        List<String> parts =
            new List<String>();


        for (
            CampaignDataProvider.TargetingConfiguration row :
            rows
        ) {

            if (
                row == null ||
                !row.active
            ) {
                continue;
            }


            String text =
                safeText(row.targetingType) +
                '=' +
                safeText(row.targetingName);


            if (
                !String.isBlank(
                    row.targetingId
                )
            ) {

                text +=
                    ' [' +
                    row.targetingId +
                    ']';
            }


            if (
                !String.isBlank(
                    row.includeExclude
                )
            ) {

                text +=
                    ' ' +
                    row.includeExclude;
            }


            if (
                !String.isBlank(
                    row.matchType
                )
            ) {

                text +=
                    ' ' +
                    row.matchType;
            }


            parts.add(text);
        }


        return
            parts.isEmpty()
                ? 'No active targeting configuration was returned.'
                : String.join(parts, '; ');
    }


    /*
     * ================================================================
     * EVIDENCE SUMMARY
     * ================================================================
     */

    private static String buildEvidenceSummary(
        LineItemMetrics target,
        Benchmark benchmark,
        List<SegmentSummary> segmentSummaries,
        List<InventorySummary> inventorySummaries,
        List<CampaignDataProvider.TargetingConfiguration> targetingRows,
        ContentionSummary contentionSummary,
        DataQualitySummary dataQuality
    ) {

        List<String> parts =
            new List<String>();


        parts.add(
            'Historical impressions=' +
            formatNumber(
                target.impressions
            )
        );

        parts.add(
            'CTR=' +
            formatNumber(
                target.ctr
            ) +
            '%'
        );

        parts.add(
            'CPM=' +
            formatNumber(
                target.cpm
            )
        );

        parts.add(
            'Fill rate=' +
            formatNumber(
                target.fillRate
            ) +
            '%'
        );

        parts.add(
            'Observed segment options=' +
            String.valueOf(
                segmentSummaries.size()
            )
        );

        parts.add(
            'Inventory observations=' +
            String.valueOf(
                inventorySummaries.size()
            )
        );

        parts.add(
            'Active targeting records=' +
            String.valueOf(
                targetingRows == null
                    ? 0
                    : targetingRows.size()
            )
        );

        parts.add(
            'Contention records=' +
            String.valueOf(
                contentionSummary.records.size()
            )
        );

        parts.add(
            'Data quality=' +
            dataQuality.status
        );


        return String.join(
            parts,
            '; '
        );
    }


    /*
     * ================================================================
     * OPTIMIZATION EVIDENCE PACKAGE
     * ================================================================
     *
     * This JSON is intentionally descriptive.
     *
     * It contains:
     *
     *   current state
     *   historical performance
     *   portfolio comparison
     *   segment observations
     *   inventory observations
     *   targeting configuration
     *   contention context
     *   data-quality limitations
     *
     * It does NOT contain an Apex-selected recommendation.
     * ================================================================
     */

    private static String buildOptimizationEvidence(
        LineItemMetrics target,
        Benchmark benchmark,
        List<SegmentSummary> segmentSummaries,
        List<InventorySummary> inventorySummaries,
        List<CampaignDataProvider.TargetingConfiguration> targetingRows,
        ContentionSummary contentionSummary,
        DataQualitySummary dataQuality,
        OptimizationResult result
    ) {

        Map<String, Object> payload =
            new Map<String, Object>();


        payload.put(
            'analysisRole',
            'EVIDENCE_ONLY'
        );

        payload.put(
            'decisionOwner',
            'ATLAS_AGENTFORCE_REASONING'
        );

        payload.put(
            'finalRecommendationGeneratedByApex',
            false
        );

        payload.put(
            'humanApprovalRequired',
            true
        );


        /*
         * ------------------------------------------------------------
         * LINE ITEM
         * ------------------------------------------------------------
         */

        Map<String, Object> lineItem =
            new Map<String, Object>();

        lineItem.put(
            'lineItemId',
            target.lineItemId
        );

        lineItem.put(
            'advertiser',
            target.advertiser
        );

        lineItem.put(
            'lineItemType',
            target.lineItemType
        );

        lineItem.put(
            'creative',
            target.creative
        );

        lineItem.put(
            'adUnit',
            target.adUnit
        );

        lineItem.put(
            'goalType',
            target.goalType
        );

        lineItem.put(
            'goalUnits',
            target.goalUnits
        );

        lineItem.put(
            'startDate',
            target.startDate
        );

        lineItem.put(
            'endDate',
            target.endDate
        );

        lineItem.put(
            'latestReportDate',
            target.latestReportDate
        );


        payload.put(
            'lineItem',
            lineItem
        );


        /*
         * ------------------------------------------------------------
         * PERFORMANCE
         * ------------------------------------------------------------
         */

        Map<String, Object> performance =
            new Map<String, Object>();

        performance.put(
            'historicalImpressions',
            target.impressions
        );

        performance.put(
            'historicalClicks',
            target.clicks
        );

        performance.put(
            'historicalRevenue',
            target.revenue
        );

        performance.put(
            'historicalCodeServedCount',
            target.codeServed
        );

        performance.put(
            'historicalUnfilledImpressions',
            target.unfilled
        );

        performance.put(
            'averageDailyImpressions',
            target.averageDailyImpressions
        );

        performance.put(
            'recent7DayAverageImpressions',
            target.recent7DayAverage
        );

        performance.put(
            'recentDeliveryTrendPercentage',
            target.recentTrend
        );

        performance.put(
            'ctrPercentage',
            target.ctr
        );

        performance.put(
            'cpm',
            target.cpm
        );

        performance.put(
            'fillRatePercentage',
            target.fillRate
        );


        payload.put(
            'historicalPerformance',
            performance
        );


        /*
         * ------------------------------------------------------------
         * PORTFOLIO COMPARISON
         * ------------------------------------------------------------
         */

        Map<String, Object> benchmarks =
            new Map<String, Object>();

        benchmarks.put(
            'medianCtr',
            benchmark.medianCtr
        );

        benchmarks.put(
            'medianCpm',
            benchmark.medianCpm
        );

        benchmarks.put(
            'medianFillRate',
            benchmark.medianFillRate
        );

        benchmarks.put(
            'ctrVersusMedianPercentage',
            result.ctrVersusBenchmarkPercentage
        );

        benchmarks.put(
            'cpmVersusMedianPercentage',
            result.cpmVersusBenchmarkPercentage
        );

        benchmarks.put(
            'fillRateVersusMedianPercentage',
            result.fillRateVersusBenchmarkPercentage
        );


        payload.put(
            'portfolioComparison',
            benchmarks
        );


        /*
         * ------------------------------------------------------------
         * DESCRIPTIVE SIGNALS
         * ------------------------------------------------------------
         */

        Map<String, Object> signals =
            new Map<String, Object>();

        signals.put(
            'delivery',
            result.deliverySignal
        );

        signals.put(
            'engagement',
            result.engagementSignal
        );

        signals.put(
            'supply',
            result.supplySignal
        );

        signals.put(
            'yield',
            result.yieldSignal
        );


        payload.put(
            'descriptiveSignals',
            signals
        );


        /*
         * ------------------------------------------------------------
         * DETERMINISTIC HEALTH / URGENCY
         *
         * Calculated once in Apex (see calculateOptimizationHealth).
         * Atlas must use these values as-is; it must not re-derive
         * health or urgency itself.
         * ------------------------------------------------------------
         */

        payload.put(
            'optimizationHealth',
            result.optimizationHealth
        );

        payload.put(
            'optimizationUrgency',
            result.optimizationUrgency
        );


        /*
         * ------------------------------------------------------------
         * TARGETING
         * ------------------------------------------------------------
         */

        List<Object> targetingEvidence =
            new List<Object>();


        if (
            targetingRows != null
        ) {

            for (
                CampaignDataProvider.TargetingConfiguration row :
                targetingRows
            ) {

                if (
                    row == null
                ) {
                    continue;
                }


                Map<String, Object> targetRecord =
                    new Map<String, Object>();

                targetRecord.put(
                    'lineItemId',
                    row.lineItemId
                );

                targetRecord.put(
                    'targetingType',
                    row.targetingType
                );

                targetRecord.put(
                    'targetingId',
                    row.targetingId
                );

                targetRecord.put(
                    'targetingName',
                    row.targetingName
                );

                targetRecord.put(
                    'includeExclude',
                    row.includeExclude
                );

                targetRecord.put(
                    'matchType',
                    row.matchType
                );

                targetRecord.put(
                    'active',
                    row.active
                );


                targetingEvidence.add(
                    targetRecord
                );
            }
        }


        payload.put(
            'currentTargeting',
            targetingEvidence
        );


        /*
         * ------------------------------------------------------------
         * OBSERVED SEGMENT OPTIONS
         * ------------------------------------------------------------
         *
         * These are observations, not recommendations.
         * ============================================================
         */

        List<Object> segmentEvidence =
            new List<Object>();


        if (
            segmentSummaries != null
        ) {

            for (
                SegmentSummary segment :
                segmentSummaries
            ) {

                Map<String, Object> segmentRecord =
                    new Map<String, Object>();


                segmentRecord.put(
                    'observationType',
                    'HISTORICAL_SEGMENT_OBSERVATION'
                );

                segmentRecord.put(
                    'segmentType',
                    segment.segmentType
                );

                segmentRecord.put(
                    'segmentId',
                    segment.segmentId
                );

                segmentRecord.put(
                    'segmentName',
                    segment.segmentName
                );

                segmentRecord.put(
                    'country',
                    segment.country
                );

                segmentRecord.put(
                    'state',
                    segment.state
                );

                segmentRecord.put(
                    'city',
                    segment.city
                );

                segmentRecord.put(
                    'dma',
                    segment.dma
                );

                segmentRecord.put(
                    'audienceId',
                    segment.audienceId
                );

                segmentRecord.put(
                    'audienceName',
                    segment.audienceName
                );

                segmentRecord.put(
                    'deviceCategory',
                    segment.deviceCategory
                );

                segmentRecord.put(
                    'platform',
                    segment.platform
                );

                segmentRecord.put(
                    'placementId',
                    segment.placementId
                );

                segmentRecord.put(
                    'placementName',
                    segment.placementName
                );

                segmentRecord.put(
                    'adUnitPath',
                    segment.adUnitPath
                );

                segmentRecord.put(
                    'creativeName',
                    segment.creativeName
                );

                segmentRecord.put(
                    'creativeSize',
                    segment.creativeSize
                );

                segmentRecord.put(
                    'daypart',
                    segment.daypart
                );

                segmentRecord.put(
                    'impressions',
                    segment.impressions
                );

                segmentRecord.put(
                    'clicks',
                    segment.clicks
                );

                segmentRecord.put(
                    'revenue',
                    segment.revenue
                );

                segmentRecord.put(
                    'requests',
                    segment.requests
                );

                segmentRecord.put(
                    'unfilledImpressions',
                    segment.unfilled
                );

                segmentRecord.put(
                    'ctrPercentage',
                    segment.ctr
                );

                segmentRecord.put(
                    'cpm',
                    segment.cpm
                );

                segmentRecord.put(
                    'fillRatePercentage',
                    segment.fillRate
                );

                segmentRecord.put(
                    'viewabilityPercentage',
                    segment.viewability
                );

                segmentRecord.put(
                    'recordCount',
                    segment.recordCount
                );


                /*
                 * A segment row is observational.
                 * It does NOT prove that the line item can use it.
                 */
                segmentRecord.put(
                    'configurationEligibility',
                    determineSegmentEligibility(
                        segment,
                        targetingRows
                    )
                );


                segmentEvidence.add(
                    segmentRecord
                );
            }
        }


        payload.put(
            'observedSegmentOptions',
            segmentEvidence
        );


        /*
         * ------------------------------------------------------------
         * INVENTORY OPTIONS
         * ------------------------------------------------------------
         *
         * Inventory data in the source contract is not line-item keyed.
         *
         * Therefore these observations are explicitly marked as not
         * proving line-item eligibility.
         * ------------------------------------------------------------
         */

        List<Object> inventoryEvidence =
            new List<Object>();


        if (
            inventorySummaries != null
        ) {

            for (
                InventorySummary inventory :
                inventorySummaries
            ) {

                Map<String, Object> inventoryRecord =
                    new Map<String, Object>();

                inventoryRecord.put(
                    'observationType',
                    'INVENTORY_AVAILABILITY_OBSERVATION'
                );

                inventoryRecord.put(
                    'inventoryId',
                    inventory.inventoryId
                );

                inventoryRecord.put(
                    'placementId',
                    inventory.placementId
                );

                inventoryRecord.put(
                    'placementName',
                    inventory.placementName
                );

                inventoryRecord.put(
                    'adUnitPath',
                    inventory.adUnitPath
                );

                inventoryRecord.put(
                    'creativeSize',
                    inventory.creativeSize
                );

                inventoryRecord.put(
                    'country',
                    inventory.country
                );

                inventoryRecord.put(
                    'state',
                    inventory.state
                );

                inventoryRecord.put(
                    'city',
                    inventory.city
                );

                inventoryRecord.put(
                    'dma',
                    inventory.dma
                );

                inventoryRecord.put(
                    'deviceCategory',
                    inventory.deviceCategory
                );

                inventoryRecord.put(
                    'platform',
                    inventory.platform
                );

                inventoryRecord.put(
                    'inventoryType',
                    inventory.inventoryType
                );

                inventoryRecord.put(
                    'availableImpressions',
                    inventory.available
                );

                inventoryRecord.put(
                    'bookedImpressions',
                    inventory.booked
                );

                inventoryRecord.put(
                    'reservedImpressions',
                    inventory.reserved
                );

                inventoryRecord.put(
                    'remainingAvailableImpressions',
                    inventory.remaining
                );

                inventoryRecord.put(
                    'adRequests',
                    inventory.requests
                );

                inventoryRecord.put(
                    'historicalImpressions',
                    inventory.historicalImpressions
                );

                inventoryRecord.put(
                    'fillRatePercentage',
                    inventory.fillRate
                );

                inventoryRecord.put(
                    'viewabilityPercentage',
                    inventory.viewability
                );

                inventoryRecord.put(
                    'ctrPercentage',
                    inventory.ctr
                );

                inventoryRecord.put(
                    'cpm',
                    inventory.cpm
                );

                inventoryRecord.put(
                    'isActive',
                    inventory.isActive
                );

                inventoryRecord.put(
                    'lineItemEligibility',
                    determineInventoryEligibility(
                        inventory,
                        targetingRows
                    )
                );


                inventoryEvidence.add(
                    inventoryRecord
                );
            }
        }


        payload.put(
            'observedInventoryOptions',
            inventoryEvidence
        );


        /*
         * ------------------------------------------------------------
         * CONTENTION
         * ------------------------------------------------------------
         */

        payload.put(
            'contentionContext',
            new Map<String, Object>{
                'exists' => contentionSummary.exists,
                'priority' => contentionSummary.priority,
                'status' => contentionSummary.status,
                'records' =>
                    contentionSummary.records
            }
        );


        /*
         * ------------------------------------------------------------
         * DATA QUALITY
         * ------------------------------------------------------------
         */

        payload.put(
            'dataQuality',
            new Map<String, Object>{
                'status' => dataQuality.status,
                'issues' => dataQuality.issues,
                'dailyHistoricalDays' =>
                    dataQuality.dailyRowCount,
                'segmentRowCount' =>
                    dataQuality.segmentRowCount,
                'inventoryRowCount' =>
                    dataQuality.inventoryRowCount,
                'targetingRowCount' =>
                    dataQuality.targetingRowCount,
                'contentionRowCount' =>
                    dataQuality.contentionRowCount,
                'segmentEvidenceAvailable' =>
                    dataQuality.segmentEvidenceAvailable,
                'inventoryEvidenceAvailable' =>
                    dataQuality.inventoryEvidenceAvailable,
                'targetingEvidenceAvailable' =>
                    dataQuality.targetingEvidenceAvailable,
                'contentionEvidenceAvailable' =>
                    dataQuality.contentionEvidenceAvailable
            }
        );


        /*
         * ------------------------------------------------------------
         * REASONING GUARDRAILS FOR ATLAS
         * ------------------------------------------------------------
         */

        payload.put(
            'reasoningConstraints',
            new List<String>{
                'Treat this payload as factual analytical evidence, not as a preselected recommendation.',
                'Select a recommendation only from evidence explicitly present in this payload.',
                'Do not invent targeting values, geography, audiences, placements, creative sizes, allocations, metrics, or expected uplift.',
                'Do not infer line-item inventory eligibility from inventory observations when the source does not prove that relationship.',
                'Do not convert historical observational performance into guaranteed future performance.',
                'When evidence is insufficient or conflicting, return no specific configuration change and explain the limitation.',
                'Human approval is required before any future operational apply action.'
            }
        );


        return JSON.serialize(payload);
    }


    /*
     * ================================================================
     * SEGMENT ELIGIBILITY / RELATIONSHIP CHECK
     * ================================================================
     *
     * This does NOT claim true ad-server eligibility.
     *
     * It only determines what can be established from the supplied
     * targeting data.
     * ================================================================
     */

    private static String determineSegmentEligibility(
        SegmentSummary segment,
        List<CampaignDataProvider.TargetingConfiguration> targetingRows
    ) {

        if (
            segment == null
        ) {
            return 'NOT_PROVEN';
        }


        if (
            targetingRows == null ||
            targetingRows.isEmpty()
        ) {
            return 'NOT_PROVEN_NO_TARGETING_DATA';
        }


        Boolean matchingType =
            false;

        Boolean matchingValue =
            false;


        for (
            CampaignDataProvider.TargetingConfiguration row :
            targetingRows
        ) {

            if (
                row == null ||
                !row.active
            ) {
                continue;
            }


            if (
                String.isBlank(row.targetingType)
            ) {
                continue;
            }


            String targetingType =
                row.targetingType.trim().toUpperCase();

            String segmentType =
                String.isBlank(segment.segmentType)
                    ? null
                    : segment.segmentType.trim().toUpperCase();


            if (
                targetingType ==
                segmentType
            ) {

                matchingType = true;


                if (
                    sameNonBlank(
                        row.targetingId,
                        segment.segmentId
                    ) ||
                    sameNonBlank(
                        row.targetingName,
                        segment.segmentName
                    )
                ) {

                    matchingValue = true;
                    break;
                }
            }
        }


        if (
            matchingValue
        ) {
            return 'CURRENT_TARGETING_MATCH';
        }


        if (
            matchingType
        ) {
            return 'SAME_TARGETING_DIMENSION_VALUE_NOT_PROVEN';
        }


        return 'NOT_PROVEN';
    }


    /*
     * ================================================================
     * INVENTORY ELIGIBILITY / DIMENSION MATCH
     * ================================================================
     *
     * The inventory dataset is not line-item-keyed, so true ad-server
     * eligibility cannot be proven from this source alone.
     *
     * What CAN be established deterministically is whether an
     * inventory row shares concrete targeting dimensions (placement,
     * geography/DMA, device/platform, creative size) with the line
     * item's own ACTIVE targeting configuration.
     *
     * This is dimension-matching evidence, not a live GAM eligibility
     * check. Atlas must present it as such.
     * ================================================================
     */

    private static String determineInventoryEligibility(
        InventorySummary inventory,
        List<CampaignDataProvider.TargetingConfiguration> targetingRows
    ) {

        if (
            inventory == null ||
            targetingRows == null ||
            targetingRows.isEmpty()
        ) {
            return 'NOT_PROVEN_NO_TARGETING_DATA';
        }


        Set<String> placementValues =
            new Set<String>();

        Set<String> dmaValues =
            new Set<String>();

        Set<String> deviceValues =
            new Set<String>();

        Set<String> creativeSizeValues =
            new Set<String>();


        for (
            CampaignDataProvider.TargetingConfiguration row :
            targetingRows
        ) {

            if (
                row == null ||
                !row.active ||
                String.isBlank(row.targetingType)
            ) {
                continue;
            }

            String type =
                row.targetingType.trim().toUpperCase();

            if (type == 'PLACEMENT') {

                addIfNotBlank(
                    placementValues,
                    row.targetingId
                );

                addIfNotBlank(
                    placementValues,
                    row.targetingName
                );

            } else if (type == 'GEOGRAPHY') {

                addIfNotBlank(
                    dmaValues,
                    row.targetingId
                );

                addIfNotBlank(
                    dmaValues,
                    row.targetingName
                );

            } else if (type == 'DEVICE_PLATFORM') {

                addIfNotBlank(
                    deviceValues,
                    row.targetingId
                );

                addIfNotBlank(
                    deviceValues,
                    row.targetingName
                );

            } else if (type == 'CREATIVE_SIZE') {

                addIfNotBlank(
                    creativeSizeValues,
                    row.targetingId
                );

                addIfNotBlank(
                    creativeSizeValues,
                    row.targetingName
                );
            }
        }


        Integer matchedDimensions = 0;

        List<String> matchedOn =
            new List<String>();

        if (
            containsIgnoreCase(
                placementValues,
                inventory.placementId
            ) ||
            containsIgnoreCase(
                placementValues,
                inventory.placementName
            )
        ) {
            matchedDimensions++;
            matchedOn.add('PLACEMENT');
        }

        if (
            containsIgnoreCase(
                dmaValues,
                inventory.dma
            )
        ) {
            matchedDimensions++;
            matchedOn.add('GEOGRAPHY');
        }

        if (
            containsDevicePlatformMatch(
                deviceValues,
                inventory.deviceCategory,
                inventory.platform
            )
        ) {
            matchedDimensions++;
            matchedOn.add('DEVICE_PLATFORM');
        }

        if (
            containsIgnoreCase(
                creativeSizeValues,
                inventory.creativeSize
            )
        ) {
            matchedDimensions++;
            matchedOn.add('CREATIVE_SIZE');
        }


        if (matchedDimensions >= 2) {
            return
                'ELIGIBLE_MULTI_DIMENSION_MATCH:' +
                String.join(matchedOn, '+');
        }

        if (matchedDimensions == 1) {
            return
                'ELIGIBLE_SINGLE_DIMENSION_MATCH:' +
                String.join(matchedOn, '+');
        }

        return 'NOT_PROVEN';
    }


    private static void addIfNotBlank(
        Set<String> values,
        String value
    ) {

        if (!String.isBlank(value)) {
            values.add(value.trim().toLowerCase());
        }
    }


    private static Boolean containsIgnoreCase(
        Set<String> values,
        String value
    ) {

        if (
            String.isBlank(value) ||
            values == null ||
            values.isEmpty()
        ) {
            return false;
        }

        return values.contains(value.trim().toLowerCase());
    }


    private static Boolean containsDevicePlatformMatch(
        Set<String> deviceValues,
        String deviceCategory,
        String platform
    ) {

        if (
            deviceValues == null ||
            deviceValues.isEmpty()
        ) {
            return false;
        }

        String combined =
            (
                zeroIfBlank(deviceCategory) +
                '_' +
                zeroIfBlank(platform)
            ).trim().toLowerCase();

        if (deviceValues.contains(combined)) {
            return true;
        }

        return
            containsIgnoreCase(
                deviceValues,
                deviceCategory
            ) ||
            containsIgnoreCase(
                deviceValues,
                platform
            );
    }


    private static String zeroIfBlank(
        String value
    ) {

        return
            String.isBlank(value)
                ? ''
                : value.trim();
    }


    /*
     * ================================================================
     * MEDIAN
     * ================================================================
     */

    private static Decimal calculateMedian(
        List<Decimal> values
    ) {

        if (
            values == null ||
            values.isEmpty()
        ) {
            return null;
        }


        List<Decimal> sorted =
            new List<Decimal>();


        for (
            Decimal value :
            values
        ) {

            if (
                value != null
            ) {
                sorted.add(value);
            }
        }


        if (
            sorted.isEmpty()
        ) {
            return null;
        }


        sorted.sort();


        Integer size =
            sorted.size();

        Integer middle =
            size / 2;


        if (
            Math.mod(
                size,
                2
            ) == 0
        ) {

            return
                (
                    sorted[middle - 1] +
                    sorted[middle]
                ) / 2;
        }


        return sorted[middle];
    }


    /*
     * ================================================================
     * CALCULATIONS
     * ================================================================
     */

    private static Decimal safePercentage(
        Decimal numerator,
        Decimal denominator
    ) {

        if (
            denominator == null ||
            denominator <= 0
        ) {
            return null;
        }


        return
            (
                zeroIfNull(numerator) /
                denominator
            ) * 100;
    }


    private static Decimal calculateCpm(
        Decimal revenue,
        Decimal impressions
    ) {

        if (
            impressions == null ||
            impressions <= 0
        ) {
            return null;
        }


        return
            (
                zeroIfNull(revenue) /
                impressions
            ) * 1000;
    }


    private static Decimal calculateFillRateFromCodeServed(
        Decimal impressions,
        Decimal codeServed
    ) {

        if (
            codeServed == null ||
            codeServed <= 0
        ) {
            return null;
        }


        return
            (
                zeroIfNull(impressions) /
                codeServed
            ) * 100;
    }


    private static Decimal calculateFillRate(
        Decimal impressions,
        Decimal unfilled
    ) {

        Decimal served =
            zeroIfNull(impressions);

        Decimal unfilledValue =
            zeroIfNull(unfilled);

        Decimal opportunity =
            served +
            unfilledValue;


        if (
            opportunity <= 0
        ) {
            return null;
        }


        return
            (
                served /
                opportunity
            ) * 100;
    }


    private static Decimal calculateRelativePercentage(
        Decimal actual,
        Decimal benchmark
    ) {

        if (
            actual == null ||
            benchmark == null ||
            benchmark == 0
        ) {
            return null;
        }


        return
            (
                (
                    actual -
                    benchmark
                ) /
                benchmark
            ) * 100;
    }


    private static Decimal zeroIfNull(
        Decimal value
    ) {

        return
            value == null
                ? 0
                : value;
    }


    /*
     * ================================================================
     * GENERAL HELPERS
     * ================================================================
     */

    private static Boolean sameNonBlank(
        String firstValue,
        String secondValue
    ) {

        return
            !String.isBlank(firstValue) &&
            !String.isBlank(secondValue) &&
            firstValue.trim() ==
            secondValue.trim();
    }


    private static String safeText(
        Object value
    ) {

        if (
            value == null
        ) {
            return 'N/A';
        }


        String text =
            String.valueOf(value);


        return
            String.isBlank(text)
                ? 'N/A'
                : text;
    }


    private static String firstNonBlank(
        String firstValue,
        String secondValue,
        String thirdValue,
        String fourthValue
    ) {

        if (
            !String.isBlank(firstValue)
        ) {
            return firstValue;
        }

        if (
            !String.isBlank(secondValue)
        ) {
            return secondValue;
        }

        if (
            !String.isBlank(thirdValue)
        ) {
            return thirdValue;
        }

        if (
            !String.isBlank(fourthValue)
        ) {
            return fourthValue;
        }

        return null;
    }


    private static String formatNumber(
        Decimal value
    ) {

        if (
            value == null
        ) {
            return 'N/A';
        }


        return
            String.valueOf(
                value.setScale(
                    2,
                    System.RoundingMode.HALF_UP
                )
            );
    }


    private static String joinIssues(
        List<String> issues
    ) {

        if (
            issues == null ||
            issues.isEmpty()
        ) {
            return null;
        }


        return String.join(
            issues,
            ' | '
        );
    }


    /*
     * ================================================================
     * SAFE DATA ACCESS
     * ================================================================
     */

    private static List<CampaignDataProvider.SegmentPerformance>
    safeGetSegmentPerformance(
        String lineItemId
    ) {

        try {

            return
                CampaignDataProvider.getSegmentPerformance(
                    lineItemId
                );

        } catch (Exception e) {

            return
                new List<CampaignDataProvider.SegmentPerformance>();
        }
    }


    private static List<CampaignDataProvider.InventoryAvailability>
    safeGetInventoryAvailability(
        String lineItemId
    ) {

        try {

            return
                CampaignDataProvider.getInventoryAvailability(
                    lineItemId
                );

        } catch (Exception e) {

            return
                new List<CampaignDataProvider.InventoryAvailability>();
        }
    }


    private static List<CampaignDataProvider.TargetingConfiguration>
    safeGetTargetingConfiguration(
        String lineItemId
    ) {

        try {

            return
                CampaignDataProvider.getTargetingConfiguration(
                    lineItemId
                );

        } catch (Exception e) {

            return
                new List<CampaignDataProvider.TargetingConfiguration>();
        }
    }


    private static List<CampaignDataProvider.ContentionRecord>
    safeGetContentionData(
        String lineItemId
    ) {

        try {

            return
                CampaignDataProvider.getContentionData(
                    lineItemId
                );

        } catch (Exception e) {

            return
                new List<CampaignDataProvider.ContentionRecord>();
        }
    }


    /*
     * ================================================================
     * DAILY SORT
     * ================================================================
     */

    private static void sortCampaignDays(
        List<CampaignDataProvider.CampaignDay> rows
    ) {

        if (
            rows == null ||
            rows.size() < 2
        ) {
            return;
        }


        for (
            Integer i = 1;
            i < rows.size();
            i++
        ) {

            CampaignDataProvider.CampaignDay current =
                rows[i];

            Integer j =
                i - 1;


            while (
                j >= 0 &&
                comesAfter(
                    rows[j],
                    current
                )
            ) {

                rows[j + 1] =
                    rows[j];

                j--;
            }


            rows[j + 1] =
                current;
        }
    }


    private static Boolean comesAfter(
        CampaignDataProvider.CampaignDay left,
        CampaignDataProvider.CampaignDay right
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


        return
            left.reportDate >
            right.reportDate;
    }


    /*
     * ================================================================
     * EXCEPTION
     * ================================================================
     */

    public class OptimizationException
        extends Exception {
    }
}