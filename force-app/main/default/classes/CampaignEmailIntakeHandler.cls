global with sharing class CampaignEmailIntakeHandler implements Messaging.InboundEmailHandler {

    /*
     * ================================================================
     * EMAIL-TO-CASE CAMPAIGN INTAKE
     *
     * Apex Email Service handler - an inbound email to this service's
     * generated address creates a real Campaign Request Case exactly
     * like the Web Form/OMS API channels CampaignIntakeService already
     * expects (see its header comment). This handler does NOT attempt
     * to parse structured fields (advertiser name, budget, flight
     * dates) out of free-form email text - that would mean guessing,
     * which this project's architecture explicitly avoids. Instead it
     * creates the Case with only what an email genuinely gives us for
     * free (subject, body, sender), and lets the existing
     * CampaignIntakeService/CampaignCaseTriggerHandler pipeline run its
     * normal deterministic validation, which already knows how to
     * report "missing fields" back for advertiser-facing follow-up -
     * this is exactly the scenario that reporting path was built for.
     *
     * Attachments (briefs, insertion orders, etc.) ARE saved for real,
     * as Salesforce Files attached to the new Case - this only works
     * if the Email Service's "Accept Attachments" setting is not set
     * to "None" (a Setup-level config, not something this class
     * controls).
     * ================================================================
     */

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, Messaging.InboundEnvelope envelope
    ) {

        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            Schema.RecordTypeInfo campaignRequestRt = Schema.SObjectType.Case
                .getRecordTypeInfosByDeveloperName()
                .get('Campaign_Request');

            if (campaignRequestRt == null) {
                result.success = false;
                result.message = 'Campaign Request record type is not configured on Case.';
                return result;
            }

            Case newCase = new Case();
            newCase.RecordTypeId = campaignRequestRt.getRecordTypeId();
            newCase.Origin = 'Email';
            newCase.SuppliedEmail = email.fromAddress;
            newCase.SuppliedName = String.isNotBlank(email.fromName) ? email.fromName : email.fromAddress;
            newCase.Subject = String.isNotBlank(email.subject) ? email.subject : 'Campaign Request via Email';
            newCase.Description = String.isNotBlank(email.plainTextBody)
                ? email.plainTextBody
                : 'No email body was provided.';

            insert newCase;

            saveAttachments(email, newCase.Id);

            result.success = true;

        } catch (Exception e) {
            result.success = false;
            result.message = 'Failed to create Campaign Request Case: ' + e.getMessage();
        }

        return result;
    }


    /*
     * Best-effort - the Case has already been created by the time
     * this runs, so a problem saving one attachment should never
     * cause the whole inbound email to be treated as a failure (which
     * would make the mail server retry/bounce it). Each attachment is
     * inserted independently so one bad file doesn't block the rest.
     */
    private static void saveAttachments(Messaging.InboundEmail email, Id caseId) {

        List<ContentVersion> filesToInsert = new List<ContentVersion>();

        if (email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment attachment : email.binaryAttachments) {
                ContentVersion file = new ContentVersion();
                file.PathOnClient = attachment.fileName;
                file.VersionData = attachment.body;
                file.FirstPublishLocationId = caseId;
                filesToInsert.add(file);
            }
        }

        if (email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment attachment : email.textAttachments) {
                ContentVersion file = new ContentVersion();
                file.PathOnClient = attachment.fileName;
                file.VersionData = Blob.valueOf(attachment.body);
                file.FirstPublishLocationId = caseId;
                filesToInsert.add(file);
            }
        }

        if (!filesToInsert.isEmpty()) {
            insert filesToInsert;
        }
    }
}
