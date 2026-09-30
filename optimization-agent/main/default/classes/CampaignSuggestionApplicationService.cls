public with sharing class CampaignSuggestionApplicationService {

    /*
     * ================================================================
     * OPTIMIZATION SUGGESTION APPLICATION ENGINE
     *
     * This is the write path behind the per-suggestion Confirm/Cancel
     * buttons in Agentforce. The Optimize_Campaign_From_Historical_Delivery
     * action stays 100% read-only evidence generation - it never calls
     * this class itself. Atlas (the agent) only calls this action after
     * the human clicks Confirm on one specific suggestion, and this
     * action is registered with isConfirmationRequired = true in its
     * GenAiFunction, so Agentforce's native Confirm/Cancel UI is what
     * actually gates the call - Apex does not re-ask for approval here.
     *
     * The line items evaluated by the Optimization Agent today
     * (9100xxxxxxx style IDs) come from CSV-simulated GAM delivery data,
     * not from real Salesforce records - so this always find-or-creates
     * the Account/Opportunity by advertiser name.
     *
     * AMENDMENT behavior (new): if a real Order already exists for that
     * advertiser Account, the new Quote is an AMENDMENT - it carries
     * forward the Order's current real line items AS-IS, plus the newly
     * confirmed suggestion(s), so the Quote represents the full updated
     * plan (not just the suggestion in isolation) ready to present to
     * the client. Its Status is set to 'Needs Review' so it is one
     * click away from entering the real Quote.Media_Plan_Approval
     * process. If no Order exists yet for that advertiser, it falls
     * back to creating a standalone Draft Quote for just the
     * suggestion(s), same as before.
     *
     *   Account (find-or-create, by exact advertiser name)
     *     -> Opportunity (find-or-create, "<advertiser> - Optimization Suggestions")
     *          -> Quote (ALWAYS NEW per confirmed group - Needs Review
     *                     if amending an Order, else Draft)
     *               -> AdQuote (new, one per Quote)
     *                    -> QuoteLineItem(s) carried forward from the
     *                       Order (if amending) + the confirmed
     *                       suggestion(s)' own QuoteLineItem/AdQuoteLine
     *
     * The result always reports BOTH the new Quote's record link and
     * (when amending) the existing Order's record link, so a reviewer
     * can see the proposed change alongside what it would replace.
     *
     * Everything this method creates is left short of any live change.
     * It does NOT touch the live Order, AdOrderItem, or ad server
     * itself - approving this Quote is not the same as applying it to
     * the real Order, which is still a separate, not-yet-automated step.
     * ================================================================
     */


    private static final String OPTIMIZATION_OPPORTUNITY_SUFFIX =
        ' - Optimization Suggestions';

    private static final String DEFAULT_PRODUCT_NAME =
        'Digital Banner';


    public class SuggestionApplicationRequest {

        @InvocableVariable(
            label='Source Line Item ID'
            required=true
            description='The GAM/CSV Line Item ID the suggestion was generated for.'
        )
        public String lineItemId;

        @InvocableVariable(
            label='Advertiser Name'
            required=true
        )
        public String advertiserName;

        @InvocableVariable(
            label='Suggestion Summary'
            required=true
            description='Plain-English description of the one suggestion being applied, e.g. "Expand targeting to include the Afternoon daypart (12:00-17:59)".'
        )
        public String suggestionSummary;

        @InvocableVariable(
            label='Suggested Budget'
            description='Optional budget/spend estimate for this change, if the evidence included one.'
        )
        public Decimal suggestedBudget;
    }


    public class SuggestionApplicationResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Quote ID')
        public String quoteId;

        @InvocableVariable(label='Quote Line Item ID')
        public String quoteLineItemId;

        @InvocableVariable(label='Explanation')
        public String explanation;

        @InvocableVariable(label='Quote Link')
        public String quoteLinkHtml;

        @InvocableVariable(label='Order Link')
        public String orderLinkHtml;
    }


    @InvocableMethod(
        label='Apply Optimization Suggestion'
        description='Creates or amends a Quote reflecting one or more human-approved optimization suggestions. If a real Order already exists for the advertiser, creates an Amendment Quote carrying forward the Order\'s current line items plus the new suggestion(s), set to Needs Review so it is ready to submit for approval. Otherwise creates a standalone Draft Quote. Always returns both the Quote link and (when amending) the Order link. Only call this after the user has confirmed the suggestion(s) - this action requires Agentforce confirmation. If the user confirms several suggestions for the same advertiser/line item in one action, pass them all in a single call - they will share one new Quote. Separate calls each get their own new Quote.'
    )
    public static List<SuggestionApplicationResult> apply(
        List<SuggestionApplicationRequest> requests
    ) {

        List<SuggestionApplicationResult> results =
            new List<SuggestionApplicationResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        /*
         * All requests passed into ONE call to this method are treated
         * as "confirmed together" and grouped onto a single new Quote
         * per advertiser/line item combination - covering the case
         * where a user approves several suggestions in one action. A
         * separate invocation of this method (e.g. suggestions
         * confirmed one at a time across separate turns) always gets
         * its own brand new Quote, per group, because each call starts
         * this grouping fresh.
         */
        Map<String, List<SuggestionApplicationRequest>> requestsByGroup =
            new Map<String, List<SuggestionApplicationRequest>>();
        List<String> groupOrder = new List<String>();

        for (SuggestionApplicationRequest request : requests) {

            if (
                request == null ||
                String.isBlank(request.lineItemId) ||
                String.isBlank(request.advertiserName) ||
                String.isBlank(request.suggestionSummary)
            ) {
                continue;
            }

            String groupKey = request.advertiserName + '|' + request.lineItemId;

            if (!requestsByGroup.containsKey(groupKey)) {
                requestsByGroup.put(groupKey, new List<SuggestionApplicationRequest>());
                groupOrder.add(groupKey);
            }

            requestsByGroup.get(groupKey).add(request);
        }

        Map<SuggestionApplicationRequest, SuggestionApplicationResult> resultByRequest =
            new Map<SuggestionApplicationRequest, SuggestionApplicationResult>();

        for (String groupKey : groupOrder) {

            List<SuggestionApplicationRequest> groupRequests = requestsByGroup.get(groupKey);

            Savepoint savepoint = Database.setSavepoint();

            try {

                SuggestionApplicationRequest firstRequest = groupRequests[0];

                Account advertiserAccount =
                    findOrCreateAccount(firstRequest.advertiserName);

                Order existingOrder = findMostRecentOrder(advertiserAccount.Id);

                /*
                 * When amending a real Order, the Amendment Quote
                 * belongs on that Order's OWN original Opportunity
                 * (via Order.QuoteId -> Quote.OpportunityId), not a
                 * separate "<advertiser> - Optimization Suggestions"
                 * Opportunity - otherwise the amendment history ends
                 * up disconnected from the campaign it actually
                 * belongs to. Only fall back to find-or-create the
                 * dedicated Optimization Suggestions Opportunity when
                 * there is no existing Order (nothing to amend yet).
                 */
                Opportunity opportunity =
                    existingOrder != null
                        ? resolveOriginalOpportunity(existingOrder, advertiserAccount, firstRequest.advertiserName)
                        : findOrCreateOpportunity(advertiserAccount, firstRequest.advertiserName);

                String combinedSummary = groupRequests.size() == 1
                    ? firstRequest.suggestionSummary
                    : groupRequests.size() + ' suggestions';

                Quote quoteRecord =
                    createNewQuote(
                        opportunity,
                        firstRequest.lineItemId,
                        combinedSummary,
                        existingOrder
                    );

                AdQuote adQuote = findOrCreateAdQuote(quoteRecord);

                PricebookEntry pricebookEntry =
                    resolvePricebookEntry(quoteRecord.Pricebook2Id);

                /*
                 * AMEND behavior: when a real Order already exists for
                 * this advertiser, the new Quote represents the FULL
                 * amended plan - the Order's current real line items,
                 * carried forward as-is, plus the newly confirmed
                 * suggestion(s) - not just the suggestion in isolation.
                 * This is what gets presented to the client for
                 * approval as the updated plan.
                 */
                List<QuoteLineItem> carriedForwardLineItems =
                    existingOrder != null
                        ? copyOrderLineItemsToQuote(existingOrder.Id, quoteRecord.Id)
                        : new List<QuoteLineItem>();

                List<QuoteLineItem> lineItemsToInsert = new List<QuoteLineItem>();

                for (SuggestionApplicationRequest request : groupRequests) {

                    QuoteLineItem lineItem = new QuoteLineItem();
                    lineItem.QuoteId = quoteRecord.Id;
                    lineItem.PricebookEntryId = pricebookEntry.Id;
                    lineItem.Product2Id = pricebookEntry.Product2Id;
                    lineItem.Quantity = 1;
                    lineItem.UnitPrice =
                        request.suggestedBudget != null
                            ? request.suggestedBudget
                            : pricebookEntry.UnitPrice;
                    lineItem.Description = truncate(request.suggestionSummary, 255);

                    lineItemsToInsert.add(lineItem);
                }

                insert lineItemsToInsert;

                List<AdQuoteLine> adLinesToInsert = new List<AdQuoteLine>();

                for (Integer i = 0; i < groupRequests.size(); i++) {

                    SuggestionApplicationRequest request = groupRequests[i];
                    QuoteLineItem lineItem = lineItemsToInsert[i];

                    AdQuoteLine adLine = new AdQuoteLine();
                    adLine.AdQuoteId = adQuote.Id;
                    adLine.QuoteLineItemId = lineItem.Id;
                    adLine.Name = truncate(request.suggestionSummary, 80);
                    adLine.MediaType = 'Digital';

                    if (request.suggestedBudget != null) {
                        adLine.Budget = request.suggestedBudget;
                    }

                    adLinesToInsert.add(adLine);
                }

                insert adLinesToInsert;

                /*
                 * Tried surfacing quoteLinkHtml/orderLinkHtml as real
                 * <a> anchor tags for a clickable in-chat card, but
                 * confirmed live that Agentforce's response layer
                 * redacts ANY URL-shaped string in ANY output field
                 * (even the href inside raw HTML) to the literal text
                 * "URL_Redacted" - not just plain-text URLs in the
                 * model's own prose. No admin-configurable masking rule
                 * was found in this org's Setup (checked Einstein
                 * Setup, Agentforce Gateway Policies) to disable it, so
                 * this is treated as a hard platform behavior. Per the
                 * user's explicit choice, these fields are left
                 * deployed (already registered as real outputs in the
                 * Agentforce Action - this org's UI doesn't support
                 * removing outputs either) but always left null; only
                 * the plain record ID in "explanation" is relied on,
                 * since that's the one thing confirmed to reliably
                 * reach the user.
                 */
                for (Integer i = 0; i < groupRequests.size(); i++) {

                    SuggestionApplicationRequest request = groupRequests[i];

                    SuggestionApplicationResult result = new SuggestionApplicationResult();
                    result.success = true;
                    result.quoteId = quoteRecord.Id;
                    result.quoteLineItemId = lineItemsToInsert[i].Id;
                    result.quoteLinkHtml = null;
                    result.orderLinkHtml = null;

                    String suggestionDescriptor = groupRequests.size() == 1
                        ? 'this confirmed suggestion'
                        : 'these ' + groupRequests.size() + ' confirmed suggestions';

                    if (existingOrder != null) {
                        result.explanation =
                            'Created Amendment Quote reflecting ' + suggestionDescriptor +
                            ' plus the current Order\'s existing line items. Needs Review status - submit for approval, ' +
                            'then present to the client. Once approved, the changes still need to be applied to the live Order.\n' +
                            'Amendment Quote ID: ' + quoteRecord.Id + '\n' +
                            'Current Order ID: ' + existingOrder.Id;
                    } else {
                        result.explanation =
                            'No existing Order found for this advertiser yet, so created a standalone Draft Quote for ' +
                            suggestionDescriptor + ' instead of an amendment. Requires normal Quote review/approval ' +
                            'before it could become a real Order.\n' +
                            'Quote ID: ' + quoteRecord.Id;
                    }

                    resultByRequest.put(request, result);
                }

            } catch (Exception e) {

                Database.rollback(savepoint);

                SuggestionApplicationResult failureResult = new SuggestionApplicationResult();
                failureResult.success = false;
                failureResult.explanation = e.getMessage();

                for (SuggestionApplicationRequest request : groupRequests) {
                    resultByRequest.put(request, failureResult);
                }
            }
        }

        for (SuggestionApplicationRequest request : requests) {

            SuggestionApplicationResult result = resultByRequest.get(request);

            if (result == null) {
                result = new SuggestionApplicationResult();
                result.success = false;
                result.explanation = 'Source Line Item ID, Advertiser Name, and Suggestion Summary are all required.';
            }

            results.add(result);
        }

        return results;
    }


    private static Account findOrCreateAccount(
        String advertiserName
    ) {

        List<Account> existing =
            [
                SELECT Id, Name
                FROM Account
                WHERE Name = :advertiserName
                LIMIT 1
            ];

        if (
            !existing.isEmpty()
        ) {
            return existing[0];
        }

        Account newAccount =
            new Account();

        newAccount.Name = advertiserName;

        insert newAccount;

        return newAccount;
    }


    private static Opportunity findOrCreateOpportunity(
        Account advertiserAccount,
        String advertiserName
    ) {

        String opportunityName =
            advertiserName +
            OPTIMIZATION_OPPORTUNITY_SUFFIX;

        List<Opportunity> existing =
            [
                SELECT Id, Name, AccountId, Pricebook2Id
                FROM Opportunity
                WHERE AccountId = :advertiserAccount.Id
                AND Name = :opportunityName
                LIMIT 1
            ];

        if (
            !existing.isEmpty()
        ) {
            return existing[0];
        }

        Opportunity newOpportunity =
            new Opportunity();

        newOpportunity.Name = opportunityName;
        newOpportunity.AccountId = advertiserAccount.Id;
        newOpportunity.StageName = 'Prospecting';
        newOpportunity.CloseDate = Date.today().addDays(90);

        insert newOpportunity;

        return newOpportunity;
    }


    private static Order findMostRecentOrder(Id accountId) {

        List<Order> existingOrders = [
            SELECT Id, OrderNumber, Pricebook2Id, QuoteId, Quote.OpportunityId
            FROM Order
            WHERE AccountId = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return existingOrders.isEmpty() ? null : existingOrders[0];
    }


    private static Opportunity resolveOriginalOpportunity(
        Order existingOrder, Account advertiserAccount, String advertiserName
    ) {

        if (existingOrder.QuoteId != null && existingOrder.Quote.OpportunityId != null) {
            return new Opportunity(Id = existingOrder.Quote.OpportunityId);
        }

        return findOrCreateOpportunity(advertiserAccount, advertiserName);
    }


    private static List<QuoteLineItem> copyOrderLineItemsToQuote(Id orderId, Id quoteId) {

        List<OrderItem> orderItems = [
            SELECT Id, PricebookEntryId, Product2Id, Quantity, UnitPrice, Description
            FROM OrderItem
            WHERE OrderId = :orderId
        ];

        if (orderItems.isEmpty()) {
            return new List<QuoteLineItem>();
        }

        List<QuoteLineItem> carriedForward = new List<QuoteLineItem>();

        for (OrderItem oi : orderItems) {
            QuoteLineItem qli = new QuoteLineItem();
            qli.QuoteId = quoteId;
            qli.PricebookEntryId = oi.PricebookEntryId;
            qli.Product2Id = oi.Product2Id;
            qli.Quantity = oi.Quantity;
            qli.UnitPrice = oi.UnitPrice;
            qli.Description = oi.Description;
            carriedForward.add(qli);
        }

        insert carriedForward;

        return carriedForward;
    }




    private static Quote createNewQuote(
        Opportunity opportunity,
        String sourceLineItemId,
        String suggestionSummary,
        Order existingOrder
    ) {

        String quoteName =
            truncate(
                (existingOrder != null ? 'Amendment - ' : 'Optimization Suggestion - ') +
                sourceLineItemId +
                ' - ' +
                suggestionSummary,
                80
            );

        Pricebook2 standardPricebook =
            [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = true
                LIMIT 1
            ];

        Quote newQuote =
            new Quote();

        newQuote.Name = quoteName;
        newQuote.OpportunityId = opportunity.Id;
        newQuote.Pricebook2Id = existingOrder != null && existingOrder.Pricebook2Id != null
            ? existingOrder.Pricebook2Id
            : standardPricebook.Id;
        newQuote.Status = existingOrder != null ? 'Needs Review' : 'Draft';
        newQuote.Amends_Order__c = existingOrder != null ? existingOrder.Id : null;
        newQuote.Description =
            (existingOrder != null
                ? 'Amendment Quote carrying forward Order ' + existingOrder.OrderNumber + '\'s current line items, '
                : 'Auto-created from a human-confirmed Optimization Agent suggestion ') +
            'for source line item ' +
            sourceLineItemId +
            '. Requires review and approval before any live change is made.';

        insert newQuote;

        return newQuote;
    }


    private static AdQuote findOrCreateAdQuote(
        Quote quoteRecord
    ) {

        List<AdQuote> existing =
            [
                SELECT Id, Name, QuoteId
                FROM AdQuote
                WHERE QuoteId = :quoteRecord.Id
                LIMIT 1
            ];

        if (
            !existing.isEmpty()
        ) {
            return existing[0];
        }

        AdQuote newAdQuote =
            new AdQuote();

        newAdQuote.Name = quoteRecord.Name;
        newAdQuote.QuoteId = quoteRecord.Id;

        insert newAdQuote;

        return newAdQuote;
    }


    private static PricebookEntry resolvePricebookEntry(
        Id pricebook2Id
    ) {

        List<PricebookEntry> preferredEntries =
            [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebook2Id
                AND Product2.Name = :DEFAULT_PRODUCT_NAME
                AND IsActive = true
                LIMIT 1
            ];

        if (
            !preferredEntries.isEmpty()
        ) {
            return preferredEntries[0];
        }

        List<PricebookEntry> anyActiveEntry =
            [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebook2Id
                AND IsActive = true
                LIMIT 1
            ];

        if (
            anyActiveEntry.isEmpty()
        ) {

            throw new SuggestionApplicationException(
                'No active Pricebook Entry exists on the Standard Price Book. ' +
                'Add at least one active product to the Standard Price Book before applying suggestions.'
            );
        }

        return anyActiveEntry[0];
    }


    private static String truncate(
        String text,
        Integer maxLength
    ) {

        if (
            text == null
        ) {
            return null;
        }

        return text.length() > maxLength
            ? text.substring(0, maxLength)
            : text;
    }


    public class SuggestionApplicationException extends Exception {
    }
}
