public with sharing class CampaignIntakeService {

    /*
     * ================================================================
     * CAMPAIGN INTAKE / VALIDATION ENGINE
     *
     * Deterministic completeness check for an inbound campaign request
     * Case, regardless of source channel (Web Form, Email, OMS API,
     * Sales Representative).
     *
     * Apex responsibilities:
     *   1. Read the Case.
     *   2. Determine which required fields are missing.
     *   3. Write Validation_Status__c and Missing_Fields__c back to the
     *      Case so downstream automation and the agent both see the
     *      same source of truth.
     *   4. Return a structured result for the Validation Agent to turn
     *      into advertiser-facing communication.
     *
     * Apex does NOT draft or send advertiser communication - that is
     * the agent's/human's responsibility once missing fields are known.
     * ================================================================
     */

    private static final List<String> REQUIRED_FIELD_LABELS =
        new List<String>{
            'Advertiser Name',
            'Requested Budget',
            'Flight Start Date',
            'Flight End Date',
            'Campaign Objective'
        };


    /*
     * ================================================================
     * REQUEST / RESULT
     * ================================================================
     */

    public class IntakeValidationRequest {

        @InvocableVariable(
            label='Case ID'
            required=true
        )
        public String caseId;
    }


    public class IntakeValidationResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Case ID')
        public String caseId;

        @InvocableVariable(label='Validation Status')
        public String validationStatus;

        @InvocableVariable(label='Is Complete')
        public Boolean isComplete;

        @InvocableVariable(label='Missing Fields')
        public String missingFields;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    /*
     * ================================================================
     * INVOCABLE METHOD
     * ================================================================
     */

    @InvocableMethod(
        label='Validate Campaign Request Completeness'
        description='Checks a campaign request Case for required fields, updates Validation Status and Missing Fields, and returns a structured completeness result.'
    )
    public static List<IntakeValidationResult> validate(
        List<IntakeValidationRequest> requests
    ) {

        List<IntakeValidationResult> results =
            new List<IntakeValidationResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        Set<Id> caseIds =
            new Set<Id>();

        for (
            IntakeValidationRequest request :
            requests
        ) {

            if (
                request != null &&
                !String.isBlank(request.caseId)
            ) {

                try {
                    caseIds.add(
                        Id.valueOf(request.caseId)
                    );
                } catch (Exception e) {
                    // invalid id handled per-request below
                }
            }
        }

        Map<Id, Case> casesById =
            new Map<Id, Case>(
                [
                    SELECT
                        Id,
                        Advertiser_Name__c,
                        Requested_Budget__c,
                        Flight_Start_Date__c,
                        Flight_End_Date__c,
                        Campaign_Objective__c,
                        Validation_Status__c,
                        Missing_Fields__c
                    FROM Case
                    WHERE Id IN :caseIds
                ]
            );

        List<Case> casesToUpdate =
            new List<Case>();

        for (
            IntakeValidationRequest request :
            requests
        ) {

            IntakeValidationResult result =
                new IntakeValidationResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.caseId)
                ) {

                    throw new IntakeException(
                        'Case ID is required.'
                    );
                }

                result.caseId =
                    request.caseId;

                Id caseId =
                    Id.valueOf(request.caseId);

                if (
                    !casesById.containsKey(caseId)
                ) {

                    throw new IntakeException(
                        'No campaign request Case was found for ID "' +
                        request.caseId +
                        '".'
                    );
                }

                Case record =
                    casesById.get(caseId);

                List<String> missing =
                    findMissingFields(record);

                Boolean isComplete =
                    missing.isEmpty();

                record.Missing_Fields__c =
                    isComplete
                        ? null
                        : String.join(missing, '; ');

                record.Validation_Status__c =
                    isComplete
                        ? 'Validated'
                        : 'Incomplete';

                casesToUpdate.add(record);

                result.isComplete = isComplete;
                result.missingFields = record.Missing_Fields__c;
                result.validationStatus = record.Validation_Status__c;

                result.explanation =
                    isComplete
                        ? 'All required campaign request fields are present.'
                        : 'The following required fields are missing and must be obtained from the advertiser before this request can proceed: ' +
                          record.Missing_Fields__c +
                          '.';

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.validationStatus = 'Pending';
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        if (
            !casesToUpdate.isEmpty()
        ) {

            update casesToUpdate;
        }

        return results;
    }


    /*
     * ================================================================
     * FIELD COMPLETENESS CHECK
     * ================================================================
     */

    private static List<String> findMissingFields(
        Case record
    ) {

        List<String> missing =
            new List<String>();

        if (
            String.isBlank(record.Advertiser_Name__c)
        ) {
            missing.add(REQUIRED_FIELD_LABELS[0]);
        }

        if (
            record.Requested_Budget__c == null ||
            record.Requested_Budget__c <= 0
        ) {
            missing.add(REQUIRED_FIELD_LABELS[1]);
        }

        if (
            record.Flight_Start_Date__c == null
        ) {
            missing.add(REQUIRED_FIELD_LABELS[2]);
        }

        if (
            record.Flight_End_Date__c == null
        ) {
            missing.add(REQUIRED_FIELD_LABELS[3]);
        }

        if (
            String.isBlank(record.Campaign_Objective__c)
        ) {
            missing.add(REQUIRED_FIELD_LABELS[4]);
        }

        if (
            record.Flight_Start_Date__c != null &&
            record.Flight_End_Date__c != null &&
            record.Flight_Start_Date__c > record.Flight_End_Date__c
        ) {
            missing.add(
                'Flight Start Date must be before Flight End Date'
            );
        }

        return missing;
    }


    /*
     * ================================================================
     * EXCEPTION
     * ================================================================
     */

    public class IntakeException extends Exception {
    }
}
