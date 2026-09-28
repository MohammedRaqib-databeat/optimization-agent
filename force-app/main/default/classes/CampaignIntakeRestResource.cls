@RestResource(urlMapping='/CampaignIntake/*')
global with sharing class CampaignIntakeRestResource {

    /*
     * ================================================================
     * OMS / EXTERNAL API INTAKE ENDPOINT
     *
     * POST /services/apexrest/CampaignIntake
     *
     * Accepts a campaign request from an external OMS or partner
     * system and creates a Campaign Request Case with Source
     * Channel = "OMS API". This is one of three intake channels
     * (Web Form, Email, OMS API) that all normalize into the same
     * Case shape for the Validation Agent to process.
     *
     * This endpoint intentionally does no validation of its own -
     * it only records what was submitted. Completeness checking is
     * CampaignIntakeService's job, run immediately after insert.
     * ================================================================
     */

    global class CampaignIntakeRequestBody {

        public String advertiserName;
        public String advertiserEmail;
        public Decimal requestedBudget;
        public String flightStartDate;
        public String flightEndDate;
        public String campaignObjective;
        public String externalReferenceId;
    }


    global class CampaignIntakeResponseBody {

        public Boolean success;
        public String caseId;
        public String caseNumber;
        public String message;
    }


    @HttpPost
    global static CampaignIntakeResponseBody createCampaignRequest() {

        CampaignIntakeResponseBody response =
            new CampaignIntakeResponseBody();

        response.success = false;

        try {

            RestRequest request =
                RestContext.request;

            if (
                request == null ||
                request.requestBody == null
            ) {

                response.message =
                    'Request body is required.';

                return response;
            }

            CampaignIntakeRequestBody payload =
                (CampaignIntakeRequestBody) JSON.deserialize(
                    request.requestBody.toString(),
                    CampaignIntakeRequestBody.class
                );

            if (
                String.isBlank(payload.advertiserName)
            ) {

                response.message =
                    'advertiserName is required.';

                return response;
            }

            Case newCase =
                new Case();

            newCase.RecordTypeId =
                campaignRequestRecordTypeId();

            newCase.Subject =
                'Campaign Request - ' +
                payload.advertiserName;

            newCase.Origin =
                'OMS API';

            newCase.Source_Channel__c =
                'OMS API';

            newCase.Advertiser_Name__c =
                payload.advertiserName;

            newCase.SuppliedEmail =
                payload.advertiserEmail;

            newCase.Requested_Budget__c =
                payload.requestedBudget;

            newCase.Flight_Start_Date__c =
                parseDate(payload.flightStartDate);

            newCase.Flight_End_Date__c =
                parseDate(payload.flightEndDate);

            newCase.Campaign_Objective__c =
                payload.campaignObjective;

            newCase.Validation_Status__c =
                'Pending';

            if (
                !String.isBlank(payload.externalReferenceId)
            ) {

                newCase.Description =
                    'External OMS Reference: ' +
                    payload.externalReferenceId;
            }

            insert newCase;

            List<CampaignIntakeService.IntakeValidationRequest> validationRequests =
                new List<CampaignIntakeService.IntakeValidationRequest>();

            CampaignIntakeService.IntakeValidationRequest validationRequest =
                new CampaignIntakeService.IntakeValidationRequest();

            validationRequest.caseId =
                newCase.Id;

            validationRequests.add(validationRequest);

            CampaignIntakeService.validate(validationRequests);

            Case insertedCase =
                [
                    SELECT Id, CaseNumber
                    FROM Case
                    WHERE Id = :newCase.Id
                ];

            response.success = true;
            response.caseId = insertedCase.Id;
            response.caseNumber = insertedCase.CaseNumber;
            response.message = 'Campaign request received.';

        } catch (Exception e) {

            response.success = false;
            response.message =
                'Unable to process campaign request: ' +
                e.getMessage();
        }

        return response;
    }


    private static Id campaignRequestRecordTypeId() {

        return
            Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
                .get('Campaign_Request')
                .getRecordTypeId();
    }


    private static Date parseDate(
        String value
    ) {

        if (String.isBlank(value)) {
            return null;
        }

        try {

            return Date.valueOf(value.trim());

        } catch (Exception e) {

            return null;
        }
    }
}
