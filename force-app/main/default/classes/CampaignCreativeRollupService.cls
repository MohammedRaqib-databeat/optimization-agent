public with sharing class CampaignCreativeRollupService {

    /*
     * ================================================================
     * CREATIVE-LEVEL PERFORMANCE ROLLUP
     *
     * Answers "which creatives are getting expected impressions" style
     * questions by grouping performance by creative across whatever
     * line items use it, optionally scoped to one advertiser or order.
     * Delegates all math to CampaignRollupEngine.
     * ================================================================
     */


    public class CreativeScopeRequest {

        @InvocableVariable(label='Advertiser Name')
        public String advertiserName;

        @InvocableVariable(label='Order Name')
        public String orderName;
    }


    public class CreativeRollupResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Scope Name')
        public String scopeName;

        @InvocableVariable(label='Creative Count')
        public Integer creativeCount;

        @InvocableVariable(label='Creative Breakdown')
        public String creativeBreakdown;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Summarize Creative Performance'
        description='Groups performance by creative across whatever line items use it (optionally scoped to one advertiser or order), and flags whether each creative is meeting the goal of the line items it appears on.'
    )
    public static List<CreativeRollupResult> summarize(
        List<CreativeScopeRequest> requests
    ) {

        List<CreativeRollupResult> results =
            new List<CreativeRollupResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        List<CampaignRollupEngine.LineMetrics> allMetrics =
            CampaignRollupEngine.loadAllMetrics();

        Map<String, Set<String>> lineItemsByOrder =
            CampaignRollupEngine.loadLineItemsByOrder();

        for (
            CreativeScopeRequest request :
            requests
        ) {

            CreativeRollupResult result =
                new CreativeRollupResult();

            result.success = false;

            try {

                List<CampaignRollupEngine.LineMetrics> scoped =
                    allMetrics;

                if (
                    request != null &&
                    !String.isBlank(request.advertiserName)
                ) {

                    List<CampaignRollupEngine.LineMetrics> filtered =
                        new List<CampaignRollupEngine.LineMetrics>();

                    for (
                        CampaignRollupEngine.LineMetrics metric :
                        scoped
                    ) {

                        if (
                            metric.advertiser != null &&
                            metric.advertiser.equalsIgnoreCase(
                                request.advertiserName
                            )
                        ) {
                            filtered.add(metric);
                        }
                    }

                    scoped = filtered;
                    result.scopeName = request.advertiserName;

                } else if (
                    request != null &&
                    !String.isBlank(request.orderName)
                ) {

                    Set<String> lineItemIds =
                        lineItemsByOrder.get(request.orderName);

                    List<CampaignRollupEngine.LineMetrics> filtered =
                        new List<CampaignRollupEngine.LineMetrics>();

                    if (
                        lineItemIds != null
                    ) {

                        for (
                            CampaignRollupEngine.LineMetrics metric :
                            scoped
                        ) {

                            if (
                                lineItemIds.contains(metric.lineItemId)
                            ) {
                                filtered.add(metric);
                            }
                        }
                    }

                    scoped = filtered;
                    result.scopeName = request.orderName;

                } else {

                    result.scopeName = 'ALL_ADVERTISERS';
                }

                if (
                    scoped.isEmpty()
                ) {

                    throw new CampaignRollupEngine.RollupException(
                        'No line items were found for the requested scope.'
                    );
                }

                result.creativeBreakdown =
                    CampaignRollupEngine.buildCreativeBreakdown(scoped);

                result.creativeCount =
                    CampaignRollupEngine.countDistinctCreatives(scoped);

                result.explanation =
                    'Creative performance is grouped across ' +
                    scoped.size() +
                    ' line item(s) in scope. "Meeting Expected" compares ' +
                    'delivered impressions on each creative\'s line item(s) ' +
                    'against that line item\'s own recorded goal, when an ' +
                    'absolute goal is available.';

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }
}
