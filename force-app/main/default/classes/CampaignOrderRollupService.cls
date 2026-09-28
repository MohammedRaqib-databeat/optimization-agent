public with sharing class CampaignOrderRollupService {

    /*
     * ================================================================
     * ORDER-LEVEL PERFORMANCE ROLLUP
     *
     * Answers "how is the Nike Fall order doing" style questions by
     * aggregating every line item belonging to the given order name.
     * Delegates all math to CampaignRollupEngine.
     * ================================================================
     */


    public class OrderRequest {

        @InvocableVariable(
            label='Order Name'
            required=true
        )
        public String orderName;
    }


    public class RollupResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Scope Name')
        public String scopeName;

        @InvocableVariable(label='Line Item Count')
        public Integer lineItemCount;

        @InvocableVariable(label='Total Impressions')
        public Decimal totalImpressions;

        @InvocableVariable(label='Total Clicks')
        public Decimal totalClicks;

        @InvocableVariable(label='Total Revenue')
        public Decimal totalRevenue;

        @InvocableVariable(label='Average CTR Percentage')
        public Decimal averageCtrPercentage;

        @InvocableVariable(label='Average CPM')
        public Decimal averageCpm;

        @InvocableVariable(label='Average Fill Rate Percentage')
        public Decimal averageFillRatePercentage;

        @InvocableVariable(label='Portfolio Median CTR Percentage')
        public Decimal portfolioMedianCtrPercentage;

        @InvocableVariable(label='Portfolio Median CPM')
        public Decimal portfolioMedianCpm;

        @InvocableVariable(label='Portfolio Median Fill Rate Percentage')
        public Decimal portfolioMedianFillRatePercentage;

        @InvocableVariable(label='Line Item Breakdown')
        public String lineItemBreakdown;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Summarize Order Performance'
        description='Aggregates delivery, yield, and benchmark comparison across every line item belonging to the given order name.'
    )
    public static List<RollupResult> summarize(
        List<OrderRequest> requests
    ) {

        List<RollupResult> results =
            new List<RollupResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        List<CampaignRollupEngine.LineMetrics> allMetrics =
            CampaignRollupEngine.loadAllMetrics();

        CampaignRollupEngine.Benchmark benchmark =
            CampaignRollupEngine.calculateBenchmark(allMetrics);

        Map<String, CampaignRollupEngine.LineMetrics> metricsByLineItemId =
            new Map<String, CampaignRollupEngine.LineMetrics>();

        for (
            CampaignRollupEngine.LineMetrics metric :
            allMetrics
        ) {
            metricsByLineItemId.put(metric.lineItemId, metric);
        }

        Map<String, Set<String>> lineItemsByOrder =
            CampaignRollupEngine.loadLineItemsByOrder();

        for (
            OrderRequest request :
            requests
        ) {

            RollupResult result =
                new RollupResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.orderName)
                ) {

                    throw new CampaignRollupEngine.RollupException(
                        'Order Name is required.'
                    );
                }

                Set<String> lineItemIds =
                    lineItemsByOrder.get(request.orderName);

                if (
                    lineItemIds == null ||
                    lineItemIds.isEmpty()
                ) {

                    throw new CampaignRollupEngine.RollupException(
                        'No line items were found for order "' +
                        request.orderName +
                        '".'
                    );
                }

                List<CampaignRollupEngine.LineMetrics> scoped =
                    new List<CampaignRollupEngine.LineMetrics>();

                for (
                    String lineItemId :
                    lineItemIds
                ) {

                    if (
                        metricsByLineItemId.containsKey(lineItemId)
                    ) {

                        scoped.add(
                            metricsByLineItemId.get(lineItemId)
                        );
                    }
                }

                if (
                    scoped.isEmpty()
                ) {

                    throw new CampaignRollupEngine.RollupException(
                        'Order "' +
                        request.orderName +
                        '" was found, but no matching daily delivery records exist for its line items.'
                    );
                }

                CampaignRollupEngine.RollupSummary summary =
                    CampaignRollupEngine.buildRollupSummary(
                        request.orderName,
                        scoped,
                        benchmark
                    );

                applySummary(
                    result,
                    summary,
                    benchmark
                );

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static void applySummary(
        RollupResult result,
        CampaignRollupEngine.RollupSummary summary,
        CampaignRollupEngine.Benchmark benchmark
    ) {

        result.scopeName = summary.scopeName;
        result.lineItemCount = summary.lineItemCount;
        result.totalImpressions = summary.totalImpressions;
        result.totalClicks = summary.totalClicks;
        result.totalRevenue = summary.totalRevenue;
        result.averageCtrPercentage = summary.averageCtrPercentage;
        result.averageCpm = summary.averageCpm;
        result.averageFillRatePercentage = summary.averageFillRatePercentage;
        result.portfolioMedianCtrPercentage = benchmark.medianCtr;
        result.portfolioMedianCpm = benchmark.medianCpm;
        result.portfolioMedianFillRatePercentage = benchmark.medianFillRate;
        result.lineItemBreakdown = summary.lineItemBreakdown;
        result.explanation = summary.explanation;
    }
}
