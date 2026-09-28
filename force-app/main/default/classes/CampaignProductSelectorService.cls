public with sharing class CampaignProductSelectorService {

    /*
     * ================================================================
     * PRODUCT SELECTOR EVIDENCE ENGINE
     *
     * Standard-object-only implementation. Uses the org's existing
     * Product2 / PricebookEntry catalog (the Media Cloud starter
     * catalog already installed) plus the campaign request Case linked
     * to the Opportunity for budget and objective context.
     *
     * Apex responsibilities:
     *   1. Retrieve active, priced products from the standard catalog.
     *   2. Score each product against budget fit and objective keyword
     *      relevance - both deterministic, explainable calculations.
     *   3. Return ranked candidates as evidence for the agent/human to
     *      choose from.
     *
     * Apex does NOT:
     *   - Add products to the Opportunity automatically.
     *   - Claim audience-segment or inventory-availability matching
     *     beyond what the catalog data actually supports. The org's
     *     current Product2 records carry no audience/segment fields,
     *     so that limitation is surfaced explicitly rather than
     *     fabricated.
     * ================================================================
     */


    public class ProductSelectionRequest {

        @InvocableVariable(
            label='Opportunity ID'
            required=true
        )
        public String opportunityId;
    }


    public class ProductSelectionResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Opportunity ID')
        public String opportunityId;

        @InvocableVariable(label='Budget')
        public Decimal budget;

        @InvocableVariable(label='Campaign Objective')
        public String campaignObjective;

        @InvocableVariable(label='Candidate Count')
        public Decimal candidateCount;

        @InvocableVariable(label='Product Candidates')
        public String productCandidates;

        @InvocableVariable(label='Data Quality Notes')
        public String dataQualityNotes;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    private class ProductCandidate {

        String productId;
        String productName;
        String family;
        Decimal listPrice;
        String pricebookName;
        Decimal budgetFitPercentage;
        Integer keywordMatchCount;
        String matchedKeywords;
        Boolean withinBudget;
    }


    @InvocableMethod(
        label='Recommend Products for Opportunity'
        description='Ranks active priced products from the standard catalog against the linked campaign request budget and objective, returning evidence for human/agent selection. Does not add products to the Opportunity.'
    )
    public static List<ProductSelectionResult> recommend(
        List<ProductSelectionRequest> requests
    ) {

        List<ProductSelectionResult> results =
            new List<ProductSelectionResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        for (
            ProductSelectionRequest request :
            requests
        ) {

            ProductSelectionResult result =
                new ProductSelectionResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.opportunityId)
                ) {

                    throw new ProductSelectorException(
                        'Opportunity ID is required.'
                    );
                }

                result.opportunityId = request.opportunityId;

                Id oppId =
                    Id.valueOf(request.opportunityId);

                List<Case> linkedCases =
                    [
                        SELECT
                            Requested_Budget__c,
                            Campaign_Objective__c
                        FROM Case
                        WHERE Related_Opportunity__c = :oppId
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];

                Decimal budget = null;
                String objective = null;

                if (
                    !linkedCases.isEmpty()
                ) {

                    budget = linkedCases[0].Requested_Budget__c;
                    objective = linkedCases[0].Campaign_Objective__c;
                }

                result.budget = budget;
                result.campaignObjective = objective;

                List<PricebookEntry> entries =
                    [
                        SELECT
                            Product2Id,
                            Product2.Name,
                            Product2.Family,
                            Pricebook2.Name,
                            UnitPrice
                        FROM PricebookEntry
                        WHERE
                            IsActive = true
                            AND Product2.IsActive = true
                        ORDER BY UnitPrice ASC
                        LIMIT 200
                    ];

                List<ProductCandidate> candidates =
                    scoreCandidates(
                        entries,
                        budget,
                        objective
                    );

                sortByRelevance(
                    candidates
                );

                result.candidateCount = candidates.size();
                result.productCandidates =
                    serializeCandidates(
                        candidates
                    );

                result.dataQualityNotes =
                    'The current catalog does not carry audience-segment or ' +
                    'inventory-availability fields on Product2. Ranking is ' +
                    'based only on budget fit and objective keyword overlap ' +
                    'with product name and family. Availability must still ' +
                    'be confirmed through the Forecast/Availability step ' +
                    'before a Media Plan is finalized.';

                result.explanation =
                    String.isBlank(objective)
                        ? 'No campaign objective text was available, so products are ranked by budget fit only.'
                        : 'Products are ranked by budget fit and objective keyword overlap. This is evidence for selection, not an automatic addition to the Opportunity.';

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static List<ProductCandidate> scoreCandidates(
        List<PricebookEntry> entries,
        Decimal budget,
        String objective
    ) {

        List<String> objectiveKeywords =
            extractKeywords(objective);

        List<ProductCandidate> candidates =
            new List<ProductCandidate>();

        for (
            PricebookEntry entry :
            entries
        ) {

            ProductCandidate candidate =
                new ProductCandidate();

            candidate.productId = entry.Product2Id;
            candidate.productName = entry.Product2.Name;
            candidate.family = entry.Product2.Family;
            candidate.listPrice = entry.UnitPrice;
            candidate.pricebookName = entry.Pricebook2.Name;

            candidate.withinBudget =
                budget == null ||
                entry.UnitPrice == null ||
                entry.UnitPrice <= budget;

            candidate.budgetFitPercentage =
                (
                    budget != null &&
                    budget > 0 &&
                    entry.UnitPrice != null
                )
                    ? (entry.UnitPrice / budget) * 100
                    : null;

            List<String> matched =
                matchKeywords(
                    objectiveKeywords,
                    entry.Product2.Name,
                    entry.Product2.Family
                );

            candidate.keywordMatchCount = matched.size();
            candidate.matchedKeywords =
                matched.isEmpty()
                    ? null
                    : String.join(matched, ', ');

            candidates.add(candidate);
        }

        return candidates;
    }


    private static List<String> extractKeywords(
        String objective
    ) {

        List<String> keywords =
            new List<String>();

        if (
            String.isBlank(objective)
        ) {
            return keywords;
        }

        for (
            String token :
            objective.toLowerCase().split('[^a-z0-9]+')
        ) {

            if (
                token.length() > 3
            ) {
                keywords.add(token);
            }
        }

        return keywords;
    }


    private static List<String> matchKeywords(
        List<String> objectiveKeywords,
        String productName,
        String productFamily
    ) {

        List<String> matched =
            new List<String>();

        if (
            objectiveKeywords == null ||
            objectiveKeywords.isEmpty()
        ) {
            return matched;
        }

        String haystack =
            (
                (
                    String.isBlank(productName)
                        ? ''
                        : productName
                ) +
                ' ' +
                (
                    String.isBlank(productFamily)
                        ? ''
                        : productFamily
                )
            ).toLowerCase();

        for (
            String keyword :
            objectiveKeywords
        ) {

            if (
                haystack.contains(keyword)
            ) {
                matched.add(keyword);
            }
        }

        return matched;
    }


    private static void sortByRelevance(
        List<ProductCandidate> candidates
    ) {

        if (
            candidates == null ||
            candidates.size() < 2
        ) {
            return;
        }

        for (
            Integer i = 1;
            i < candidates.size();
            i++
        ) {

            ProductCandidate current =
                candidates[i];

            Integer j = i - 1;

            while (
                j >= 0 &&
                isLowerRank(
                    candidates[j],
                    current
                )
            ) {

                candidates[j + 1] = candidates[j];
                j--;
            }

            candidates[j + 1] = current;
        }
    }


    private static Boolean isLowerRank(
        ProductCandidate left,
        ProductCandidate right
    ) {

        if (
            left.keywordMatchCount !=
            right.keywordMatchCount
        ) {

            return
                left.keywordMatchCount <
                right.keywordMatchCount;
        }

        if (
            left.withinBudget !=
            right.withinBudget
        ) {

            return
                left.withinBudget == false &&
                right.withinBudget == true;
        }

        Decimal leftPrice =
            left.listPrice == null
                ? 0
                : left.listPrice;

        Decimal rightPrice =
            right.listPrice == null
                ? 0
                : right.listPrice;

        return leftPrice > rightPrice;
    }


    private static String serializeCandidates(
        List<ProductCandidate> candidates
    ) {

        List<Object> payload =
            new List<Object>();

        Integer topN =
            candidates.size() < 20
                ? candidates.size()
                : 20;

        for (
            Integer i = 0;
            i < topN;
            i++
        ) {

            ProductCandidate candidate =
                candidates[i];

            Map<String, Object> record =
                new Map<String, Object>();

            record.put('productId', candidate.productId);
            record.put('productName', candidate.productName);
            record.put('family', candidate.family);
            record.put('listPrice', candidate.listPrice);
            record.put('pricebookName', candidate.pricebookName);
            record.put('withinBudget', candidate.withinBudget);
            record.put(
                'budgetFitPercentage',
                candidate.budgetFitPercentage
            );
            record.put(
                'keywordMatchCount',
                candidate.keywordMatchCount
            );
            record.put(
                'matchedKeywords',
                candidate.matchedKeywords
            );

            payload.add(record);
        }

        return JSON.serialize(payload);
    }


    public class ProductSelectorException extends Exception {
    }
}
