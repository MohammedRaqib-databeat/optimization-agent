public with sharing class CampaignAmendmentApplicationService {

    /*
     * ================================================================
     * APPLY AN APPROVED OPTIMIZATION AMENDMENT TO THE LIVE ORDER
     *
     * Closes the loop CampaignSuggestionApplicationService.apply()
     * starts: once a human/client approves an Amendment Quote (real
     * Order already existed for the advertiser, Quote.Status =
     * 'Approved'/'Accepted', Quote.Amends_Order__c populated), this
     * REPLACES the target Order's line items to match the approved
     * Quote's current line items exactly - not just "add the new
     * suggestion alongside the old ones":
     *
     *   - Products present on the Quote but not the Order -> new
     *     OrderItem/AdOrderItem inserted.
     *   - Products present on both -> the Order's existing OrderItem
     *     is updated to the Quote's Quantity/UnitPrice (this is how an
     *     underperforming line gets genuinely overruled/replaced - the
     *     human edits or removes it on the Quote before approving,
     *     and that becomes the new Order state).
     *   - Products present on the Order but no longer on the approved
     *     Quote -> removed from the Order entirely.
     *
     * After syncing, it calls the existing GAMOrderPushService.push()
     * to push the updated Order to Google Ad Manager for real -
     * reusing the already-verified push logic (which now also updates
     * existing same-named GAM Line Items with the new values, not just
     * find-or-create).
     *
     * This is a real, live, irreversible write to both Salesforce and
     * an external ad server - it must only run after explicit human
     * confirmation, exactly like every other write path in this
     * project.
     * ================================================================
     */

    public class ApplyAmendmentRequest {
        @InvocableVariable(label='Amendment Quote ID' required=true)
        public String quoteId;
    }

    public class ApplyAmendmentResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Order ID')
        public String orderId;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }

    public class AmendmentApplicationException extends Exception {}


    private static final Set<String> APPROVED_STATUSES = new Set<String>{ 'Approved', 'Accepted' };


    @InvocableMethod(
        label='Apply Approved Amendment to Order'
        description='Applies an approved Optimization Amendment Quote to the real Order it amends - replacing the Order\'s line items to match the approved Quote exactly (new/changed lines override what they replace, removed lines are dropped) - then pushes the updated Order to Google Ad Manager. Only call this after the user has explicitly confirmed this specific amendment should go live. Real, live, irreversible change to both Salesforce and GAM.'
    )
    public static List<ApplyAmendmentResult> applyApprovedAmendment(List<ApplyAmendmentRequest> requests) {

        List<ApplyAmendmentResult> results = new List<ApplyAmendmentResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (ApplyAmendmentRequest request : requests) {

            ApplyAmendmentResult result = new ApplyAmendmentResult();
            result.success = false;

            try {
                if (request == null || String.isBlank(request.quoteId)) {
                    throw new AmendmentApplicationException('Amendment Quote ID is required.');
                }

                Quote amendmentQuote = [
                    SELECT Id, Status, Amends_Order__c
                    FROM Quote
                    WHERE Id = :Id.valueOf(request.quoteId)
                    LIMIT 1
                ];

                if (!APPROVED_STATUSES.contains(amendmentQuote.Status)) {
                    throw new AmendmentApplicationException(
                        'This Quote is ' + amendmentQuote.Status + ', not Approved/Accepted. ' +
                        'It must be approved before its changes can be applied to the Order.'
                    );
                }

                if (amendmentQuote.Amends_Order__c == null) {
                    throw new AmendmentApplicationException(
                        'This Quote is not an Optimization Amendment (no Order linked via Amends_Order__c) - ' +
                        'nothing to apply.'
                    );
                }

                Id orderId = amendmentQuote.Amends_Order__c;
                result.orderId = orderId;

                syncOrderToApprovedQuote(orderId, amendmentQuote.Id);

                /*
                 * The OrderItem sync above is DML - Salesforce forbids
                 * a callout (the GAM push) in the same transaction as
                 * prior DML ("You have uncommitted work pending").
                 * Queueable starts a fresh transaction once this one
                 * commits, which is the standard way to do a callout
                 * right after DML that can't simply be reordered (the
                 * push needs the just-synced OrderItem values). The
                 * push itself still logs GAM_ORDER_PUSHED/PUSH_FAILED
                 * to the Case-based audit trail exactly as before, so
                 * the real outcome is always recorded even though this
                 * method returns before the push actually runs.
                 */
                System.enqueueJob(new AmendmentPushQueueable(orderId));

                result.success = true;
                result.explanation = 'Applied the approved amendment to Order ' + orderId +
                    ' in Salesforce, and queued the push to Google Ad Manager (runs momentarily - check the ' +
                    'Order\'s Google Ad Manager status, or the audit log, for the final push result).';

            } catch (Exception e) {
                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static void syncOrderToApprovedQuote(Id orderId, Id quoteId) {

        List<OrderItem> currentOrderItems = [
            SELECT Id, Product2Id, PricebookEntryId, Quantity, UnitPrice
            FROM OrderItem
            WHERE OrderId = :orderId
        ];

        List<QuoteLineItem> approvedQuoteLines = [
            SELECT Id, Product2Id, PricebookEntryId, Quantity, UnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ];

        if (approvedQuoteLines.isEmpty()) {
            throw new AmendmentApplicationException('The approved Quote has no line items - refusing to empty out the Order.');
        }

        Map<Id, OrderItem> orderItemByProduct = new Map<Id, OrderItem>();
        for (OrderItem oi : currentOrderItems) {
            orderItemByProduct.put(oi.Product2Id, oi);
        }

        Map<Id, QuoteLineItem> quoteLineByProduct = new Map<Id, QuoteLineItem>();
        for (QuoteLineItem qli : approvedQuoteLines) {
            quoteLineByProduct.put(qli.Product2Id, qli);
        }

        List<OrderItem> toUpdate = new List<OrderItem>();
        List<OrderItem> toInsert = new List<OrderItem>();
        List<Id> toDeleteIds = new List<Id>();

        for (Id productId : quoteLineByProduct.keySet()) {

            QuoteLineItem qli = quoteLineByProduct.get(productId);
            OrderItem existing = orderItemByProduct.get(productId);

            if (existing != null) {
                existing.Quantity = qli.Quantity;
                existing.UnitPrice = qli.UnitPrice;
                toUpdate.add(existing);
            } else {
                OrderItem newItem = new OrderItem();
                newItem.OrderId = orderId;
                newItem.Product2Id = qli.Product2Id;
                newItem.PricebookEntryId = qli.PricebookEntryId;
                newItem.Quantity = qli.Quantity;
                newItem.UnitPrice = qli.UnitPrice;
                toInsert.add(newItem);
            }
        }

        for (OrderItem oi : currentOrderItems) {
            if (!quoteLineByProduct.containsKey(oi.Product2Id)) {
                toDeleteIds.add(oi.Id);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
        if (!toDeleteIds.isEmpty()) {
            delete [SELECT Id FROM OrderItem WHERE Id IN :toDeleteIds];
        }
    }


    public class AmendmentPushQueueable implements Queueable, Database.AllowsCallouts {

        private Id orderId;

        public AmendmentPushQueueable(Id orderId) {
            this.orderId = orderId;
        }

        public void execute(QueueableContext ctx) {
            GAMOrderPushService.OrderPushRequest pushRequest = new GAMOrderPushService.OrderPushRequest();
            pushRequest.orderId = orderId;
            GAMOrderPushService.push(new List<GAMOrderPushService.OrderPushRequest>{ pushRequest });
        }
    }
}
