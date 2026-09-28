public with sharing class OptimizationSchedulerJob implements Schedulable {

    /*
     * ================================================================
     * SCHEDULER-DRIVEN OPTIMIZATION (non-conversational path)
     * ================================================================
     *
     * Runs independently of any Agentforce chat session. For every
     * active line item, this:
     *   1. Pulls the same evidence CampaignOptimizationService already
     *      computes for the chat-driven flow (reused, not duplicated).
     *   2. Runs it through OptimizationDecisionEngine for a
     *      deterministic yes/no/what decision.
     *   3. If a change is warranted, creates a single
     *      a Case with Optimization_Action_Type__c populated (deduped - one open request
     *      per line item at a time) for a human to approve.
     *   4. Writes a Case-based audit log entry every run,
     *      whether or not action was needed, so there is a complete
     *      audit trail of what was evaluated and when.
     *
     * Implemented as Schedulable -> Batchable (not one synchronous
     * loop): evaluating every active line item's full evidence
     * package is real CPU work, and a plain synchronous pass over all
     * of them can exceed governor limits as the number of line items
     * grows. Batch Apex processes them in scoped chunks instead.
     *
     * HONEST LIMITATION: this project's delivery/pacing data is
     * CSV-backed via Salesforce Files (see PROJECT_HANDOFF.md), not a
     * live ad-server sync - there is no real "stats sync completed"
     * platform event to hook into yet. This scheduled job is a
     * time-based proxy for that trigger (e.g. scheduled hourly/daily)
     * until a genuine sync-completion event exists to fire it instead.
     * ================================================================
     */

    /*
     * Scope size of 1: CampaignOptimizationService.optimize() is a
     * genuinely expensive call (~10s CPU per line item, measured
     * directly - already close to the synchronous governor limit on
     * its own), so each batch chunk processes exactly one line item
     * to stay safely under Batch Apex's per-execute limits.
     */
    private static final Integer BATCH_SCOPE_SIZE = 1;

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new OptimizationEvaluationBatch(), BATCH_SCOPE_SIZE);
    }

    /*
     * Convenience method to schedule this job - run once from
     * Execute Anonymous (or a Setup > Scheduled Jobs entry) to turn
     * on the automation:
     *
     *   OptimizationSchedulerJob.scheduleHourly();
     */
    public static String scheduleHourly() {
        return System.schedule(
            'Optimization Agent - Hourly Evaluation',
            '0 0 * * * ?',
            new OptimizationSchedulerJob()
        );
    }

    /*
     * Also exposed directly so it can be run on demand (e.g. a "Run
     * Now" button, or a quick manual test) without waiting for the
     * schedule to fire.
     */
    public static Id runNow() {
        return Database.executeBatch(new OptimizationEvaluationBatch(), BATCH_SCOPE_SIZE);
    }
}
