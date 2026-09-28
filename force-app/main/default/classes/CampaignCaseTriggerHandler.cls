public with sharing class CampaignCaseTriggerHandler {

    /*
     * ================================================================
     * AUTO-VALIDATION ON CASE SAVE
     * ================================================================
     *
     * Closes a real gap: CampaignIntakeService.validate() previously
     * only ran when a Case came in through the OMS API endpoint
     * (CampaignIntakeRestResource calls it directly in Apex). A Case
     * created any other way - manually, or a future Web-to-Case/
     * Email-to-Case channel - never got validated at all.
     *
     * This trigger handler calls the same, unmodified
     * CampaignIntakeService.validate() invocable method automatically
     * whenever a Campaign Request Case is inserted, or updated while
     * still Pending/Incomplete (so editing a Case to fill in a missing
     * field re-checks completeness). No validation logic lives here -
     * this only decides WHEN to call the existing validator.
     *
     * It also then calls the existing, unmodified
     * CampaignIdentityResolutionService.resolve() the moment a Case's
     * Validation_Status__c actually transitions to "Validated" (which
     * happens via validate()'s own UPDATE DML, re-firing this trigger
     * - that transition, old status != Validated / new status ==
     * Validated, is exactly the signal used here, so there is no
     * separate recursion guard needed beyond that transition check).
     * ================================================================
     */

    private static Id campaignRequestRecordTypeId;

    private static Id getCampaignRequestRecordTypeId() {
        if (campaignRequestRecordTypeId == null) {
            Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Case
                .getRecordTypeInfosByDeveloperName()
                .get('Campaign_Request');

            campaignRequestRecordTypeId = rtInfo != null ? rtInfo.getRecordTypeId() : null;
        }
        return campaignRequestRecordTypeId;
    }

    private static final Set<String> STATUSES_ELIGIBLE_FOR_VALIDATION =
        new Set<String>{ 'Pending', 'Incomplete' };

    private static final Set<String> WATCHED_FIELDS_FOR_REVALIDATION =
        new Set<String>{
            'Advertiser_Name__c',
            'Requested_Budget__c',
            'Flight_Start_Date__c',
            'Flight_End_Date__c',
            'Campaign_Objective__c'
        };

    public static void handleAfterSave(
        List<Case> newCases,
        Map<Id, Case> oldCasesById
    ) {

        Id campaignRequestRtId = getCampaignRequestRecordTypeId();

        if (campaignRequestRtId == null) {
            return;
        }

        List<CampaignIntakeService.IntakeValidationRequest> requestsToValidate =
            new List<CampaignIntakeService.IntakeValidationRequest>();

        for (Case newCase : newCases) {

            if (newCase.RecordTypeId != campaignRequestRtId) {
                continue;
            }

            if (!STATUSES_ELIGIBLE_FOR_VALIDATION.contains(newCase.Validation_Status__c)) {
                continue;
            }

            Boolean isNewInsert = (oldCasesById == null);

            if (!isNewInsert) {
                Case oldCase = oldCasesById.get(newCase.Id);
                if (!relevantFieldChanged(newCase, oldCase)) {
                    continue;
                }
            }

            CampaignIntakeService.IntakeValidationRequest request =
                new CampaignIntakeService.IntakeValidationRequest();
            request.caseId = newCase.Id;
            requestsToValidate.add(request);
        }

        if (!requestsToValidate.isEmpty()) {
            CampaignIntakeService.validate(requestsToValidate);
        }

        handleIdentityResolution(newCases, oldCasesById, campaignRequestRtId);
    }

    private static void handleIdentityResolution(
        List<Case> newCases,
        Map<Id, Case> oldCasesById,
        Id campaignRequestRtId
    ) {

        if (oldCasesById == null) {
            return;
        }

        List<CampaignIdentityResolutionService.IdentityResolutionRequest> requestsToResolve =
            new List<CampaignIdentityResolutionService.IdentityResolutionRequest>();

        for (Case newCase : newCases) {

            if (newCase.RecordTypeId != campaignRequestRtId) {
                continue;
            }

            if (newCase.Validation_Status__c != 'Validated') {
                continue;
            }

            Case oldCase = oldCasesById.get(newCase.Id);

            Boolean justBecameValidated =
                oldCase != null && oldCase.Validation_Status__c != 'Validated';

            if (!justBecameValidated) {
                continue;
            }

            if (!String.isBlank(newCase.Related_Opportunity__c)) {
                continue;
            }

            CampaignIdentityResolutionService.IdentityResolutionRequest request =
                new CampaignIdentityResolutionService.IdentityResolutionRequest();
            request.caseId = newCase.Id;
            requestsToResolve.add(request);
        }

        if (!requestsToResolve.isEmpty()) {
            CampaignIdentityResolutionService.resolve(requestsToResolve);
        }
    }

    private static Boolean relevantFieldChanged(Case newCase, Case oldCase) {

        if (oldCase == null) {
            return true;
        }

        for (String fieldName : WATCHED_FIELDS_FOR_REVALIDATION) {
            if (newCase.get(fieldName) != oldCase.get(fieldName)) {
                return true;
            }
        }

        return false;
    }
}
