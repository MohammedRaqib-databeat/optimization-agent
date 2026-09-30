public with sharing class OptimizationEvaluationBatch implements Database.Batchable<String>, Database.Stateful {

    /*
     * ================================================================
     * Batch worker behind OptimizationSchedulerJob. Iterates distinct
     * line item IDs (from the CSV-backed CampaignDataProvider) in
     * scoped chunks, so evaluating a large number of line items never
     * risks the CPU/heap limits a single synchronous pass would hit.
     *
     * Audit log entries and change requests are both stored as Case
     * records (default/Master record type - never the "Campaign
     * Request" record type, so CampaignCaseTriggerHandler's intake
     * logic never fires for these) instead of dedicated custom
     * objects, per the project's "zero new custom objects" rule.
     * A Case with Optimization_Event_Type__c populated is a log
     * entry; a Case with Optimization_Action_Type__c populated is a
     * change request needing human approval (Status =
     * 'Pending Approval').
     * ================================================================
     */

    private Map<String, CampaignDataProvider.CampaignDay> latestDayByLineItem;
    private Set<String> lineItemsWithOpenRequests;

    public Iterable<String> start(Database.BatchableContext bc) {

        List<CampaignDataProvider.CampaignDay> allDays =
            CampaignDataProvider.getAllLineItemData();

        latestDayByLineItem = new Map<String, CampaignDataProvider.CampaignDay>();

        for (CampaignDataProvider.CampaignDay day : allDays) {
            CampaignDataProvider.CampaignDay existing =
                latestDayByLineItem.get(day.lineItemId);

            if (existing == null || day.reportDate > existing.reportDate) {
                latestDayByLineItem.put(day.lineItemId, day);
            }
        }

        lineItemsWithOpenRequests = new Set<String>();
        for (Case existingRequest : [
            SELECT Optimization_Line_Item_Id__c
            FROM Case
            WHERE Optimization_Action_Type__c != null
            AND Status = 'Pending Approval'
        ]) {
            lineItemsWithOpenRequests.add(existingRequest.Optimization_Line_Item_Id__c);
        }

        return latestDayByLineItem.keySet();
    }

    public void execute(Database.BatchableContext bc, List<String> lineItemIds) {

        List<Case> logsToInsert = new List<Case>();
        List<Case> requestsToInsert = new List<Case>();

        for (String lineItemId : lineItemIds) {

            CampaignDataProvider.CampaignDay latestDay = latestDayByLineItem.get(lineItemId);
            if (latestDay == null) {
                continue;
            }

            CampaignOptimizationService.OptimizationRequest req =
                new CampaignOptimizationService.OptimizationRequest();
            req.lineItemId = lineItemId;

            List<CampaignOptimizationService.OptimizationResult> results =
                CampaignOptimizationService.optimize(new List<CampaignOptimizationService.OptimizationRequest>{ req });

            if (results.isEmpty() || !results[0].success) {
                continue;
            }

            CampaignOptimizationService.OptimizationResult evidenceResult = results[0];

            OptimizationDecisionEngine.Decision decision = OptimizationDecisionEngine.decide(
                latestDay.pacingPercentage,
                evidenceResult.optimizationHealth,
                evidenceResult.optimizationUrgency
            );

            Case logEntry = new Case();
            logEntry.Subject = 'Optimization Log: SCHEDULED_EVALUATION - ' + lineItemId;
            logEntry.Optimization_Line_Item_Id__c = lineItemId;
            logEntry.Optimization_Advertiser__c = latestDay.advertiser;
            logEntry.Optimization_Event_Type__c = 'SCHEDULED_EVALUATION';
            logEntry.Description = '[Actor: Scheduled Job] ' + decision.reasoning;
            logEntry.Status = 'Closed';
            logsToInsert.add(logEntry);

            if (decision.requiresChangeRequest && !lineItemsWithOpenRequests.contains(lineItemId)) {

                Case changeRequest = new Case();
                changeRequest.Subject = 'Optimization Change Request: ' + decision.actionType + ' - ' + latestDay.advertiser;
                changeRequest.Optimization_Line_Item_Id__c = lineItemId;
                changeRequest.Optimization_Advertiser__c = latestDay.advertiser;
                changeRequest.Optimization_Action_Type__c = decision.actionType;
                changeRequest.Status = 'Pending Approval';
                changeRequest.Optimization_Current_Pacing_Percentage__c = latestDay.pacingPercentage;
                changeRequest.Optimization_Pacing_Adjustment_Pct__c = decision.pacingAdjustmentPercent;
                changeRequest.Optimization_Health__c = evidenceResult.optimizationHealth;
                changeRequest.Description = decision.reasoning;
                requestsToInsert.add(changeRequest);

                lineItemsWithOpenRequests.add(lineItemId);
            }
        }

        if (!requestsToInsert.isEmpty()) {
            insert requestsToInsert;

            for (Case changeRequest : requestsToInsert) {
                Case requestLog = new Case();
                requestLog.Subject = 'Optimization Log: CHANGE_REQUEST_CREATED - ' + changeRequest.Optimization_Line_Item_Id__c;
                requestLog.Optimization_Line_Item_Id__c = changeRequest.Optimization_Line_Item_Id__c;
                requestLog.Optimization_Advertiser__c = changeRequest.Optimization_Advertiser__c;
                requestLog.Optimization_Event_Type__c = 'CHANGE_REQUEST_CREATED';
                requestLog.Description = '[Actor: Scheduled Job] Created ' + changeRequest.Optimization_Action_Type__c +
                    ' request: ' + changeRequest.Description;
                requestLog.Status = 'Closed';
                logsToInsert.add(requestLog);
            }
        }

        if (!logsToInsert.isEmpty()) {
            insert logsToInsert;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Nothing further needed - each chunk commits its own logs/requests.
    }
}
