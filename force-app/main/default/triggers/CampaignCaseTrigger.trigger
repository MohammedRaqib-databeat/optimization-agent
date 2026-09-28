trigger CampaignCaseTrigger on Case (after insert, after update) {

    CampaignCaseTriggerHandler.handleAfterSave(
        Trigger.new,
        Trigger.isUpdate ? Trigger.oldMap : null
    );
}
