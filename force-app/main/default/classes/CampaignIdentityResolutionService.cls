public with sharing class CampaignIdentityResolutionService {

    /*
     * ================================================================
     * IDENTITY RESOLUTION & OPPORTUNITY CREATION ENGINE
     *
     * Standard-object-only implementation of the diagram's
     * "Case -> Lead / Account / Contact -> Opportunity" step.
     *
     * No custom objects are used. Only standard Lead, Account,
     * Contact, and Opportunity objects, plus one custom lookup field
     * (Lead.Related_Case__c) for traceability back to the intake Case.
     *
     * Logic:
     *   1. Try to match the advertiser to an existing Account by name.
     *   2. If matched: attach the Case to that Account/Contact and
     *      create the Opportunity directly under it.
     *   3. If not matched: create a Lead, convert it immediately via
     *      the standard Database.LeadConvert API (Account + Contact +
     *      Opportunity), and attach the Case to the results.
     *
     * This runs only on a Case whose Validation_Status__c is already
     * "Validated" - identity resolution should not run on an
     * incomplete request.
     * ================================================================
     */


    public class IdentityResolutionRequest {

        @InvocableVariable(
            label='Case ID'
            required=true
        )
        public String caseId;
    }


    public class IdentityResolutionResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Case ID')
        public String caseId;

        @InvocableVariable(label='Resolution Path')
        public String resolutionPath;

        @InvocableVariable(label='Account ID')
        public String accountId;

        @InvocableVariable(label='Contact ID')
        public String contactId;

        @InvocableVariable(label='Opportunity ID')
        public String opportunityId;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Resolve Advertiser Identity and Create Opportunity'
        description='Matches a validated campaign request Case to an existing Account or creates a new Lead/Account/Contact via standard Lead conversion, then creates the Opportunity - using only standard Salesforce objects.'
    )
    public static List<IdentityResolutionResult> resolve(
        List<IdentityResolutionRequest> requests
    ) {

        List<IdentityResolutionResult> results =
            new List<IdentityResolutionResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        for (
            IdentityResolutionRequest request :
            requests
        ) {

            IdentityResolutionResult result =
                new IdentityResolutionResult();

            result.success = false;

            try {

                if (
                    request == null ||
                    String.isBlank(request.caseId)
                ) {

                    throw new IdentityResolutionException(
                        'Case ID is required.'
                    );
                }

                result.caseId = request.caseId;

                Case record =
                    [
                        SELECT
                            Id,
                            Advertiser_Name__c,
                            SuppliedName,
                            SuppliedEmail,
                            Requested_Budget__c,
                            Flight_Start_Date__c,
                            Flight_End_Date__c,
                            Validation_Status__c,
                            AccountId,
                            ContactId,
                            Related_Opportunity__c
                        FROM Case
                        WHERE Id = :Id.valueOf(request.caseId)
                        LIMIT 1
                    ];

                if (
                    record.Validation_Status__c != 'Validated'
                ) {

                    throw new IdentityResolutionException(
                        'Identity resolution requires a Validated campaign request. Current status: ' +
                        record.Validation_Status__c +
                        '.'
                    );
                }

                if (
                    !String.isBlank(record.Related_Opportunity__c)
                ) {

                    throw new IdentityResolutionException(
                        'This Case is already linked to an Opportunity.'
                    );
                }

                resolveAndCreateOpportunity(
                    record,
                    result
                );

                update record;

                result.success = true;

            } catch (Exception e) {

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    private static void resolveAndCreateOpportunity(
        Case record,
        IdentityResolutionResult result
    ) {

        List<Account> matches =
            [
                SELECT Id
                FROM Account
                WHERE Name = :record.Advertiser_Name__c
                LIMIT 1
            ];

        if (
            !matches.isEmpty()
        ) {

            Account matchedAccount =
                matches[0];

            Contact matchedContact =
                findContactByEmail(
                    matchedAccount.Id,
                    record.SuppliedEmail
                );

            Opportunity opportunity =
                buildOpportunity(
                    record,
                    matchedAccount.Id
                );

            insert opportunity;

            record.AccountId = matchedAccount.Id;
            record.ContactId =
                matchedContact != null
                    ? matchedContact.Id
                    : null;
            record.Related_Opportunity__c = opportunity.Id;

            result.resolutionPath = 'MATCHED_EXISTING_ACCOUNT';
            result.accountId = matchedAccount.Id;
            result.contactId = record.ContactId;
            result.opportunityId = opportunity.Id;
            result.explanation =
                'Advertiser matched an existing Account by name. Opportunity created under the existing Account.';

            return;
        }

        Lead newLead =
            new Lead();

        newLead.Company = record.Advertiser_Name__c;
        newLead.LastName =
            String.isBlank(record.SuppliedName)
                ? 'Unknown'
                : record.SuppliedName;
        newLead.Email = record.SuppliedEmail;
        newLead.LeadSource = 'Campaign Request';
        newLead.Related_Case__c = record.Id;

        insert newLead;

        Database.LeadConvert convert =
            new Database.LeadConvert();

        convert.setLeadId(newLead.Id);
        convert.setDoNotCreateOpportunity(true);
        convert.setConvertedStatus(
            leadConvertedStatus()
        );

        Database.LeadConvertResult convertResult =
            Database.convertLead(convert);

        if (
            !convertResult.isSuccess()
        ) {

            throw new IdentityResolutionException(
                'Lead conversion failed: ' +
                String.join(
                    convertResult.getErrors(),
                    '; '
                )
            );
        }

        Opportunity opportunity =
            buildOpportunity(
                record,
                convertResult.getAccountId()
            );

        opportunity.ContactId = convertResult.getContactId();

        insert opportunity;

        record.AccountId = convertResult.getAccountId();
        record.ContactId = convertResult.getContactId();
        record.Related_Opportunity__c = opportunity.Id;

        result.resolutionPath = 'CREATED_NEW_LEAD_CONVERTED';
        result.accountId = convertResult.getAccountId();
        result.contactId = convertResult.getContactId();
        result.opportunityId = opportunity.Id;
        result.explanation =
            'No existing Account matched. A new Lead was created and converted via the standard Salesforce Lead Convert API into an Account, Contact, and Opportunity.';
    }


    private static Opportunity buildOpportunity(
        Case record,
        Id accountId
    ) {

        Opportunity opportunity =
            new Opportunity();

        opportunity.Name =
            record.Advertiser_Name__c +
            ' - Campaign Request';

        opportunity.AccountId = accountId;

        opportunity.StageName =
            defaultOpportunityStage();

        opportunity.CloseDate =
            record.Flight_End_Date__c != null
                ? record.Flight_End_Date__c
                : Date.today().addDays(30);

        opportunity.Amount = record.Requested_Budget__c;

        return opportunity;
    }


    private static Contact findContactByEmail(
        Id accountId,
        String email
    ) {

        if (
            String.isBlank(email)
        ) {
            return null;
        }

        List<Contact> matches =
            [
                SELECT Id
                FROM Contact
                WHERE
                    AccountId = :accountId
                    AND Email = :email
                LIMIT 1
            ];

        return
            matches.isEmpty()
                ? null
                : matches[0];
    }


    /*
     * ================================================================
     * PICKLIST DEFAULTS
     *
     * Resolved dynamically from the org's own picklist metadata rather
     * than hardcoded, so this works regardless of which default stage
     * or lead-status values a given org has configured.
     * ================================================================
     */

    private static String defaultOpportunityStage() {

        for (
            Schema.PicklistEntry entry :
            Opportunity.StageName.getDescribe().getPicklistValues()
        ) {

            if (
                entry.isDefaultValue()
            ) {
                return entry.getValue();
            }
        }

        for (
            Schema.PicklistEntry entry :
            Opportunity.StageName.getDescribe().getPicklistValues()
        ) {

            if (
                entry.isActive()
            ) {
                return entry.getValue();
            }
        }

        throw new IdentityResolutionException(
            'No active Opportunity Stage values are configured in this org.'
        );
    }


    private static String leadConvertedStatus() {

        for (
            Schema.PicklistEntry entry :
            Lead.Status.getDescribe().getPicklistValues()
        ) {

            if (
                entry.isActive() &&
                entry.getValue().toLowerCase().contains('convert')
            ) {
                return entry.getValue();
            }
        }

        LeadStatus convertedStatus =
            [
                SELECT MasterLabel
                FROM LeadStatus
                WHERE IsConverted = true
                LIMIT 1
            ];

        return convertedStatus.MasterLabel;
    }


    public class IdentityResolutionException extends Exception {
    }
}
