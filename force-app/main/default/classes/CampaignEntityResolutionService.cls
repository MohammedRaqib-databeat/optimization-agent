public with sharing class CampaignEntityResolutionService {

    /*
     * ================================================================
     * NATURAL LANGUAGE ENTITY RESOLUTION
     * ================================================================
     *
     * Real users at a publisher/SSP do not know Line Item IDs. They
     * know advertiser names ("Nike") and sometimes order names. This
     * engine resolves free text into the underlying Line Item IDs,
     * Advertiser Names, and Order Names the deterministic engines
     * actually operate on.
     *
     * Apex responsibilities:
     *   1. Detect whether the input already looks like a Line Item ID.
     *   2. Otherwise, search advertiser names and order names for a
     *      case-insensitive partial match.
     *   3. Report back exactly what matched, and flag when more than
     *      one candidate exists so the agent asks the user to
     *      disambiguate instead of guessing.
     *
     * Apex does NOT guess which candidate the user meant when more
     * than one exists.
     * ================================================================
     */


    public class EntityResolutionRequest {

        @InvocableVariable(
            label='Search Text'
            required=true
        )
        public String searchText;
    }


    public class EntityResolutionResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Search Text')
        public String searchText;

        @InvocableVariable(label='Match Type')
        public String matchType;

        @InvocableVariable(label='Requires Disambiguation')
        public Boolean requiresDisambiguation;

        @InvocableVariable(label='Matched Line Item ID')
        public String matchedLineItemId;

        @InvocableVariable(label='Matched Advertiser Name')
        public String matchedAdvertiserName;

        @InvocableVariable(label='Matched Order Name')
        public String matchedOrderName;

        @InvocableVariable(label='Candidate Advertisers')
        public String candidateAdvertisers;

        @InvocableVariable(label='Candidate Orders')
        public String candidateOrders;

        @InvocableVariable(label='Candidate Line Item Count')
        public Integer candidateLineItemCount;

        @InvocableVariable(label='Candidate Line Item IDs')
        public String candidateLineItemIds;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Resolve Campaign Entity From Text'
        description='Resolves free text (advertiser name, order name, or Line Item ID) into the underlying record identifiers, flagging when more than one candidate matches so the agent can ask the user to disambiguate.'
    )
    public static List<EntityResolutionResult> resolve(
        List<EntityResolutionRequest> requests
    ) {

        List<EntityResolutionResult> results =
            new List<EntityResolutionResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        List<CampaignDataProvider.CampaignDay> allDailyRows;
        List<CampaignDataProvider.ContentionRecord> allContentionRows;

        try {

            allDailyRows =
                CampaignDataProvider.getAllLineItemData();

            allContentionRows =
                CampaignDataProvider.getAllContentionData();

        } catch (Exception e) {

            for (
                EntityResolutionRequest request :
                requests
            ) {

                EntityResolutionResult errorResult =
                    new EntityResolutionResult();

                errorResult.success = false;
                errorResult.searchText =
                    request == null
                        ? null
                        : request.searchText;

                errorResult.explanation = e.getMessage();

                results.add(errorResult);
            }

            return results;
        }

        Map<String, Set<String>> advertiserToLineItemIds =
            buildAdvertiserIndex(
                allDailyRows
            );

        Map<String, Set<String>> orderToLineItemIds =
            buildOrderIndex(
                allContentionRows
            );

        Map<String, String> orderToAdvertiser =
            buildOrderToAdvertiserIndex(
                allContentionRows
            );

        Set<String> allLineItemIds =
            collectLineItemIds(
                allDailyRows
            );

        for (
            EntityResolutionRequest request :
            requests
        ) {

            EntityResolutionResult result =
                new EntityResolutionResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.searchText)
                ) {

                    throw new EntityResolutionException(
                        'Search text is required.'
                    );
                }

                String searchText =
                    request.searchText.trim();

                result.searchText = searchText;

                resolveSingleRequest(
                    searchText,
                    allLineItemIds,
                    advertiserToLineItemIds,
                    orderToLineItemIds,
                    orderToAdvertiser,
                    result
                );

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.matchType = 'ERROR';
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static void resolveSingleRequest(
        String searchText,
        Set<String> allLineItemIds,
        Map<String, Set<String>> advertiserToLineItemIds,
        Map<String, Set<String>> orderToLineItemIds,
        Map<String, String> orderToAdvertiser,
        EntityResolutionResult result
    ) {

        if (
            allLineItemIds.contains(searchText)
        ) {

            result.matchType = 'EXACT_LINE_ITEM';
            result.requiresDisambiguation = false;
            result.matchedLineItemId = searchText;
            result.candidateLineItemCount = 1;
            result.explanation =
                'Search text matched an exact Line Item ID.';

            return;
        }

        String searchLower =
            searchText.toLowerCase();

        List<String> matchingAdvertisers =
            findMatchingKeys(
                advertiserToLineItemIds.keySet(),
                searchLower
            );

        List<String> matchingOrders =
            findMatchingKeys(
                orderToLineItemIds.keySet(),
                searchLower
            );

        /*
         * A matched order that simply belongs to the one matched
         * advertiser is not a separate candidate - it is the same
         * entity found two ways. Collapse that case down to a single
         * advertiser match instead of forcing disambiguation between
         * an advertiser and its own order.
         */
        if (
            matchingAdvertisers.size() == 1 &&
            !matchingOrders.isEmpty()
        ) {

            Boolean allOrdersBelongToMatchedAdvertiser =
                true;

            for (
                String orderName :
                matchingOrders
            ) {

                String orderAdvertiser =
                    orderToAdvertiser.get(orderName);

                if (
                    orderAdvertiser == null ||
                    !orderAdvertiser.equalsIgnoreCase(
                        matchingAdvertisers[0]
                    )
                ) {

                    allOrdersBelongToMatchedAdvertiser = false;
                    break;
                }
            }

            if (
                allOrdersBelongToMatchedAdvertiser
            ) {
                matchingOrders = new List<String>();
            }
        }

        Integer totalMatches =
            matchingAdvertisers.size() +
            matchingOrders.size();

        if (
            totalMatches == 0
        ) {

            result.matchType = 'NO_MATCH';
            result.requiresDisambiguation = false;
            result.explanation =
                'No advertiser, order, or Line Item ID matched "' +
                searchText +
                '".';

            return;
        }

        if (
            totalMatches == 1
        ) {

            if (
                matchingAdvertisers.size() == 1
            ) {

                String advertiserName =
                    matchingAdvertisers[0];

                result.matchType = 'ADVERTISER_MATCH';
                result.requiresDisambiguation = false;
                result.matchedAdvertiserName = advertiserName;
                Set<String> advertiserLineItemIds =
                    advertiserToLineItemIds.get(
                        advertiserName
                    );
                result.candidateLineItemCount =
                    advertiserLineItemIds.size();
                result.candidateLineItemIds =
                    String.join(
                        new List<String>(advertiserLineItemIds),
                        '; '
                    );
                result.explanation =
                    'Matched advertiser "' +
                    advertiserName +
                    '" with ' +
                    result.candidateLineItemCount +
                    ' line item(s).';

            } else {

                String orderName =
                    matchingOrders[0];

                result.matchType = 'ORDER_MATCH';
                result.requiresDisambiguation = false;
                result.matchedOrderName = orderName;
                Set<String> orderLineItemIds =
                    orderToLineItemIds.get(
                        orderName
                    );
                result.candidateLineItemCount =
                    orderLineItemIds.size();
                result.candidateLineItemIds =
                    String.join(
                        new List<String>(orderLineItemIds),
                        '; '
                    );
                result.explanation =
                    'Matched order "' +
                    orderName +
                    '" with ' +
                    result.candidateLineItemCount +
                    ' line item(s).';
            }

            return;
        }

        result.matchType = 'MULTIPLE_MATCHES';
        result.requiresDisambiguation = true;
        result.candidateAdvertisers =
            matchingAdvertisers.isEmpty()
                ? null
                : String.join(matchingAdvertisers, '; ');
        result.candidateOrders =
            matchingOrders.isEmpty()
                ? null
                : String.join(matchingOrders, '; ');
        result.explanation =
            'More than one advertiser or order matched "' +
            searchText +
            '". Ask the user which one they meant before proceeding.';
    }


    private static List<String> findMatchingKeys(
        Set<String> keys,
        String searchLower
    ) {

        List<String> matches =
            new List<String>();

        for (
            String key :
            keys
        ) {

            if (
                key != null &&
                (
                    key.toLowerCase().contains(searchLower) ||
                    searchLower.contains(key.toLowerCase())
                )
            ) {
                matches.add(key);
            }
        }

        return matches;
    }


    private static Map<String, Set<String>> buildAdvertiserIndex(
        List<CampaignDataProvider.CampaignDay> rows
    ) {

        Map<String, Set<String>> index =
            new Map<String, Set<String>>();

        for (
            CampaignDataProvider.CampaignDay row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.advertiser) ||
                String.isBlank(row.lineItemId)
            ) {
                continue;
            }

            if (
                !index.containsKey(row.advertiser)
            ) {

                index.put(
                    row.advertiser,
                    new Set<String>()
                );
            }

            index.get(row.advertiser).add(
                row.lineItemId
            );
        }

        return index;
    }


    private static Map<String, Set<String>> buildOrderIndex(
        List<CampaignDataProvider.ContentionRecord> rows
    ) {

        Map<String, Set<String>> index =
            new Map<String, Set<String>>();

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

            index.get(row.orderName).add(
                row.lineItemId
            );
        }

        return index;
    }


    private static Map<String, String> buildOrderToAdvertiserIndex(
        List<CampaignDataProvider.ContentionRecord> rows
    ) {

        Map<String, String> index =
            new Map<String, String>();

        for (
            CampaignDataProvider.ContentionRecord row :
            rows
        ) {

            if (
                row == null ||
                String.isBlank(row.orderName) ||
                String.isBlank(row.advertiserName)
            ) {
                continue;
            }

            index.put(
                row.orderName,
                row.advertiserName
            );
        }

        return index;
    }


    private static Set<String> collectLineItemIds(
        List<CampaignDataProvider.CampaignDay> rows
    ) {

        Set<String> ids =
            new Set<String>();

        for (
            CampaignDataProvider.CampaignDay row :
            rows
        ) {

            if (
                row != null &&
                !String.isBlank(row.lineItemId)
            ) {
                ids.add(row.lineItemId);
            }
        }

        return ids;
    }


    public class EntityResolutionException extends Exception {
    }
}
