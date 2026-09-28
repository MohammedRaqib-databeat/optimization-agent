public with sharing class GAMOrderButtonController {

    public class GamOrderStatus {
        @AuraEnabled public Boolean isPushed;
        @AuraEnabled public String gamOrderId;
    }

    /*
     * GAMOrderPushService.OrderPushResult / GAMOrderDeleteService.OrderDeleteResult
     * only mark their fields with @InvocableVariable (for Flow/Agentforce use),
     * not @AuraEnabled - Lightning strips every field from an @AuraEnabled
     * method's return value unless each field itself is @AuraEnabled, so
     * returning those types directly here serializes to an empty object
     * client-side. Mapping into local @AuraEnabled DTOs here instead of
     * editing those already-verified services, which stay untouched.
     */
    public class GamPushResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String orderId;
        @AuraEnabled public String gamOrderId;
        @AuraEnabled public Decimal lineItemsPushed;
        @AuraEnabled public String explanation;
    }

    public class GamDeleteResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String orderId;
        @AuraEnabled public String gamOrderId;
        @AuraEnabled public String explanation;
    }

    @AuraEnabled(cacheable=true)
    public static GamOrderStatus getGamOrderStatus(Id orderId) {
        List<AdOrderItem> adOrderItems = [
            SELECT Id, AdServerOrderIdentifier
            FROM AdOrderItem
            WHERE OrderItem.OrderId = :orderId
            AND AdServerOrderIdentifier != null
            LIMIT 1
        ];

        GamOrderStatus result = new GamOrderStatus();
        result.isPushed = !adOrderItems.isEmpty();
        result.gamOrderId = adOrderItems.isEmpty() ? null : adOrderItems[0].AdServerOrderIdentifier;
        return result;
    }

    @AuraEnabled
    public static GamPushResult pushOrderToGam(Id orderId) {
        GAMOrderPushService.OrderPushRequest request = new GAMOrderPushService.OrderPushRequest();
        request.orderId = orderId;

        List<GAMOrderPushService.OrderPushResult> results =
            GAMOrderPushService.push(new List<GAMOrderPushService.OrderPushRequest>{ request });

        if (results.isEmpty()) {
            return null;
        }

        GAMOrderPushService.OrderPushResult source = results[0];
        GamPushResult dto = new GamPushResult();
        dto.success = source.success;
        dto.orderId = source.orderId;
        dto.gamOrderId = source.gamOrderId;
        dto.lineItemsPushed = source.lineItemsPushed;
        dto.explanation = source.explanation;
        return dto;
    }

    @AuraEnabled
    public static GamDeleteResult deleteOrderFromGam(Id orderId) {
        GAMOrderDeleteService.OrderDeleteRequest request = new GAMOrderDeleteService.OrderDeleteRequest();
        request.orderId = orderId;

        List<GAMOrderDeleteService.OrderDeleteResult> results =
            GAMOrderDeleteService.deleteOrder(new List<GAMOrderDeleteService.OrderDeleteRequest>{ request });

        if (results.isEmpty()) {
            return null;
        }

        GAMOrderDeleteService.OrderDeleteResult source = results[0];
        GamDeleteResult dto = new GamDeleteResult();
        dto.success = source.success;
        dto.orderId = source.orderId;
        dto.gamOrderId = source.gamOrderId;
        dto.explanation = source.explanation;
        return dto;
    }
}
