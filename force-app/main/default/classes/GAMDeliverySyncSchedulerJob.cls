public with sharing class GAMDeliverySyncSchedulerJob implements Schedulable {

    /*
     * ================================================================
     * Scheduled two-way sync: pulls real delivery stats back from
     * Google Ad Manager onto every AdOrderItem that has actually been
     * pushed (see GAMDeliverySyncBatch). Deliberately kept separate
     * from OptimizationSchedulerJob/OptimizationEvaluationBatch - the
     * Optimization Agent's own evidence pipeline stays CSV-backed via
     * CampaignDataProvider exactly as it already is (per this
     * project's standing instruction to never disturb that working
     * pipeline). This job only keeps AdOrderItem's own GAM_* fields
     * current for whichever Orders have real GAM Line Items; it does
     * not feed into Forecast/Optimization at all.
     * ================================================================
     */

    private static final Integer BATCH_SCOPE_SIZE = 25;

    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new GAMDeliverySyncBatch(), BATCH_SCOPE_SIZE);
    }

    /*
     * Run once from Execute Anonymous (or Setup > Scheduled Jobs) to
     * turn on the automation:
     *
     *   GAMDeliverySyncSchedulerJob.scheduleHourly();
     */
    public static String scheduleHourly() {
        return System.schedule(
            'GAM Delivery Sync - Hourly',
            '0 15 * * * ?',
            new GAMDeliverySyncSchedulerJob()
        );
    }

    /*
     * Also exposed directly for on-demand runs without waiting for
     * the schedule to fire.
     */
    public static Id runNow() {
        return Database.executeBatch(new GAMDeliverySyncBatch(), BATCH_SCOPE_SIZE);
    }
}
