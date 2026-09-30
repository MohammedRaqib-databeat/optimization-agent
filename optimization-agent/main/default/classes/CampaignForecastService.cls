public with sharing class CampaignForecastService {

    /*
     * ================================================================
     * DATA-DRIVEN FORECAST ENGINE
     *
     * Input:
     *     Line Item ID only.
     *
     * Source:
     *     CampaignDataProvider
     *
     * Important source rules:
     *
     * 1. GoalUnits comes from the daily delivery dataset.
     * 2. GoalType comes from the daily delivery dataset.
     * 3. The current CampaignDataProvider does not expose a
     *    GoalPercentage field.
     * 4. Therefore goalPercentage is deliberately returned as null.
     * 5. CodeServedCount is kept separate from AdRequests.
     * 6. No campaign-specific values are hardcoded.
     * ================================================================
     */


    /*
     * ================================================================
     * REQUEST
     * ================================================================
     */

    public class ForecastRequest {

        @InvocableVariable(
            label='Line Item ID'
            required=true
        )
        public String lineItemId;
    }


    /*
     * ================================================================
     * RESULT
     * ================================================================
     */

    public class ForecastResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Line Item ID')
        public String lineItemId;

        @InvocableVariable(label='Line Item Type')
        public String lineItemType;

        @InvocableVariable(label='Advertiser')
        public String advertiser;

        @InvocableVariable(label='Creative')
        public String creative;

        @InvocableVariable(label='Ad Unit')
        public String adUnit;

        @InvocableVariable(label='Goal Type')
        public String goalType;

        @InvocableVariable(label='Goal Units')
        public Decimal goalUnits;

        /*
         * The current provider does not expose a goal-percentage field.
         * This remains null rather than being fabricated.
         */
        @InvocableVariable(label='Goal Percentage')
        public Decimal goalPercentage;

        @InvocableVariable(label='Campaign Start Date')
        public Date campaignStartDate;

        @InvocableVariable(label='Campaign End Date')
        public Date campaignEndDate;

        @InvocableVariable(label='Forecast As Of Date')
        public Date forecastAsOfDate;

        @InvocableVariable(label='Historical Days')
        public Decimal historicalDays;

        @InvocableVariable(label='Historical Impressions')
        public Decimal historicalImpressions;

        @InvocableVariable(label='Average Daily Impressions')
        public Decimal averageDailyImpressions;

        @InvocableVariable(label='Recent 7 Day Average Impressions')
        public Decimal recent7DayAverageImpressions;

        @InvocableVariable(label='Recent Delivery Trend Percentage')
        public Decimal recentDeliveryTrendPercentage;

        @InvocableVariable(label='Campaign Days Elapsed')
        public Decimal campaignDaysElapsed;

        @InvocableVariable(label='Campaign Days Remaining')
        public Decimal campaignDaysRemaining;

        @InvocableVariable(label='Projected Remaining Impressions')
        public Decimal projectedRemainingImpressions;

        @InvocableVariable(label='Projected End Impressions')
        public Decimal projectedEndImpressions;

        @InvocableVariable(label='Projected Goal Attainment Percentage')
        public Decimal projectedGoalAttainmentPercentage;

        @InvocableVariable(label='Required Daily Impressions')
        public Decimal requiredDailyImpressions;

        /*
         * Daily-goal-type line items are evaluated against the source
         * dataset's own daily impression target, when present, instead
         * of an absolute lifetime goal.
         */
        @InvocableVariable(label='Daily Target Impressions')
        public Decimal dailyTargetImpressions;

        @InvocableVariable(label='Pacing Percentage')
        public Decimal pacingPercentage;

        @InvocableVariable(label='Delivery Risk')
        public String deliveryRisk;

        @InvocableVariable(label='CPM')
        public Decimal cpm;

        @InvocableVariable(label='CTR Percentage')
        public Decimal ctrPercentage;

        @InvocableVariable(label='Fill Rate Percentage')
        public Decimal fillRatePercentage;

        @InvocableVariable(label='Total Clicks')
        public Decimal totalClicks;

        @InvocableVariable(label='Total Revenue')
        public Decimal totalRevenue;

        /*
         * The source dataset does not provide AdRequests.
         * This is deliberately left null.
         */
        @InvocableVariable(
            label='Total Ad Requests'
        )
        public Decimal totalAdRequests;

        @InvocableVariable(
            label='Total Code Served Count'
        )
        public Decimal totalCodeServedCount;

        @InvocableVariable(
            label='Total Unfilled Impressions'
        )
        public Decimal totalUnfilledImpressions;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    /*
     * ================================================================
     * INVOCABLE METHOD
     * ================================================================
     */

    @InvocableMethod(
        label='Forecast Campaign From Historical Delivery'
        description='Calculates a data-driven line item forecast from historical daily delivery records.'
    )
    public static List<ForecastResult> forecast(
        List<ForecastRequest> requests
    ) {

        List<ForecastResult> results =
            new List<ForecastResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        for (
            ForecastRequest request :
            requests
        ) {

            ForecastResult result =
                new ForecastResult();

            result.success =
                false;

            try {

                if (
                    request == null ||
                    String.isBlank(
                        request.lineItemId
                    )
                ) {

                    throw new ForecastException(
                        'Line Item ID is required.'
                    );
                }

                result.lineItemId =
                    request.lineItemId.trim();

                List<CampaignDataProvider.CampaignDay> rows =
                    CampaignDataProvider.getLineItemData(
                        result.lineItemId
                    );

                calculateForecast(
                    rows,
                    result
                );

                result.success =
                    true;

            } catch (Exception e) {

                result.success =
                    false;

                result.status =
                    'ERROR';

                result.explanation =
                    e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    /*
     * ================================================================
     * MAIN FORECAST CALCULATION
     * ================================================================
     */

    private static void calculateForecast(
        List<CampaignDataProvider.CampaignDay> rows,
        ForecastResult result
    ) {

        if (
            rows == null ||
            rows.isEmpty()
        ) {

            throw new ForecastException(
                'No historical delivery records were returned.'
            );
        }

        CampaignDataProvider.CampaignDay firstRow =
            rows[0];

        CampaignDataProvider.CampaignDay lastRow =
            rows[rows.size() - 1];


        /*
         * ============================================================
         * SOURCE METADATA
         * ============================================================
         */

        result.lineItemType =
            firstRow.lineItemType;

        result.advertiser =
            firstRow.advertiser;

        result.creative =
            firstRow.creative;

        result.adUnit =
            firstRow.adUnit;

        result.goalType =
            firstRow.primaryGoalType;

        result.goalUnits =
            firstRow.primaryGoalUnits;

        /*
         * CampaignDataProvider does not expose a goal percentage.
         * Do not manufacture one.
         */
        result.goalPercentage =
            null;

        result.campaignStartDate =
            firstRow.lineItemStartDate;

        result.campaignEndDate =
            firstRow.lineItemEndDate;

        /*
         * Last historical source date is the forecast cutoff.
         */
        result.forecastAsOfDate =
            lastRow.reportDate;


        /*
         * ============================================================
         * HISTORICAL TOTALS
         * ============================================================
         */

        Decimal totalImpressions =
            0;

        Decimal totalClicks =
            0;

        Decimal totalRevenue =
            0;

        Decimal totalCodeServed =
            0;

        Decimal totalUnfilled =
            0;

        Decimal totalDailyTarget =
            0;

        Integer daysWithDailyTarget =
            0;


        for (
            CampaignDataProvider.CampaignDay row :
            rows
        ) {

            totalImpressions +=
                zeroIfNull(
                    row.adServerImpressions
                );

            totalClicks +=
                zeroIfNull(
                    row.adServerClicks
                );

            totalRevenue +=
                zeroIfNull(
                    row.adServerRevenue
                );

            totalCodeServed +=
                zeroIfNull(
                    row.codeServedCount
                );

            totalUnfilled +=
                zeroIfNull(
                    row.totalUnfilledImpressions
                );

            if (
                row.dailyTargetImpressions != null &&
                row.dailyTargetImpressions > 0
            ) {

                totalDailyTarget +=
                    row.dailyTargetImpressions;

                daysWithDailyTarget++;
            }
        }


        Decimal averageDailyTargetImpressions =
            daysWithDailyTarget > 0
                ? totalDailyTarget / Decimal.valueOf(daysWithDailyTarget)
                : null;


        result.historicalDays =
            Decimal.valueOf(
                rows.size()
            );

        result.historicalImpressions =
            totalImpressions;

        result.totalClicks =
            totalClicks;

        result.totalRevenue =
            totalRevenue;

        /*
         * No AdRequests source field exists.
         */
        result.totalAdRequests =
            null;

        result.totalCodeServedCount =
            totalCodeServed;

        result.totalUnfilledImpressions =
            totalUnfilled;


        /*
         * ============================================================
         * FULL-HISTORY DAILY AVERAGE
         * ============================================================
         */

        Decimal averageDaily =
            safeDivide(
                totalImpressions,
                Decimal.valueOf(
                    rows.size()
                )
            );

        result.averageDailyImpressions =
            averageDaily;


        /*
         * ============================================================
         * RECENT 7-DAY AVERAGE
         * ============================================================
         */

        Integer recentCount =
            rows.size() < 7
                ? rows.size()
                : 7;

        Decimal recentImpressions =
            0;

        Integer recentStart =
            rows.size() -
            recentCount;

        for (
            Integer i = recentStart;
            i < rows.size();
            i++
        ) {

            recentImpressions +=
                zeroIfNull(
                    rows[i].adServerImpressions
                );
        }

        Decimal recent7Average =
            safeDivide(
                recentImpressions,
                Decimal.valueOf(
                    recentCount
                )
            );

        result.recent7DayAverageImpressions =
            recent7Average;


        /*
         * ============================================================
         * RECENT DELIVERY TREND
         * ============================================================
         */

        result.recentDeliveryTrendPercentage =
            calculateTrend(
                rows,
                recentCount
            );


        /*
         * ============================================================
         * CAMPAIGN TIMELINE
         * ============================================================
         */

        Integer elapsedDays =
            calculateElapsedCampaignDays(
                result.campaignStartDate,
                result.forecastAsOfDate,
                result.campaignEndDate
            );

        Integer remainingDays =
            calculateRemainingCampaignDays(
                result.forecastAsOfDate,
                result.campaignEndDate
            );

        result.campaignDaysElapsed =
            Decimal.valueOf(
                elapsedDays
            );

        result.campaignDaysRemaining =
            Decimal.valueOf(
                remainingDays
            );


        /*
         * ============================================================
         * FORECAST DAILY RATE
         * ============================================================
         */

        Decimal forecastDailyRate =
            recent7Average > 0
                ? recent7Average
                : averageDaily;


        /*
         * ============================================================
         * FUTURE PROJECTION
         * ============================================================
         */

        result.projectedRemainingImpressions =
            forecastDailyRate *
            Decimal.valueOf(
                remainingDays
            );

        result.projectedEndImpressions =
            totalImpressions +
            result.projectedRemainingImpressions;


        /*
         * ============================================================
         * GOAL EVALUATION
         * ============================================================
         */

        if (
            isLifetimeGoal(
                result.goalType
            ) &&
            result.goalUnits != null &&
            result.goalUnits > 0
        ) {

            result.requiredDailyImpressions =
                calculateRequiredDailyImpressions(
                    result.goalUnits,
                    totalImpressions,
                    remainingDays
                );

            result.projectedGoalAttainmentPercentage =
                safePercentage(
                    result.projectedEndImpressions,
                    result.goalUnits
                );

            result.pacingPercentage =
                calculatePacingPercentage(
                    result.campaignStartDate,
                    result.campaignEndDate,
                    result.forecastAsOfDate,
                    totalImpressions,
                    result.goalUnits
                );

            result.deliveryRisk =
                calculateLifetimeRisk(
                    result.projectedEndImpressions,
                    result.goalUnits,
                    result.requiredDailyImpressions,
                    forecastDailyRate,
                    remainingDays
                );

            result.status =
                'FORECAST_AVAILABLE';

        } else if (
            isDailyGoal(
                result.goalType
            )
        ) {

            result.dailyTargetImpressions =
                averageDailyTargetImpressions;

            if (
                averageDailyTargetImpressions != null &&
                averageDailyTargetImpressions > 0
            ) {

                /*
                 * A Daily goal type has no absolute lifetime goal, but
                 * the source dataset does supply the line item's own
                 * daily impression target. Pacing and risk are evaluated
                 * against that daily target instead of a lifetime goal.
                 */
                result.requiredDailyImpressions =
                    averageDailyTargetImpressions;

                result.pacingPercentage =
                    safePercentage(
                        forecastDailyRate,
                        averageDailyTargetImpressions
                    );

                result.projectedGoalAttainmentPercentage =
                    result.pacingPercentage;

                result.deliveryRisk =
                    calculateDailyGoalRisk(
                        forecastDailyRate,
                        averageDailyTargetImpressions
                    );

                result.status =
                    'FORECAST_AVAILABLE';

            } else {

                /*
                 * The source dataset does not supply a daily target for
                 * this line item either. Absolute attainment genuinely
                 * cannot be evaluated - this is not fabricated.
                 */
                result.requiredDailyImpressions =
                    null;

                result.projectedGoalAttainmentPercentage =
                    null;

                result.pacingPercentage =
                    null;

                result.deliveryRisk =
                    'DAILY_GOAL_ABSOLUTE_ATTAINMENT_NOT_EVALUABLE';

                result.status =
                    'FORECAST_AVAILABLE_WITH_LIMITATION';
            }

        } else {

            result.requiredDailyImpressions =
                null;

            result.projectedGoalAttainmentPercentage =
                null;

            result.pacingPercentage =
                null;

            result.deliveryRisk =
                'GOAL_NOT_EVALUABLE';

            result.status =
                'FORECAST_AVAILABLE_WITH_LIMITATION';
        }


        /*
         * ============================================================
         * PERFORMANCE METRICS
         * ============================================================
         */

        result.cpm =
            calculateCpm(
                totalRevenue,
                totalImpressions
            );

        result.ctrPercentage =
            safePercentage(
                totalClicks,
                totalImpressions
            );

        /*
         * Fill rate uses the actual CodeServedCount source metric.
         */
        result.fillRatePercentage =
            calculateFillRateFromCodeServed(
                totalImpressions,
                totalCodeServed
            );

        /*
         * ============================================================
         * EXPLANATION
         * ============================================================
         */

        result.explanation =
            buildExplanation(
                result
            );
    }


    /*
     * ================================================================
     * ELAPSED CAMPAIGN DAYS
     * ================================================================
     */

    private static Integer calculateElapsedCampaignDays(
        Date startDate,
        Date asOfDate,
        Date endDate
    ) {

        if (
            startDate == null ||
            asOfDate == null
        ) {
            return 0;
        }

        Date effectiveAsOf =
            asOfDate;

        if (
            endDate != null &&
            effectiveAsOf > endDate
        ) {
            effectiveAsOf =
                endDate;
        }

        if (
            effectiveAsOf < startDate
        ) {
            return 0;
        }

        return
            startDate.daysBetween(
                effectiveAsOf
            ) + 1;
    }


    /*
     * ================================================================
     * REMAINING CAMPAIGN DAYS
     * ================================================================
     */

    private static Integer calculateRemainingCampaignDays(
        Date asOfDate,
        Date endDate
    ) {

        if (
            asOfDate == null ||
            endDate == null
        ) {
            return 0;
        }

        if (
            asOfDate >= endDate
        ) {
            return 0;
        }

        return
            asOfDate.daysBetween(
                endDate
            );
    }


    /*
     * ================================================================
     * REQUIRED DAILY IMPRESSIONS
     * ================================================================
     */

    private static Decimal calculateRequiredDailyImpressions(
        Decimal goal,
        Decimal delivered,
        Integer remainingDays
    ) {

        if (
            remainingDays == null ||
            remainingDays <= 0
        ) {
            return 0;
        }

        Decimal remainingGoal =
            goal -
            zeroIfNull(
                delivered
            );

        if (
            remainingGoal <= 0
        ) {
            return 0;
        }

        return
            remainingGoal /
            Decimal.valueOf(
                remainingDays
            );
    }


    /*
     * ================================================================
     * PACING
     * ================================================================
     */

    private static Decimal calculatePacingPercentage(
        Date startDate,
        Date endDate,
        Date asOfDate,
        Decimal delivered,
        Decimal goal
    ) {

        if (
            startDate == null ||
            endDate == null ||
            asOfDate == null ||
            goal == null ||
            goal <= 0
        ) {
            return null;
        }

        Integer totalDays =
            startDate.daysBetween(
                endDate
            ) + 1;

        Integer elapsedDays =
            calculateElapsedCampaignDays(
                startDate,
                asOfDate,
                endDate
            );

        if (
            totalDays <= 0 ||
            elapsedDays <= 0
        ) {
            return null;
        }

        Decimal expectedDelivery =
            goal *
            (
                Decimal.valueOf(
                    elapsedDays
                ) /
                Decimal.valueOf(
                    totalDays
                )
            );

        if (
            expectedDelivery <= 0
        ) {
            return null;
        }

        return
            safePercentage(
                delivered,
                expectedDelivery
            );
    }


    /*
     * ================================================================
     * LIFETIME RISK
     * ================================================================
     */

    private static String calculateLifetimeRisk(
        Decimal projectedEnd,
        Decimal goal,
        Decimal requiredDaily,
        Decimal forecastDailyRate,
        Integer remainingDays
    ) {

        if (
            goal == null ||
            goal <= 0
        ) {
            return 'GOAL_NOT_EVALUABLE';
        }

        if (
            projectedEnd >= goal
        ) {

            Decimal attainmentRatio =
                safeDivide(
                    projectedEnd,
                    goal
                );

            if (
                attainmentRatio >= 1.10
            ) {
                return
                    'LOW_RISK_OVERDELIVERY_OPPORTUNITY';
            }

            return
                'LOW_RISK';
        }

        if (
            remainingDays <= 0 ||
            forecastDailyRate <= 0
        ) {
            return
                'HIGH_RISK';
        }

        if (
            requiredDaily == null ||
            requiredDaily <= 0
        ) {
            return
                'LOW_RISK';
        }

        Decimal deliveryRatio =
            safeDivide(
                forecastDailyRate,
                requiredDaily
            );

        if (
            deliveryRatio < 0.75
        ) {
            return
                'HIGH_RISK';
        }

        if (
            deliveryRatio < 1.00
        ) {
            return
                'MEDIUM_RISK';
        }

        return
            'LOW_RISK';
    }


    /*
     * ================================================================
     * DAILY GOAL RISK
     *
     * Mirrors the lifetime-risk tiering logic, but evaluates the
     * forecast daily delivery rate against the line item's own daily
     * impression target rather than a lifetime goal.
     * ================================================================
     */

    private static String calculateDailyGoalRisk(
        Decimal forecastDailyRate,
        Decimal dailyTarget
    ) {

        if (
            dailyTarget == null ||
            dailyTarget <= 0
        ) {
            return 'GOAL_NOT_EVALUABLE';
        }

        if (
            forecastDailyRate == null ||
            forecastDailyRate <= 0
        ) {
            return 'HIGH_RISK';
        }

        Decimal deliveryRatio =
            safeDivide(
                forecastDailyRate,
                dailyTarget
            );

        if (
            deliveryRatio >= 1.10
        ) {
            return 'LOW_RISK_OVERDELIVERY_OPPORTUNITY';
        }

        if (
            deliveryRatio >= 1.00
        ) {
            return 'LOW_RISK';
        }

        if (
            deliveryRatio >= 0.75
        ) {
            return 'MEDIUM_RISK';
        }

        return 'HIGH_RISK';
    }


    /*
     * ================================================================
     * RECENT DELIVERY TREND
     * ================================================================
     */

    private static Decimal calculateTrend(
        List<CampaignDataProvider.CampaignDay> rows,
        Integer windowSize
    ) {

        if (
            rows == null ||
            windowSize == null ||
            windowSize <= 0 ||
            rows.size() < windowSize * 2
        ) {
            return null;
        }

        Integer recentStart =
            rows.size() -
            windowSize;

        Integer previousStart =
            recentStart -
            windowSize;

        Decimal recentTotal =
            0;

        Decimal previousTotal =
            0;


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


        Decimal recentAverage =
            safeDivide(
                recentTotal,
                Decimal.valueOf(
                    windowSize
                )
            );

        Decimal previousAverage =
            safeDivide(
                previousTotal,
                Decimal.valueOf(
                    windowSize
                )
            );


        if (
            previousAverage <= 0
        ) {
            return null;
        }


        return
            (
                (
                    recentAverage -
                    previousAverage
                ) /
                previousAverage
            ) * 100;
    }


    /*
     * ================================================================
     * CPM
     * ================================================================
     */

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
                zeroIfNull(
                    revenue
                ) /
                impressions
            ) * 1000;
    }


    /*
     * ================================================================
     * FILL RATE
     *
     * Based on:
     *
     *     Impressions / CodeServedCount * 100
     *
     * CodeServedCount is an actual source field.
     * ================================================================
     */

    private static Decimal calculateFillRateFromCodeServed(
        Decimal impressions,
        Decimal codeServedCount
    ) {

        if (
            codeServedCount == null ||
            codeServedCount <= 0
        ) {
            return null;
        }

        return
            (
                zeroIfNull(
                    impressions
                ) /
                codeServedCount
            ) * 100;
    }


    /*
     * ================================================================
     * SAFE PERCENTAGE
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
                zeroIfNull(
                    numerator
                ) /
                denominator
            ) * 100;
    }


    /*
     * ================================================================
     * SAFE DIVISION
     * ================================================================
     */

    private static Decimal safeDivide(
        Decimal numerator,
        Decimal denominator
    ) {

        if (
            denominator == null ||
            denominator == 0
        ) {
            return 0;
        }

        return
            zeroIfNull(
                numerator
            ) /
            denominator;
    }


    /*
     * ================================================================
     * NULL -> ZERO
     * ================================================================
     */

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
     * GOAL HELPERS
     * ================================================================
     */

    private static Boolean isLifetimeGoal(
        String goalType
    ) {

        return
            goalType != null &&
            goalType.trim().toLowerCase() ==
            'lifetime';
    }


    private static Boolean isDailyGoal(
        String goalType
    ) {

        return
            goalType != null &&
            goalType.trim().toLowerCase() ==
            'daily';
    }


    /*
     * ================================================================
     * EXPLANATION
     * ================================================================
     */

    private static String buildExplanation(
        ForecastResult result
    ) {

        String text =
            'Forecast as of ' +
            String.valueOf(
                result.forecastAsOfDate
            ) +
            ' using ' +
            String.valueOf(
                result.historicalDays
            ) +
            ' historical daily records. ';


        text +=
            'Historical impressions: ' +
            formatNumber(
                result.historicalImpressions
            ) +
            '. ';


        text +=
            'Average daily impressions: ' +
            formatNumber(
                result.averageDailyImpressions
            ) +
            '. ';


        text +=
            'Recent 7-day average impressions: ' +
            formatNumber(
                result.recent7DayAverageImpressions
            ) +
            '. ';


        if (
            result.recentDeliveryTrendPercentage != null
        ) {

            text +=
                'Recent delivery trend: ' +
                formatNumber(
                    result.recentDeliveryTrendPercentage
                ) +
                '%. ';
        }


        text +=
            'Projected remaining impressions: ' +
            formatNumber(
                result.projectedRemainingImpressions
            ) +
            '. ';


        text +=
            'Projected end impressions: ' +
            formatNumber(
                result.projectedEndImpressions
            ) +
            '. ';


        if (
            result.requiredDailyImpressions != null
        ) {

            text +=
                'Required daily impressions: ' +
                formatNumber(
                    result.requiredDailyImpressions
                ) +
                '. ';
        }


        if (
            result.goalUnits != null &&
            result.goalUnits > 0
        ) {

            text +=
                'Absolute goal: ' +
                formatNumber(
                    result.goalUnits
                ) +
                '. ';
        }


        if (
            result.projectedGoalAttainmentPercentage != null
        ) {

            text +=
                'Projected goal attainment: ' +
                formatNumber(
                    result.projectedGoalAttainmentPercentage
                ) +
                '%. ';
        }


        if (
            result.pacingPercentage != null
        ) {

            text +=
                'Pacing versus time-based campaign target: ' +
                formatNumber(
                    result.pacingPercentage
                ) +
                '%. ';
        }


        text +=
            'CTR: ' +
            formatPercentage(
                result.ctrPercentage
            ) +
            '. ';


        text +=
            'Fill rate: ' +
            formatPercentage(
                result.fillRatePercentage
            ) +
            '. ';


        text +=
            'CPM: ' +
            formatNumber(
                result.cpm
            ) +
            '. ';


        text +=
            'Total code served count: ' +
            formatNumber(
                result.totalCodeServedCount
            ) +
            '. ';


        text +=
            'Delivery risk: ' +
            String.valueOf(
                result.deliveryRisk
            ) +
            '. ';


        if (
            isDailyGoal(
                result.goalType
            )
        ) {

            if (
                result.dailyTargetImpressions != null &&
                result.dailyTargetImpressions > 0
            ) {

                text +=
                    'This line item is a Daily goal in the source dataset. ' +
                    'Pacing and risk are evaluated against its own daily ' +
                    'target of ' +
                    formatNumber(result.dailyTargetImpressions) +
                    ' impressions per day rather than a lifetime goal.';

            } else {

                text +=
                    'This line item is a Daily goal in the source dataset. ' +
                    'The current source/provider contract does not expose a ' +
                    'daily impression target for this line item, so absolute ' +
                    'goal attainment and campaign pacing are not fabricated.';
            }
        }


        return text;
    }


    /*
     * ================================================================
     * FORMATTING
     * ================================================================
     */

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


    private static String formatPercentage(
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
            ) +
            '%';
    }


    /*
     * ================================================================
     * EXCEPTION
     * ================================================================
     */

    public class ForecastException
        extends Exception {
    }
}