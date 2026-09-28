public with sharing class CampaignRollupEngine {

    /*
     * ================================================================
     * SHARED ROLLUP MATH
     *
     * Not an invocable action itself - a single Apex class can only
     * expose one @InvocableMethod, so the three rollup actions
     * (Advertiser, Order, Creative) are thin wrapper classes that all
     * delegate their aggregation math to this shared engine.
     * ================================================================
     */


    public class LineMetrics {

        public String lineItemId;
        public String advertiser;
        public String creative;
        public String goalType;
        public Decimal goalUnits;

        public Date startDate;
        public Date endDate;
        public Date latestReportDate;

        public Decimal impressions = 0;
        public Decimal clicks = 0;
        public Decimal revenue = 0;
        public Decimal codeServed = 0;
        public Decimal measurable = 0;
        public Decimal viewable = 0;

        public Decimal totalDailyTarget = 0;
        public Integer daysWithDailyTarget = 0;
    }


    public class Benchmark {

        public Decimal medianCtr;
        public Decimal medianCpm;
        public Decimal medianFillRate;
    }


    public class RollupSummary {

        public String scopeName;
        public Integer lineItemCount;
        public Decimal totalImpressions;
        public Decimal totalClicks;
        public Decimal totalRevenue;
        public Decimal averageCtrPercentage;
        public Decimal averageCpm;
        public Decimal averageFillRatePercentage;
        public String lineItemBreakdown;
        public String explanation;
    }


    public static List<LineMetrics> loadAllMetrics() {

        List<CampaignDataProvider.CampaignDay> allRows;

        try {

            allRows =
                CampaignDataProvider.getAllLineItemData();

        } catch (Exception e) {

            throw new RollupException(
                'Unable to load historical delivery data: ' +
                e.getMessage()
            );
        }

        Map<String, LineMetrics> byLineItem =
            new Map<String, LineMetrics>();

        for (
            CampaignDataProvider.CampaignDay row :
            allRows
        ) {

            if (
                row == null ||
                String.isBlank(row.lineItemId)
            ) {
                continue;
            }

            if (
                !byLineItem.containsKey(row.lineItemId)
            ) {

                LineMetrics metric =
                    new LineMetrics();

                metric.lineItemId = row.lineItemId;
                metric.advertiser = row.advertiser;
                metric.creative = row.creative;
                metric.goalType = row.primaryGoalType;
                metric.goalUnits = row.primaryGoalUnits;
                metric.startDate = row.lineItemStartDate;
                metric.endDate = row.lineItemEndDate;

                byLineItem.put(
                    row.lineItemId,
                    metric
                );
            }

            LineMetrics metric =
                byLineItem.get(row.lineItemId);

            metric.impressions += zeroIfNull(row.adServerImpressions);
            metric.clicks += zeroIfNull(row.adServerClicks);
            metric.revenue += zeroIfNull(row.adServerRevenue);
            metric.codeServed += zeroIfNull(row.codeServedCount);
            metric.measurable +=
                zeroIfNull(row.activeViewMeasurableImpressions);
            metric.viewable +=
                zeroIfNull(row.activeViewViewableImpressions);

            if (
                metric.latestReportDate == null ||
                (
                    row.reportDate != null &&
                    row.reportDate > metric.latestReportDate
                )
            ) {
                metric.latestReportDate = row.reportDate;
            }

            if (
                row.dailyTargetImpressions != null &&
                row.dailyTargetImpressions > 0
            ) {

                metric.totalDailyTarget += row.dailyTargetImpressions;
                metric.daysWithDailyTarget++;
            }
        }

        return byLineItem.values();
    }


    public static Map<String, Set<String>> loadLineItemsByOrder() {

        Map<String, Set<String>> index =
            new Map<String, Set<String>>();

        List<CampaignDataProvider.ContentionRecord> rows;

        try {

            rows =
                CampaignDataProvider.getAllContentionData();

        } catch (Exception e) {

            return index;
        }

        for (
            CampaignDataProvider.ContentionRecord row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.orderName) ||
                String.isBlank(row.lineItemId)
            ) {
                continue;
            }

            if (
                !index.containsKey(row.orderName)
            ) {

                index.put(
                    row.orderName,
                    new Set<String>()
                );
            }

            index.get(row.orderName).add(row.lineItemId);
        }

        return index;
    }


    /*
     * ================================================================
     * PACING PERCENTAGE
     *
     * Lifetime goal: cumulative delivered impressions versus the
     * cumulative expected-to-date share of the goal, based on elapsed
     * calendar days out of the full flight.
     *
     * Daily goal: average delivered rate versus the line item's own
     * recorded daily target, when the source data supplies one.
     *
     * Returns null when pacing genuinely cannot be evaluated (no goal,
     * no dates, or no daily target) - never a fabricated number.
     * ================================================================
     */

    public static Decimal calculatePacingPercentage(
        LineMetrics metric
    ) {

        if (
            metric == null
        ) {
            return null;
        }

        Boolean isLifetime =
            metric.goalType != null &&
            metric.goalType.trim().toLowerCase() == 'lifetime';

        if (
            isLifetime &&
            metric.goalUnits != null &&
            metric.goalUnits > 0 &&
            metric.startDate != null &&
            metric.endDate != null &&
            metric.latestReportDate != null
        ) {

            Integer totalDays =
                metric.startDate.daysBetween(metric.endDate) + 1;

            Date effectiveAsOf =
                metric.latestReportDate > metric.endDate
                    ? metric.endDate
                    : metric.latestReportDate;

            if (
                effectiveAsOf < metric.startDate ||
                totalDays <= 0
            ) {
                return null;
            }

            Integer elapsedDays =
                metric.startDate.daysBetween(effectiveAsOf) + 1;

            Decimal expectedDelivery =
                metric.goalUnits *
                (
                    Decimal.valueOf(elapsedDays) /
                    Decimal.valueOf(totalDays)
                );

            if (
                expectedDelivery <= 0
            ) {
                return null;
            }

            return safePercentage(metric.impressions, expectedDelivery);
        }

        Boolean isDaily =
            metric.goalType != null &&
            metric.goalType.trim().toLowerCase() == 'daily';

        if (
            isDaily &&
            metric.daysWithDailyTarget > 0
        ) {

            Decimal averageDailyTarget =
                metric.totalDailyTarget /
                Decimal.valueOf(metric.daysWithDailyTarget);

            Integer historicalDays =
                metric.daysWithDailyTarget;

            Decimal averageDelivered =
                historicalDays > 0
                    ? metric.impressions / Decimal.valueOf(historicalDays)
                    : null;

            return safePercentage(averageDelivered, averageDailyTarget);
        }

        return null;
    }


    public static Benchmark calculateBenchmark(
        List<LineMetrics> allMetrics
    ) {

        List<Decimal> ctrValues = new List<Decimal>();
        List<Decimal> cpmValues = new List<Decimal>();
        List<Decimal> fillValues = new List<Decimal>();

        for (
            LineMetrics metric :
            allMetrics
        ) {

            if (
                metric.impressions <= 0
            ) {
                continue;
            }

            Decimal ctr = safePercentage(metric.clicks, metric.impressions);
            Decimal cpm = calculateCpm(metric.revenue, metric.impressions);
            Decimal fillRate =
                safePercentage(metric.impressions, metric.codeServed);

            if (ctr != null) { ctrValues.add(ctr); }
            if (cpm != null) { cpmValues.add(cpm); }
            if (fillRate != null) { fillValues.add(fillRate); }
        }

        Benchmark benchmark = new Benchmark();

        benchmark.medianCtr = calculateMedian(ctrValues);
        benchmark.medianCpm = calculateMedian(cpmValues);
        benchmark.medianFillRate = calculateMedian(fillValues);

        return benchmark;
    }


    public static RollupSummary buildRollupSummary(
        String scopeName,
        List<LineMetrics> scoped,
        Benchmark benchmark
    ) {

        Decimal totalImpressions = 0;
        Decimal totalClicks = 0;
        Decimal totalRevenue = 0;
        Decimal totalCodeServed = 0;

        List<Object> breakdown = new List<Object>();

        for (
            LineMetrics metric :
            scoped
        ) {

            totalImpressions += metric.impressions;
            totalClicks += metric.clicks;
            totalRevenue += metric.revenue;
            totalCodeServed += metric.codeServed;

            Map<String, Object> lineEntry = new Map<String, Object>();

            lineEntry.put('lineItemId', metric.lineItemId);
            lineEntry.put('creative', metric.creative);
            lineEntry.put('impressions', metric.impressions);
            lineEntry.put(
                'ctrPercentage',
                safePercentage(metric.clicks, metric.impressions)
            );
            lineEntry.put(
                'cpm',
                calculateCpm(metric.revenue, metric.impressions)
            );
            lineEntry.put('goalUnits', metric.goalUnits);

            breakdown.add(lineEntry);
        }

        RollupSummary summary = new RollupSummary();

        summary.scopeName = scopeName;
        summary.lineItemCount = scoped.size();
        summary.totalImpressions = totalImpressions;
        summary.totalClicks = totalClicks;
        summary.totalRevenue = totalRevenue;
        summary.averageCtrPercentage =
            safePercentage(totalClicks, totalImpressions);
        summary.averageCpm = calculateCpm(totalRevenue, totalImpressions);
        summary.averageFillRatePercentage =
            safePercentage(totalImpressions, totalCodeServed);
        summary.lineItemBreakdown = JSON.serialize(breakdown);
        summary.explanation =
            'Aggregated across ' +
            scoped.size() +
            ' line item(s) for "' +
            scopeName +
            '".';

        return summary;
    }


    public static String buildCreativeBreakdown(
        List<LineMetrics> scoped
    ) {

        Map<String, List<LineMetrics>> byCreative =
            new Map<String, List<LineMetrics>>();

        for (
            LineMetrics metric :
            scoped
        ) {

            String creativeName =
                String.isBlank(metric.creative)
                    ? 'Unknown Creative'
                    : metric.creative;

            if (
                !byCreative.containsKey(creativeName)
            ) {

                byCreative.put(
                    creativeName,
                    new List<LineMetrics>()
                );
            }

            byCreative.get(creativeName).add(metric);
        }

        List<Object> payload = new List<Object>();

        for (
            String creativeName :
            byCreative.keySet()
        ) {

            List<LineMetrics> lines =
                byCreative.get(creativeName);

            Decimal impressions = 0;
            Decimal clicks = 0;
            Decimal revenue = 0;
            Decimal totalGoal = 0;
            Boolean hasEvaluableGoal = false;

            for (
                LineMetrics metric :
                lines
            ) {

                impressions += metric.impressions;
                clicks += metric.clicks;
                revenue += metric.revenue;

                if (
                    metric.goalUnits != null &&
                    metric.goalUnits > 0 &&
                    metric.goalType != null &&
                    metric.goalType.trim().toLowerCase() == 'lifetime'
                ) {

                    totalGoal += metric.goalUnits;
                    hasEvaluableGoal = true;
                }
            }

            Map<String, Object> entry = new Map<String, Object>();

            List<String> lineItemIds = new List<String>();

            for (
                LineMetrics metric :
                lines
            ) {
                lineItemIds.add(metric.lineItemId);
            }

            entry.put('creative', creativeName);
            entry.put('lineItemCount', lines.size());
            entry.put('lineItemIds', String.join(lineItemIds, ', '));
            entry.put('impressions', impressions);
            entry.put(
                'ctrPercentage',
                safePercentage(clicks, impressions)
            );
            entry.put('cpm', calculateCpm(revenue, impressions));

            if (
                hasEvaluableGoal
            ) {

                Decimal attainment =
                    safePercentage(impressions, totalGoal);

                entry.put('goalAttainmentPercentage', attainment);
                entry.put(
                    'status',
                    attainment != null && attainment >= 100
                        ? 'MEETING_EXPECTED'
                        : 'BELOW_EXPECTED'
                );

            } else {

                entry.put('goalAttainmentPercentage', null);
                entry.put('status', 'GOAL_NOT_EVALUABLE');
            }

            payload.add(entry);
        }

        return JSON.serialize(payload);
    }


    public static Integer countDistinctCreatives(
        List<LineMetrics> scoped
    ) {

        Set<String> creatives = new Set<String>();

        for (
            LineMetrics metric :
            scoped
        ) {

            creatives.add(
                String.isBlank(metric.creative)
                    ? 'Unknown Creative'
                    : metric.creative
            );
        }

        return creatives.size();
    }


    private static Decimal calculateMedian(
        List<Decimal> values
    ) {

        if (
            values == null ||
            values.isEmpty()
        ) {
            return null;
        }

        List<Decimal> sorted = values.clone();
        sorted.sort();

        Integer size = sorted.size();
        Integer middle = size / 2;

        if (
            Math.mod(size, 2) == 0
        ) {
            return (sorted[middle - 1] + sorted[middle]) / 2;
        }

        return sorted[middle];
    }


    public static Decimal safePercentage(
        Decimal numerator,
        Decimal denominator
    ) {

        if (
            denominator == null ||
            denominator <= 0
        ) {
            return null;
        }

        return (zeroIfNull(numerator) / denominator) * 100;
    }


    public static Decimal calculateCpm(
        Decimal revenue,
        Decimal impressions
    ) {

        if (
            impressions == null ||
            impressions <= 0
        ) {
            return null;
        }

        return (zeroIfNull(revenue) / impressions) * 1000;
    }


    private static Decimal zeroIfNull(
        Decimal value
    ) {

        return
            value == null
                ? 0
                : value;
    }


    public class RollupException extends Exception {
    }
}
