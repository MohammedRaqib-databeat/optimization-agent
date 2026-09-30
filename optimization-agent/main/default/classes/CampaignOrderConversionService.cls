public with sharing class CampaignOrderConversionService {

    /*
     * ================================================================
     * MEDIA PLAN TO ORDER CONVERSION ENGINE
     *
     * Standard-object-only implementation of the diagram's "Once
     * approved, the Media Plan is converted into an Order" step.
     *
     * Uses native objects:
     *   - Order (standard) - the commercial order.
     *   - OrderItem (standard) - one per QuoteLineItem.
     *   - AdOrderItem (native Media Cloud) - media-specific order line,
     *     mirroring AdQuoteLine, linked via QuoteLineItemId and
     *     OrderItemId. This is the record the real Order Push / Ad
     *     Server Connector will later push to GAM (AdServerId,
     *     AdServerOrderIdentifier fields exist on it for that purpose,
     *     left blank until that connector is configured).
     *
     * Human-in-the-loop gate: conversion is only allowed when the
     * Quote's Status is "Approved" or "Accepted" - i.e. after the
     * human + advertiser approval step in the diagram. This is a hard
     * precondition, not a suggestion.
     * ================================================================
     */


    private static final Set<String> APPROVED_QUOTE_STATUSES =
        new Set<String>{
            'Approved',
            'Accepted'
        };


    public class OrderConversionRequest {

        @InvocableVariable(
            label='Quote ID'
            required=true
        )
        public String quoteId;
    }


    public class OrderConversionResult {

        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Quote ID')
        public String quoteId;

        @InvocableVariable(label='Order ID')
        public String orderId;

        @InvocableVariable(label='Order Item Count')
        public Decimal orderItemCount;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }


    @InvocableMethod(
        label='Convert Approved Media Plan to Order'
        description='Converts an Approved/Accepted Quote and its AdQuote line items into a standard Order with matching AdOrderItem records. Refuses to run unless the Quote has already passed human/advertiser approval.'
    )
    public static List<OrderConversionResult> convert(
        List<OrderConversionRequest> requests
    ) {

        List<OrderConversionResult> results =
            new List<OrderConversionResult>();

        if (
            requests == null ||
            requests.isEmpty()
        ) {
            return results;
        }

        for (
            OrderConversionRequest request :
            requests
        ) {

            OrderConversionResult result =
                new OrderConversionResult();

            result.success = false;

            Savepoint savepoint =
                Database.setSavepoint();

            try {

                if (
                    request == null ||
                    String.isBlank(request.quoteId)
                ) {

                    throw new OrderConversionException(
                        'Quote ID is required.'
                    );
                }

                result.quoteId = request.quoteId;

                Id quoteId =
                    Id.valueOf(request.quoteId);

                Quote quoteRecord =
                    [
                        SELECT
                            Id,
                            Status,
                            Pricebook2Id,
                            Opportunity.AccountId,
                            Amends_Order__c
                        FROM Quote
                        WHERE Id = :quoteId
                        LIMIT 1
                    ];

                if (quoteRecord.Amends_Order__c != null) {
                    throw new OrderConversionException(
                        'This Quote is an Optimization Amendment (it amends Order ' + quoteRecord.Amends_Order__c +
                        '), not a new media plan - converting it here would create a duplicate, unrelated Order. ' +
                        'Use "Apply Approved Amendment to Order" instead, which updates the existing Order directly.'
                    );
                }

                if (
                    !APPROVED_QUOTE_STATUSES.contains(
                        quoteRecord.Status
                    )
                ) {

                    throw new OrderConversionException(
                        'This Media Plan has not completed human/advertiser approval. Current status: ' +
                        quoteRecord.Status +
                        '. Required: Approved or Accepted.'
                    );
                }

                List<AdQuote> adQuotes =
                    [
                        SELECT
                            Id,
                            StartDate,
                            EndDate
                        FROM AdQuote
                        WHERE QuoteId = :quoteId
                        LIMIT 1
                    ];

                if (
                    adQuotes.isEmpty()
                ) {

                    throw new OrderConversionException(
                        'No Ad Media Plan (AdQuote) was found for this Quote.'
                    );
                }

                AdQuote adQuote =
                    adQuotes[0];

                List<QuoteLineItem> quoteLineItems =
                    [
                        SELECT
                            Id,
                            PricebookEntryId,
                            Quantity,
                            UnitPrice
                        FROM QuoteLineItem
                        WHERE QuoteId = :quoteId
                    ];

                if (
                    quoteLineItems.isEmpty()
                ) {

                    throw new OrderConversionException(
                        'This Quote has no Quote Line Items to convert.'
                    );
                }

                Map<Id, AdQuoteLine> adQuoteLinesByQuoteLineItemId =
                    new Map<Id, AdQuoteLine>();

                for (
                    AdQuoteLine adLine :
                    [
                        SELECT
                            Id,
                            Name,
                            QuoteLineItemId,
                            MediaType,
                            Budget,
                            AdRequestedQuantity,
                            AdRequestedStartDate,
                            AdRequestedEndDate
                        FROM AdQuoteLine
                        WHERE AdQuoteId = :adQuote.Id
                    ]
                ) {

                    if (
                        adLine.QuoteLineItemId != null
                    ) {

                        adQuoteLinesByQuoteLineItemId.put(
                            adLine.QuoteLineItemId,
                            adLine
                        );
                    }
                }

                Order newOrder =
                    new Order();

                newOrder.AccountId = quoteRecord.Opportunity.AccountId;
                newOrder.Pricebook2Id = quoteRecord.Pricebook2Id;
                newOrder.QuoteId = quoteRecord.Id;
                newOrder.Status = 'Draft';

                newOrder.EffectiveDate =
                    adQuote.StartDate != null
                        ? adQuote.StartDate.date()
                        : Date.today();

                if (
                    adQuote.EndDate != null
                ) {
                    newOrder.EndDate = adQuote.EndDate.date();
                }

                insert newOrder;

                List<OrderItem> orderItems =
                    new List<OrderItem>();

                for (
                    QuoteLineItem qli :
                    quoteLineItems
                ) {

                    OrderItem orderItem =
                        new OrderItem();

                    orderItem.OrderId = newOrder.Id;
                    orderItem.PricebookEntryId = qli.PricebookEntryId;
                    orderItem.Quantity = qli.Quantity;
                    orderItem.UnitPrice = qli.UnitPrice;

                    orderItems.add(orderItem);
                }

                insert orderItems;

                List<AdOrderItem> adOrderItems =
                    new List<AdOrderItem>();

                for (
                    Integer i = 0;
                    i < quoteLineItems.size();
                    i++
                ) {

                    QuoteLineItem qli =
                        quoteLineItems[i];

                    AdQuoteLine matchingAdLine =
                        adQuoteLinesByQuoteLineItemId.get(
                            qli.Id
                        );

                    if (
                        matchingAdLine == null
                    ) {
                        continue;
                    }

                    AdOrderItem adOrderItem =
                        new AdOrderItem();

                    adOrderItem.Name = matchingAdLine.Name;
                    adOrderItem.OrderId = newOrder.Id;
                    adOrderItem.OrderItemId = orderItems[i].Id;
                    adOrderItem.QuoteLineItemId = qli.Id;
                    adOrderItem.MediaType = matchingAdLine.MediaType;
                    adOrderItem.Budget = matchingAdLine.Budget;

                    adOrderItems.add(adOrderItem);
                }

                if (
                    !adOrderItems.isEmpty()
                ) {
                    insert adOrderItems;
                }

                result.orderId = newOrder.Id;
                result.orderItemCount = orderItems.size();

                result.explanation =
                    'Order created in Draft status with ' +
                    orderItems.size() +
                    ' line item(s). This Order has not been pushed to any ' +
                    'ad server - that requires the Order Push / Ad Server ' +
                    'Connector, which is not yet configured.';

                result.success = true;

            } catch (Exception e) {

                Database.rollback(savepoint);

                result.success = false;
                result.explanation = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }


    public class OrderConversionException extends Exception {
    }
}
