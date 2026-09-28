public with sharing class GAMOrderDeleteService {

    /*
     * ================================================================
     * ORDER DELETE / CLEANUP (real GAM Order -> permanently removed)
     * ================================================================
     *
     * Companion to GAMOrderPushService - lets a pushed test/mistaken
     * Order be permanently removed from Google Ad Manager again,
     * using the GAM Order ID already recorded on this Order's
     * AdOrderItem records by the push.
     *
     * Human-in-the-loop: this is a real, live, IRREVERSIBLE change to
     * an external ad server. It must only run after explicit human
     * confirmation (isConfirmationRequired = true on its Agentforce
     * action), exactly like every other write path in this project.
     *
     * Kept as its own class (not a second method on
     * GAMOrderPushService) because Apex only allows one
     * @InvocableMethod per class.
     * ================================================================
     */

    private static final String GAM_NAMED_CREDENTIAL = 'callout:GAM_API/';
    private static final String APPLICATION_NAME = 'Salesforce Media Cloud Optimization Agent';


    public class OrderDeleteRequest {
        @InvocableVariable(label='Order ID' required=true)
        public String orderId;
    }

    public class OrderDeleteResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Order ID')
        public String orderId;

        @InvocableVariable(label='GAM Order ID')
        public String gamOrderId;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }

    public class OrderDeleteException extends Exception {}


    @InvocableMethod(
        label='Delete Order From Google Ad Manager'
        description='Permanently deletes a previously-pushed Order (and its Line Items) from Google Ad Manager, using the GAM Order ID already recorded on this Order\'s AdOrderItem records. This is a real, live, irreversible change to an external ad server - only call this after the user has explicitly confirmed this specific Order should be deleted from GAM.'
    )
    public static List<OrderDeleteResult> deleteOrder(List<OrderDeleteRequest> requests) {

        List<OrderDeleteResult> results = new List<OrderDeleteResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        String networkCode = getConfiguredNetworkCode();
        List<Case> auditLogs = new List<Case>();

        for (OrderDeleteRequest request : requests) {

            OrderDeleteResult result = new OrderDeleteResult();
            result.success = false;
            result.orderId = request != null ? request.orderId : null;
            String advertiserNameForLog = null;

            try {
                if (request == null || String.isBlank(request.orderId)) {
                    throw new OrderDeleteException('Order ID is required.');
                }

                Order sfOrder = [
                    SELECT Id, Account.Name
                    FROM Order
                    WHERE Id = :Id.valueOf(request.orderId)
                    LIMIT 1
                ];
                advertiserNameForLog = sfOrder.Account.Name;

                Set<Id> orderItemIds = new Map<Id, OrderItem>([
                    SELECT Id FROM OrderItem WHERE OrderId = :sfOrder.Id
                ]).keySet();

                List<AdOrderItem> adOrderItems = [
                    SELECT Id, AdServerOrderIdentifier, AdServerOrderLineIdentifier
                    FROM AdOrderItem
                    WHERE OrderItemId IN :orderItemIds
                    AND AdServerOrderIdentifier != null
                ];

                if (adOrderItems.isEmpty()) {
                    throw new OrderDeleteException('This Order has no recorded GAM Order ID - it was never pushed, or the identifier is missing.');
                }

                String gamOrderId = adOrderItems[0].AdServerOrderIdentifier;
                result.gamOrderId = gamOrderId;

                deleteGamOrder(gamOrderId, networkCode);

                for (AdOrderItem aoi : adOrderItems) {
                    aoi.AdServerOrderIdentifier = null;
                    aoi.AdServerOrderLineIdentifier = null;
                }
                update adOrderItems;

                result.success = true;
                result.explanation = 'Deleted GAM Order ' + gamOrderId + ' from Google Ad Manager.';

            } catch (Exception e) {
                result.success = false;
                result.explanation = e.getMessage();
            }

            Case logEntry = new Case();
            logEntry.Subject = 'Optimization Log: ' + (result.success ? 'GAM_ORDER_DELETED' : 'GAM_ORDER_DELETE_FAILED') + ' - ' + result.orderId;
            logEntry.Optimization_Line_Item_Id__c = result.orderId;
            logEntry.Optimization_Advertiser__c = advertiserNameForLog;
            logEntry.Optimization_Event_Type__c = result.success ? 'GAM_ORDER_DELETED' : 'GAM_ORDER_DELETE_FAILED';
            logEntry.Description = '[Actor: ' + UserInfo.getName() + '] ' + result.explanation;
            logEntry.Status = 'Closed';
            auditLogs.add(logEntry);

            results.add(result);
        }

        if (!auditLogs.isEmpty()) {
            insert auditLogs;
        }

        return results;
    }


    private static final String GAM_NAMESPACE = 'https://www.google.com/apis/ads/publisher/v202608';

    /*
     * GAM's OrderAction element is an abstract XSD type requiring an
     * explicit xsi:type on the wire to identify the concrete subtype
     * (e.g. DeleteOrders). WSDL2Apex's generated stub does not emit
     * this xsi:type correctly for polymorphic elements (confirmed:
     * neither a concretely-typed field nor an explicit type_info
     * override on the generated wrapper class fixed the outgoing
     * XML), so GAM rejects the request with "cvc-type.2: The type
     * definition cannot be abstract for element orderAction" before
     * it ever reaches business logic. Worked around by building and
     * sending the SOAP envelope by hand, where the xsi:type can be
     * set explicitly, while still routing through the same Named
     * Credential (so org-configured auth/OAuth is applied exactly as
     * it is for every other GAM callout in this project).
     */
    private static void deleteGamOrder(String gamOrderId, String networkCode) {

        String escapedGamOrderId = String.escapeSingleQuotes(gamOrderId);

        String envelope =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                '<soapenv:Header>' +
                    '<RequestHeader xmlns="' + GAM_NAMESPACE + '">' +
                        '<networkCode>' + networkCode + '</networkCode>' +
                        '<applicationName>' + APPLICATION_NAME.escapeXml() + '</applicationName>' +
                    '</RequestHeader>' +
                '</soapenv:Header>' +
                '<soapenv:Body>' +
                    '<performOrderAction xmlns="' + GAM_NAMESPACE + '">' +
                        '<orderAction xsi:type="DeleteOrders"/>' +
                        '<filterStatement>' +
                            '<query>WHERE id = ' + escapedGamOrderId + '</query>' +
                        '</filterStatement>' +
                    '</performOrderAction>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(GAM_NAMED_CREDENTIAL + 'OrderService');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', '""');
        req.setBody(envelope);
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        String responseBody = res.getBody();

        if (responseBody != null && responseBody.contains('<soap:Fault>')) {
            String faultString = extractXmlTag(responseBody, 'faultstring');
            throw new OrderDeleteException(
                String.isNotBlank(faultString) ? faultString : 'GAM returned a SOAP fault while deleting the order.'
            );
        }

        if (res.getStatusCode() != 200) {
            throw new OrderDeleteException('GAM delete request failed with HTTP status ' + res.getStatusCode() + '.');
        }

        String numChangesStr = extractXmlTag(responseBody, 'numChanges');
        Integer numChanges = String.isNotBlank(numChangesStr) ? Integer.valueOf(numChangesStr) : 0;

        if (numChanges < 1) {
            throw new OrderDeleteException('GAM reported 0 orders changed - the Order ID may not exist or delete may not be permitted in its current status.');
        }
    }

    private static String extractXmlTag(String xml, String tagName) {
        if (String.isBlank(xml)) {
            return null;
        }
        Pattern p = Pattern.compile('<(?:[A-Za-z0-9_]+:)?' + tagName + '>(.*?)</(?:[A-Za-z0-9_]+:)?' + tagName + '>');
        Matcher m = p.matcher(xml);
        return m.find() ? m.group(1) : null;
    }


    private static String getConfiguredNetworkCode() {
        GAM_Config__c config = GAM_Config__c.getOrgDefaults();
        if (config == null || String.isBlank(config.Network_Code__c)) {
            throw new OrderDeleteException('No GAM network code is configured yet. Run the GAM onboarding wizard first.');
        }
        return config.Network_Code__c;
    }
}
