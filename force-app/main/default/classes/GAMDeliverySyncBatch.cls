public with sharing class GAMDeliverySyncBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {

    /*
     * ================================================================
     * Two-way sync: pulls real delivery stats (impressions, clicks,
     * status) from Google Ad Manager back onto the AdOrderItem records
     * that GAMOrderPushService already pushed there. Read-only against
     * GAM - never writes anything back to the ad server. Complements
     * the one-way push built earlier this session.
     *
     * Batches multiple AdOrderItems into a single PQL "WHERE id IN
     * (...)" query per GAM LineItemService callout instead of one
     * callout per record, since GAM Line Item IDs are the join key
     * and PQL supports IN lists directly - keeps this well under both
     * the batch's own scope size and the 100-callout governor limit.
     * ================================================================
     */

    private static final String GAM_NAMED_CREDENTIAL = 'callout:GAM_API/';
    private static final String APPLICATION_NAME = 'Salesforce Media Cloud Optimization Agent';
    private static final Integer BATCH_SCOPE_SIZE = 25;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, AdServerOrderLineIdentifier
            FROM AdOrderItem
            WHERE AdServerOrderLineIdentifier != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<AdOrderItem> scope) {

        GAM_Config__c config = GAM_Config__c.getOrgDefaults();
        if (config == null || String.isBlank(config.Network_Code__c)) {
            return;
        }

        Map<String, AdOrderItem> aoiByGamLineItemId = new Map<String, AdOrderItem>();
        for (AdOrderItem aoi : scope) {
            aoiByGamLineItemId.put(aoi.AdServerOrderLineIdentifier, aoi);
        }

        if (aoiByGamLineItemId.isEmpty()) {
            return;
        }

        List<GAMLineItemServiceStub.LineItem> gamLineItems = getLineItemsByIds(
            aoiByGamLineItemId.keySet(), config.Network_Code__c
        );

        List<AdOrderItem> toUpdate = new List<AdOrderItem>();
        Datetime syncedAt = Datetime.now();

        for (GAMLineItemServiceStub.LineItem li : gamLineItems) {

            AdOrderItem aoi = aoiByGamLineItemId.get(String.valueOf(li.id));
            if (aoi == null) {
                continue;
            }

            aoi.GAM_Delivered_Impressions__c = li.stats != null && li.stats.impressionsDelivered != null
                ? li.stats.impressionsDelivered : 0;
            aoi.GAM_Delivered_Clicks__c = li.stats != null && li.stats.clicksDelivered != null
                ? li.stats.clicksDelivered : 0;
            aoi.GAM_Delivery_Status__c = li.status;
            aoi.GAM_Last_Synced__c = syncedAt;

            toUpdate.add(aoi);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Nothing further needed - each chunk commits its own updates.
    }


    private static List<GAMLineItemServiceStub.LineItem> getLineItemsByIds(Set<String> gamLineItemIds, String networkCode) {

        GAMLineItemServiceStub.LineItemServiceInterfacePort port =
            new GAMLineItemServiceStub.LineItemServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'LineItemService';

        GAMLineItemServiceStub.SoapRequestHeader header = new GAMLineItemServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        port.RequestHeader = header;

        GAMLineItemServiceStub.Statement statement = new GAMLineItemServiceStub.Statement();
        statement.query = 'WHERE id IN (' + String.join(new List<String>(gamLineItemIds), ',') + ')';

        GAMLineItemServiceStub.LineItemPage page = port.getLineItemsByStatement(statement);

        return page != null && page.results != null
            ? page.results
            : new List<GAMLineItemServiceStub.LineItem>();
    }
}
