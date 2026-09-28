public with sharing class CampaignOrderHealthCheckService {

    /*
     * ================================================================
     * ORDER HEALTH CHECK - MINIMAL METRIC POC
     * ================================================================
     *
     * Built for non-technical AppExchange buyers: given an order name,
     * lists every line item in it and classifies each as Performing
     * Well or Needs Attention using only three metrics - Delivery
     * Pacing, Fill Rate, and CPM - instead of the full technical
     * benchmark/eligibility evidence set used by
     * CampaignOptimizationService.
     *
     * The full technical evidence engine is NOT replaced by this
     * class - it remains available for anyone who explicitly asks for
     * a deep-dive optimization analysis on one specific line item.
     * This class is the plain-language front door for an order-level
     * question.
     *
     * Classification thresholds below are POC starting defaults, not
     * yet validated against real business risk tolerance - flagged
     * here deliberately so they are easy to find and tune.
     * ================================================================
     */

    private static final Decimal PACING_HEALTHY_THRESHOLD = 90;
    private static final Decimal FILL_RATE_HEALTHY_THRESHOLD = 70;


    public class OrderHealthCheckRequest {

        @InvocableVariable(
            label='Order Name'
            required=true
        )
        public String orderName;
    }


    public class OrderHealthCheckResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Order Name')
        public String orderName;

        @InvocableVariable(label='Line Item Count')
        public Integer lineItemCount;

        @InvocableVariable(label='Performing Well Count')
        public Integer performingWellCount;

        @InvocableVariable(label='Needs Attention Count')
        public Integer needsAttentionCount;

        @InvocableVariable(label='Line Item Health Breakdown')
        public String lineItemHealthBreakdown;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Check Order Health'
        description='Lists every line item in the given order and classifies each as Performing Well or Needs Attention using Delivery Pacing, Fill Rate, and CPM only, with one plain-language suggestion for each line item that needs attention.'
    )
    public static List<OrderHealthCheckResult> checkOrderHealth(
        List<OrderHealthCheckRequest> requests
    ) {

        List<OrderHealthCheckResult> results =
            new List<OrderHealthCheckResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        List<CampaignRollupEngine.LineMetrics> allMetrics =
            CampaignRollupEngine.loadAllMetrics();

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
            OrderHealthCheckRequest request :
            requests
        ) {

            OrderHealthCheckResult result =
                new OrderHealthCheckResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.orderName)
                ) {

                    throw new OrderHealthCheckException(
                        'Order Name is required.'
                    );
                }

                result.orderName = request.orderName;

                Set<String> lineItemIds =
                    lineItemsByOrder.get(request.orderName);

                if (
                    lineItemIds == null ||
                    lineItemIds.isEmpty()
                ) {

                    throw new OrderHealthCheckException(
                        'No line items were found for order "' +
                        request.orderName +
                        '".'
                    );
                }

                List<Object> breakdown =
                    new List<Object>();

                Integer performingWellCount = 0;
                Integer needsAttentionCount = 0;

                for (
                    String lineItemId :
                    lineItemIds
                ) {

                    CampaignRollupEngine.LineMetrics metric =
                        metricsByLineItemId.get(lineItemId);

                    if (
                        metric == null
                    ) {
                        continue;
                    }

                    Map<String, Object> entry =
                        buildLineItemHealthEntry(metric);

                    if (
                        entry.get('status') == 'PERFORMING_WELL'
                    ) {
                        performingWellCount++;
                    } else {
                        needsAttentionCount++;
                    }

                    breakdown.add(entry);
                }

                if (
                    breakdown.isEmpty()
                ) {

                    throw new OrderHealthCheckException(
                        'Order "' +
                        request.orderName +
                        '" was found, but no matching daily delivery records exist for its line items.'
                    );
                }

                result.lineItemCount = breakdown.size();
                result.performingWellCount = performingWellCount;
                result.needsAttentionCount = needsAttentionCount;
                result.lineItemHealthBreakdown = JSON.serialize(breakdown);

                result.explanation =
                    performingWellCount +
                    ' of ' +
                    breakdown.size() +
                    ' line item(s) in this order are performing well; ' +
                    needsAttentionCount +
                    ' need attention. Classification uses Delivery ' +
                    'Pacing, Fill Rate, and CPM only.';

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static Map<String, Object> buildLineItemHealthEntry(
        CampaignRollupEngine.LineMetrics metric
    ) {

        Decimal pacingPercentage =
            CampaignRollupEngine.calculatePacingPercentage(metric);

        Decimal fillRatePercentage =
            CampaignRollupEngine.safePercentage(
                metric.impressions,
                metric.codeServed
            );

        Decimal cpm =
            CampaignRollupEngine.calculateCpm(
                metric.revenue,
                metric.impressions
            );

        Boolean pacingHealthy =
            pacingPercentage != null &&
            pacingPercentage >= PACING_HEALTHY_THRESHOLD;

        Boolean fillRateHealthy =
            fillRatePercentage != null &&
            fillRatePercentage >= FILL_RATE_HEALTHY_THRESHOLD;

        Boolean pacingEvaluable =
            pacingPercentage != null;

        String status;
        String suggestion;

        if (
            !pacingEvaluable
        ) {

            status = 'NOT_EVALUABLE';
            suggestion =
                'Delivery pacing could not be evaluated for this line ' +
                'item because the source data does not provide an ' +
                'absolute goal or daily target to measure against.';

        } else if (
            pacingHealthy &&
            fillRateHealthy
        ) {

            status = 'PERFORMING_WELL';
            suggestion = null;

        } else {

            status = 'NEEDS_ATTENTION';
            suggestion =
                buildSuggestion(
                    pacingHealthy,
                    fillRateHealthy
                );
        }

        Map<String, Object> entry =
            new Map<String, Object>();

        entry.put('lineItemId', metric.lineItemId);
        entry.put('creative', metric.creative);
        entry.put('pacingPercentage', pacingPercentage);
        entry.put('fillRatePercentage', fillRatePercentage);
        entry.put('cpm', cpm);
        entry.put('status', status);
        entry.put('suggestion', suggestion);

        return entry;
    }


    private static String buildSuggestion(
        Boolean pacingHealthy,
        Boolean fillRateHealthy
    ) {

        if (
            !pacingHealthy &&
            !fillRateHealthy
        ) {

            return
                'This line item is behind pace and has a lower than ' +
                'expected fill rate. Reviewing available inventory and ' +
                'whether targeting is too narrow may help.';
        }

        if (
            !pacingHealthy
        ) {

            return
                'This line item is behind pace on its delivery goal. ' +
                'Reviewing targeting or priority may help it catch up.';
        }

        return
            'This line item has a lower than expected fill rate, ' +
            'meaning available inventory is not being fully used. ' +
            'Reviewing supply or targeting constraints may help.';
    }


    public class OrderHealthCheckException extends Exception {
    }
}
