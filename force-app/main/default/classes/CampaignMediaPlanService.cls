public with sharing class CampaignMediaPlanService {

    /*
     * ================================================================
     * MEDIA PLAN CREATION ENGINE
     *
     * Standard-object-only implementation of the diagram's "Media Plan
     * using the Media Cloud Quote structure and Quote Line Items" step.
     *
     * Uses the org's native Media Cloud objects:
     *   - Quote (standard) - the commercial container.
     *   - AdQuote (native Media Cloud) - media-specific plan detail,
     *     linked to the Quote via QuoteId.
     *   - QuoteLineItem (standard) - one per selected product.
     *   - AdQuoteLine (native Media Cloud) - media-specific line
     *     detail, master-detail to AdQuote, linked to the matching
     *     QuoteLineItem.
     *
     * No custom objects are used. This is a deterministic creation
     * step - it takes the human/agent-approved product selection from
     * CampaignProductSelectorService and materializes it as a real
     * Media Plan. It does not select products itself.
     * ================================================================
     */


    public class MediaPlanRequest {

        @InvocableVariable(
            label='Opportunity ID'
            required=true
        )
        public String opportunityId;

        @InvocableVariable(
            label='Selected Product IDs'
            description='Semicolon-separated Product IDs, e.g. "01txx01;01txx02". A plain string, not a list - Agentforce action inputs of List type hit a platform validation bug when created via Agent Action wizard.'
            required=true
        )
        public String selectedProductIds;
    }


    public class MediaPlanResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Opportunity ID')
        public String opportunityId;

        @InvocableVariable(label='Quote ID')
        public String quoteId;

        @InvocableVariable(label='Ad Quote ID')
        public String adQuoteId;

        @InvocableVariable(label='Line Item Count')
        public Decimal lineItemCount;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Create Media Plan from Selected Products'
        description='Creates a Quote/AdQuote and matching QuoteLineItem/AdQuoteLine records for the products selected from Product Selector evidence. Requires human/agent-approved product IDs; does not select products itself.'
    )
    public static List<MediaPlanResult> createMediaPlan(
        List<MediaPlanRequest> requests
    ) {

        List<MediaPlanResult> results =
            new List<MediaPlanResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        for (
            MediaPlanRequest request :
            requests
        ) {

            MediaPlanResult result =
                new MediaPlanResult();

            result.success = false;

            Savepoint savepoint =
                Database.setSavepoint();

            try {

                if (
                    request == null ||
                    String.isBlank(request.opportunityId)
                ) {

                    throw new MediaPlanException(
                        'Opportunity ID is required.'
                    );
                }

                if (
                    String.isBlank(request.selectedProductIds)
                ) {

                    throw new MediaPlanException(
                        'At least one selected Product ID is required.'
                    );
                }

                List<String> selectedProductIdList =
                    request.selectedProductIds.split(';');

                result.opportunityId = request.opportunityId;

                Id oppId =
                    Id.valueOf(request.opportunityId);

                Opportunity opp =
                    [
                        SELECT
                            Id,
                            Name,
                            AccountId,
                            CloseDate
                        FROM Opportunity
                        WHERE Id = :oppId
                        LIMIT 1
                    ];

                List<Case> linkedCases =
                    [
                        SELECT
                            Requested_Budget__c,
                            Flight_Start_Date__c,
                            Flight_End_Date__c
                        FROM Case
                        WHERE Related_Opportunity__c = :oppId
                        ORDER BY CreatedDate DESC
                        LIMIT 1
                    ];

                Decimal budget = null;
                Date flightStart = null;
                Date flightEnd = null;

                if (
                    !linkedCases.isEmpty()
                ) {

                    budget = linkedCases[0].Requested_Budget__c;
                    flightStart = linkedCases[0].Flight_Start_Date__c;
                    flightEnd = linkedCases[0].Flight_End_Date__c;
                }

                if (
                    flightEnd == null
                ) {
                    flightEnd = opp.CloseDate;
                }

                Set<Id> productIds =
                    new Set<Id>();

                for (
                    String productId :
                    selectedProductIdList
                ) {

                    if (
                        !String.isBlank(productId)
                    ) {
                        productIds.add(
                            Id.valueOf(productId.trim())
                        );
                    }
                }

                Id standardPricebookId =
                    [
                        SELECT Id
                        FROM Pricebook2
                        WHERE IsStandard = true
                        LIMIT 1
                    ].Id;

                Map<Id, PricebookEntry> entriesByProduct =
                    new Map<Id, PricebookEntry>();

                for (
                    PricebookEntry entry :
                    [
                        SELECT
                            Id,
                            Product2Id,
                            Product2.Family,
                            UnitPrice
                        FROM PricebookEntry
                        WHERE
                            Product2Id IN :productIds
                            AND Pricebook2Id = :standardPricebookId
                            AND IsActive = true
                    ]
                ) {

                    entriesByProduct.put(
                        entry.Product2Id,
                        entry
                    );
                }

                if (
                    entriesByProduct.isEmpty()
                ) {

                    throw new MediaPlanException(
                        'None of the selected products have an active Standard Price Book entry.'
                    );
                }

                Quote newQuote =
                    new Quote();

                newQuote.Name =
                    opp.Name + ' - Media Plan';

                newQuote.OpportunityId = opp.Id;
                newQuote.Pricebook2Id = standardPricebookId;
                newQuote.ExpirationDate = flightEnd;

                insert newQuote;

                Set<String> mediaTypes =
                    new Set<String>();

                for (
                    PricebookEntry entry :
                    entriesByProduct.values()
                ) {

                    if (
                        !String.isBlank(entry.Product2.Family)
                    ) {
                        mediaTypes.add(entry.Product2.Family);
                    }
                }

                AdQuote newAdQuote =
                    new AdQuote();

                newAdQuote.Name =
                    opp.Name + ' - Ad Media Plan';

                newAdQuote.QuoteId = newQuote.Id;
                newAdQuote.Budget = budget;
                newAdQuote.StartDate =
                    flightStart != null
                        ? Datetime.newInstance(
                            flightStart.year(),
                            flightStart.month(),
                            flightStart.day()
                          )
                        : null;
                newAdQuote.EndDate =
                    flightEnd != null
                        ? Datetime.newInstance(
                            flightEnd.year(),
                            flightEnd.month(),
                            flightEnd.day()
                          )
                        : null;

                if (
                    !mediaTypes.isEmpty()
                ) {
                    newAdQuote.MediaType =
                        String.join(
                            new List<String>(mediaTypes),
                            ';'
                        );
                }

                insert newAdQuote;

                List<QuoteLineItem> lineItems =
                    new List<QuoteLineItem>();

                Map<Id, PricebookEntry> lineItemProductByPricebookEntry =
                    new Map<Id, PricebookEntry>();

                for (
                    PricebookEntry entry :
                    entriesByProduct.values()
                ) {

                    QuoteLineItem lineItem =
                        new QuoteLineItem();

                    lineItem.QuoteId = newQuote.Id;
                    lineItem.PricebookEntryId = entry.Id;
                    lineItem.Quantity = 1;
                    lineItem.UnitPrice = entry.UnitPrice;

                    lineItems.add(lineItem);
                }

                insert lineItems;

                Map<Id, Id> pricebookEntryIdToLineItemId =
                    new Map<Id, Id>();

                for (
                    QuoteLineItem lineItem :
                    lineItems
                ) {

                    pricebookEntryIdToLineItemId.put(
                        lineItem.PricebookEntryId,
                        lineItem.Id
                    );
                }

                List<AdQuoteLine> adQuoteLines =
                    new List<AdQuoteLine>();

                for (
                    PricebookEntry entry :
                    entriesByProduct.values()
                ) {

                    AdQuoteLine adLine =
                        new AdQuoteLine();

                    adLine.Name =
                        (
                            String.isBlank(entry.Product2.Family)
                                ? 'Placement'
                                : entry.Product2.Family
                        ) +
                        ' - ' +
                        opp.Name;

                    adLine.AdQuoteId = newAdQuote.Id;
                    adLine.QuoteLineItemId =
                        pricebookEntryIdToLineItemId.get(
                            entry.Id
                        );
                    adLine.MediaType = entry.Product2.Family;
                    adLine.Budget = entry.UnitPrice;
                    adLine.AdRequestedQuantity = 1;
                    adLine.AdRequestedStartDate =
                        newAdQuote.StartDate;
                    adLine.AdRequestedEndDate =
                        newAdQuote.EndDate;

                    adQuoteLines.add(adLine);
                }

                insert adQuoteLines;

                result.quoteId = newQuote.Id;
                result.adQuoteId = newAdQuote.Id;
                result.lineItemCount = adQuoteLines.size();

                result.explanation =
                    'Media Plan created with ' +
                    adQuoteLines.size() +
                    ' ad placement(s). Availability must still be checked ' +
                    'against a connected ad server before this plan is ' +
                    'presented for approval.';

                result.success = true;

            } catch (Exception e) {

                Database.rollback(savepoint);

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    public class MediaPlanException extends Exception {
    }
}
