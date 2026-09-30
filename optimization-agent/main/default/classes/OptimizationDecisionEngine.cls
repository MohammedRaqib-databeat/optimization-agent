public with sharing class OptimizationDecisionEngine {

    /*
     * ================================================================
     * DETERMINISTIC DECISION LOGIC (non-LLM)
     * ================================================================
     *
     * This is separate, by design, from CampaignOptimizationService's
     * chat-facing evidence engine. That engine deliberately leaves
     * `optimizationHealth`/`recommendedAction` for Atlas to reason
     * over during a conversation. This class exists for the
     * scheduler-driven path, where there is no conversation and no
     * LLM in the loop - a real decision has to be made by code alone,
     * using only configurable thresholds (Optimization_Threshold__mdt),
     * never hardcoded literals or invented values.
     *
     * It never touches Salesforce/ad-server data itself - it only
     * decides WHAT should happen. Applying the change (via the Order
     * Push Connector) only happens after a human approves the
     * resulting Case-based change request record.
     * ================================================================
     */

    public class Decision {
        public String actionType;      // matches Case.Optimization_Action_Type__c picklist
        public Decimal pacingAdjustmentPercent;
        public String reasoning;
        public Boolean requiresChangeRequest;
    }

    private static Optimization_Threshold__mdt cachedThresholds;

    public static Optimization_Threshold__mdt getThresholds() {
        if (cachedThresholds == null) {
            cachedThresholds = Optimization_Threshold__mdt.getInstance('Default');
        }
        return cachedThresholds;
    }

    /*
     * latestPacingPercentage: the most recent day's pacingPercentage
     * from CampaignDataProvider.CampaignDay for this line item.
     * optimizationHealth/optimizationUrgency: from
     * CampaignOptimizationService's deterministic health classification
     * (see calculateOptimizationHealth) - reused here rather than
     * duplicated, since that logic already reads the same thresholds.
     */
    public static Decision decide(
        Decimal latestPacingPercentage,
        String optimizationHealth,
        String optimizationUrgency
    ) {
        Optimization_Threshold__mdt thresholds = getThresholds();
        Decision result = new Decision();

        if (latestPacingPercentage == null) {
            result.actionType = 'NO_ACTION';
            result.requiresChangeRequest = false;
            result.reasoning = 'No recent pacing data available for this line item; skipped.';
            return result;
        }

        if (latestPacingPercentage < thresholds.Pacing_At_Risk_Below_Percent__c) {

            result.actionType = 'INCREASE_DAILY_PACING';
            result.requiresChangeRequest = true;
            result.pacingAdjustmentPercent =
                (thresholds.Pacing_Healthy_At_Or_Above_Percent__c - latestPacingPercentage)
                    .setScale(2);
            result.reasoning = 'Pacing (' + latestPacingPercentage.setScale(1) + '%) is below the At Risk threshold ('
                + thresholds.Pacing_At_Risk_Below_Percent__c.setScale(1) + '%). Optimization Health: '
                + optimizationHealth + ' / Urgency: ' + optimizationUrgency
                + '. Proposing a daily pacing increase of ' + result.pacingAdjustmentPercent.setScale(1)
                + ' percentage points to close the gap to the healthy pacing threshold.';

        } else if (latestPacingPercentage >= thresholds.Pacing_Healthy_At_Or_Above_Percent__c
            && optimizationHealth == 'At Risk') {

            result.actionType = 'REVIEW_TARGETING';
            result.requiresChangeRequest = true;
            result.reasoning = 'Pacing is healthy (' + latestPacingPercentage.setScale(1)
                + '%) but the line item is still classified At Risk on benchmark signals. '
                + 'Pacing is not the bottleneck here, so a pacing change is not proposed - flagging for manual targeting review instead.';

        } else {

            result.actionType = 'NO_ACTION';
            result.requiresChangeRequest = false;
            result.reasoning = 'Pacing (' + latestPacingPercentage.setScale(1)
                + '%) and Optimization Health (' + optimizationHealth + ') are both within normal range. No change proposed.';
        }

        return result;
    }
}
