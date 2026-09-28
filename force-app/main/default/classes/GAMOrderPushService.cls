public with sharing class GAMOrderPushService {

    /*
     * ================================================================
     * ORDER PUSH CONNECTOR (Salesforce Order -> real GAM Order/LineItem)
     * ================================================================
     *
     * This is the missing piece flagged throughout this project:
     * CampaignOrderConversionService creates a Draft standard Order
     * (plus AdOrderItem) from an Approved Quote, but never pushed
     * anything to an ad server - AdOrderItem.AdServerOrderIdentifier/
     * AdServerOrderLineIdentifier were always left blank. This class
     * does that real push, using the four GAM SOAP services already
     * validated live in this org (Company/Order/LineItem/User/
     * Inventory).
     *
     * Human-in-the-loop: this is a real, consequential write to a
     * live ad server. It must only run after explicit human
     * confirmation (isConfirmationRequired = true on its Agentforce
     * action), exactly like every other write path in this project.
     *
     * Honest MVP limitations, flagged rather than hidden:
     *   - Advertiser mapping is find-or-create by exact Account name
     *     against GAM's Company records (same pattern already used
     *     for Lead/Opportunity resolution elsewhere in this project).
     *   - LineItem targeting resolves the Ad Unit from
     *     Product2.GAM_Ad_Unit_Name__c (exact name lookup against GAM)
     *     when a product has one configured, falling back to the
     *     first ACTIVE Ad Unit in the network when it doesn't or the
     *     configured name isn't found - there is still no real
     *     AdSpaceSpecification-driven targeting model in this project,
     *     so this is a per-product config field, not a full mapping
     *     engine.
     *   - Creative size comes from Product2.GAM_Creative_Width__c /
     *     GAM_Creative_Height__c when set, defaulting to 300x250
     *     otherwise - no creative size data is captured on
     *     Quote/Order records yet in this project.
     *   - costType is always CPM and the goal is always a LIFETIME
     *     IMPRESSIONS goal, since Order/OrderItem don't yet carry a
     *     distinct cost-type or goal-type field.
     * ================================================================
     */

    private static final String GAM_NAMED_CREDENTIAL = 'callout:GAM_API/';
    private static final String APPLICATION_NAME = 'Salesforce Media Cloud Optimization Agent';


    public class OrderPushRequest {
        @InvocableVariable(label='Order ID' required=true)
        public String orderId;
    }

    public class OrderPushResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Order ID')
        public String orderId;

        @InvocableVariable(label='GAM Order ID')
        public String gamOrderId;

        @InvocableVariable(label='Line Items Pushed')
        public Decimal lineItemsPushed;

        @InvocableVariable(label='Explanation')
        public String explanation;
    }

    public class OrderPushException extends Exception {}


    @InvocableMethod(
        label='Push Order to Google Ad Manager'
        description='Pushes a Draft standard Order (with its AdOrderItem line items) to Google Ad Manager as a real Order and LineItems, then writes the returned GAM IDs back onto AdOrderItem. This is a real, live change to an external ad server - only call this after the user has explicitly confirmed this specific Order should be pushed.'
    )
    public static List<OrderPushResult> push(List<OrderPushRequest> requests) {

        List<OrderPushResult> results = new List<OrderPushResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        String networkCode = getConfiguredNetworkCode();
        List<Case> auditLogs = new List<Case>();

        for (OrderPushRequest request : requests) {

            OrderPushResult result = new OrderPushResult();
            result.success = false;
            String advertiserNameForLog = null;

            try {
                if (request == null || String.isBlank(request.orderId)) {
                    throw new OrderPushException('Order ID is required.');
                }

                result.orderId = request.orderId;

                Order sfOrder = [
                    SELECT Id, OrderNumber, AccountId, Account.Name,
                           EffectiveDate, EndDate, Status
                    FROM Order
                    WHERE Id = :Id.valueOf(request.orderId)
                    LIMIT 1
                ];

                advertiserNameForLog = sfOrder.Account.Name;

                List<OrderItem> orderItems = [
                    SELECT Id, Quantity, UnitPrice, Product2.Name,
                        Product2.GAM_Ad_Unit_Name__c, Product2.GAM_Creative_Width__c, Product2.GAM_Creative_Height__c
                    FROM OrderItem
                    WHERE OrderId = :sfOrder.Id
                    ORDER BY Id
                ];

                if (orderItems.isEmpty()) {
                    throw new OrderPushException('This Order has no Order Items to push.');
                }

                List<AdOrderItem> adOrderItems = [
                    SELECT Id, OrderItemId, AdServerOrderIdentifier, AdServerOrderLineIdentifier
                    FROM AdOrderItem
                    WHERE OrderItemId IN :new Map<Id, OrderItem>(orderItems).keySet()
                ];

                Map<Id, AdOrderItem> adOrderItemByOrderItemId = new Map<Id, AdOrderItem>();
                for (AdOrderItem aoi : adOrderItems) {
                    adOrderItemByOrderItemId.put(aoi.OrderItemId, aoi);
                }

                Account acc = [SELECT Id, GAM_Company_Id__c FROM Account WHERE Id = :sfOrder.AccountId LIMIT 1];

                Long gamUserId = getCurrentGamUserId(networkCode);

                Long gamCompanyId;
                Boolean accountNeedsUpdate = false;

                if (!String.isBlank(acc.GAM_Company_Id__c)) {
                    gamCompanyId = Long.valueOf(acc.GAM_Company_Id__c);
                } else {
                    gamCompanyId = findOrCreateGamCompany(sfOrder.Account.Name, networkCode);
                    acc.GAM_Company_Id__c = String.valueOf(gamCompanyId);
                    accountNeedsUpdate = true;
                }

                String fallbackAdUnitId = getFirstActiveAdUnitId(networkCode);
                Map<String, String> adUnitIdByConfiguredName = new Map<String, String>();

                Long gamOrderId = createGamOrder(sfOrder, gamCompanyId, gamUserId, networkCode);

                List<GAMLineItemServiceStub.LineItem> lineItemsToCreate = new List<GAMLineItemServiceStub.LineItem>();
                List<OrderItem> orderItemsInSameSequence = new List<OrderItem>();

                Date lineItemEndDate = sfOrder.EndDate != null
                    ? sfOrder.EndDate
                    : sfOrder.EffectiveDate.addDays(90);

                /*
                 * GAM requires a Line Item name to be unique within its
                 * Order. A single Salesforce Order can have multiple
                 * OrderItems for the same Product (confirmed in this
                 * org, e.g. an Order with the same product 3 times), so
                 * the base product name must be disambiguated with a
                 * suffix before it collides on the wire.
                 */
                Map<String, Integer> baseNameOccurrences = new Map<String, Integer>();

                for (OrderItem oi : orderItems) {
                    String baseName = !String.isBlank(oi.Product2.Name) ? oi.Product2.Name : ('Order Item ' + oi.Id);
                    Integer occurrence = baseNameOccurrences.containsKey(baseName) ? baseNameOccurrences.get(baseName) + 1 : 1;
                    baseNameOccurrences.put(baseName, occurrence);

                    String uniqueLineItemName = occurrence == 1 ? baseName : (baseName + ' (' + occurrence + ')');

                    String configuredAdUnitName = oi.Product2.GAM_Ad_Unit_Name__c;
                    String resolvedAdUnitId = fallbackAdUnitId;

                    if (!String.isBlank(configuredAdUnitName)) {
                        if (adUnitIdByConfiguredName.containsKey(configuredAdUnitName)) {
                            resolvedAdUnitId = adUnitIdByConfiguredName.get(configuredAdUnitName);
                        } else {
                            String lookedUpId = findAdUnitIdByName(configuredAdUnitName, networkCode);
                            resolvedAdUnitId = String.isNotBlank(lookedUpId) ? lookedUpId : fallbackAdUnitId;
                            adUnitIdByConfiguredName.put(configuredAdUnitName, resolvedAdUnitId);
                        }
                    }

                    Integer creativeWidth = oi.Product2.GAM_Creative_Width__c != null
                        ? oi.Product2.GAM_Creative_Width__c.intValue() : 300;
                    Integer creativeHeight = oi.Product2.GAM_Creative_Height__c != null
                        ? oi.Product2.GAM_Creative_Height__c.intValue() : 250;

                    lineItemsToCreate.add(
                        buildGamLineItem(oi, gamOrderId, resolvedAdUnitId, lineItemEndDate, uniqueLineItemName, creativeWidth, creativeHeight)
                    );
                    orderItemsInSameSequence.add(oi);
                }

                List<GAMLineItemServiceStub.LineItem> createdLineItems =
                    createGamLineItems(lineItemsToCreate, networkCode);

                List<AdOrderItem> adOrderItemsToUpdate = new List<AdOrderItem>();
                List<AdOrderItem> adOrderItemsToInsert = new List<AdOrderItem>();

                for (Integer i = 0; i < createdLineItems.size(); i++) {

                    OrderItem sourceOrderItem = orderItemsInSameSequence[i];
                    GAMLineItemServiceStub.LineItem createdLineItem = createdLineItems[i];

                    AdOrderItem aoi = adOrderItemByOrderItemId.get(sourceOrderItem.Id);
                    if (aoi == null) {
                        aoi = new AdOrderItem();
                        aoi.Name = createdLineItem.name;
                        aoi.OrderId = sfOrder.Id;
                        aoi.OrderItemId = sourceOrderItem.Id;
                        aoi.AdServerOrderIdentifier = String.valueOf(gamOrderId);
                        aoi.AdServerOrderLineIdentifier = String.valueOf(createdLineItem.id);
                        adOrderItemsToInsert.add(aoi);
                        continue;
                    }

                    aoi.AdServerOrderIdentifier = String.valueOf(gamOrderId);
                    aoi.AdServerOrderLineIdentifier = String.valueOf(createdLineItem.id);
                    adOrderItemsToUpdate.add(aoi);
                }

                if (accountNeedsUpdate) {
                    update acc;
                }

                if (!adOrderItemsToUpdate.isEmpty()) {
                    update adOrderItemsToUpdate;
                }

                if (!adOrderItemsToInsert.isEmpty()) {
                    insert adOrderItemsToInsert;
                }

                result.gamOrderId = String.valueOf(gamOrderId);
                result.lineItemsPushed = createdLineItems.size();
                result.success = true;
                result.explanation = 'Pushed Order ' + sfOrder.OrderNumber + ' to Google Ad Manager as Order ' +
                    gamOrderId + ' with ' + createdLineItems.size() + ' Line Item(s). AdOrderItem records ' +
                    'updated with the real GAM identifiers.';

            } catch (Exception e) {
                result.success = false;
                result.explanation = e.getMessage();
            }

            Case logEntry = new Case();
            logEntry.Subject = 'Optimization Log: ' + (result.success ? 'GAM_ORDER_PUSHED' : 'GAM_ORDER_PUSH_FAILED') + ' - ' + result.orderId;
            logEntry.Optimization_Line_Item_Id__c = result.orderId;
            logEntry.Optimization_Advertiser__c = advertiserNameForLog;
            logEntry.Optimization_Event_Type__c = result.success ? 'GAM_ORDER_PUSHED' : 'GAM_ORDER_PUSH_FAILED';
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


    private static String getConfiguredNetworkCode() {
        GAM_Config__c config = GAM_Config__c.getOrgDefaults();
        if (config == null || String.isBlank(config.Network_Code__c)) {
            throw new OrderPushException('No GAM network code is configured yet. Run the GAM onboarding wizard first.');
        }
        return config.Network_Code__c;
    }

    private static GAMCompanyServiceStub.SoapRequestHeader buildCompanyHeader(String networkCode) {
        GAMCompanyServiceStub.SoapRequestHeader header = new GAMCompanyServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }

    private static GAMOrderServiceStub.SoapRequestHeader buildOrderHeader(String networkCode) {
        GAMOrderServiceStub.SoapRequestHeader header = new GAMOrderServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }

    private static GAMLineItemServiceStub.SoapRequestHeader buildLineItemHeader(String networkCode) {
        GAMLineItemServiceStub.SoapRequestHeader header = new GAMLineItemServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }

    private static GAMUserServiceStub.SoapRequestHeader buildUserHeader(String networkCode) {
        GAMUserServiceStub.SoapRequestHeader header = new GAMUserServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }

    private static GAMInventoryServiceStub.SoapRequestHeader buildInventoryHeader(String networkCode) {
        GAMInventoryServiceStub.SoapRequestHeader header = new GAMInventoryServiceStub.SoapRequestHeader();
        header.networkCode = networkCode;
        header.applicationName = APPLICATION_NAME;
        return header;
    }


    private static Long getCurrentGamUserId(String networkCode) {

        GAMUserServiceStub.UserServiceInterfacePort port = new GAMUserServiceStub.UserServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'UserService';
        port.RequestHeader = buildUserHeader(networkCode);

        GAMUserServiceStub.User_x currentUser = port.getCurrentUser();
        return currentUser.id;
    }


    private static String getFirstActiveAdUnitId(String networkCode) {

        GAMInventoryServiceStub.InventoryServiceInterfacePort port =
            new GAMInventoryServiceStub.InventoryServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'InventoryService';
        port.RequestHeader = buildInventoryHeader(networkCode);

        GAMInventoryServiceStub.Statement statement = new GAMInventoryServiceStub.Statement();
        statement.query = 'WHERE status = \'ACTIVE\' LIMIT 1';

        GAMInventoryServiceStub.AdUnitPage page = port.getAdUnitsByStatement(statement);

        if (page.results == null || page.results.isEmpty()) {
            throw new OrderPushException('No active Ad Units found in this GAM network to target.');
        }

        return page.results[0].id;
    }


    /*
     * Looks up a specific Ad Unit by its exact configured name
     * (Product2.GAM_Ad_Unit_Name__c). Returns null (caller falls back
     * to getFirstActiveAdUnitId's result) when not configured, not
     * found, or not ACTIVE - never throws, since a missing/renamed Ad
     * Unit name on one product should degrade gracefully rather than
     * fail the whole Order push.
     */
    private static String findAdUnitIdByName(String adUnitName, String networkCode) {

        GAMInventoryServiceStub.InventoryServiceInterfacePort port =
            new GAMInventoryServiceStub.InventoryServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'InventoryService';
        port.RequestHeader = buildInventoryHeader(networkCode);

        String escapedName = adUnitName.replace('\'', '\\\'');

        GAMInventoryServiceStub.Statement statement = new GAMInventoryServiceStub.Statement();
        statement.query = 'WHERE status = \'ACTIVE\' AND name = \'' + escapedName + '\' LIMIT 1';

        GAMInventoryServiceStub.AdUnitPage page = port.getAdUnitsByStatement(statement);

        if (page == null || page.results == null || page.results.isEmpty()) {
            return null;
        }

        return page.results[0].id;
    }


    /*
     * Read/create-only against GAM - deliberately does no DML itself.
     * Callouts cannot follow a DML statement in the same transaction,
     * so any Account.GAM_Company_Id__c update is deferred to the end
     * of push(), after every callout in the whole flow has completed.
     */
    private static Long findOrCreateGamCompany(String accountName, String networkCode) {

        GAMCompanyServiceStub.CompanyServiceInterfacePort port =
            new GAMCompanyServiceStub.CompanyServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'CompanyService';
        port.RequestHeader = buildCompanyHeader(networkCode);

        // Bind-variable Statement.values requires a polymorphic Value
        // type that WSDL2Apex did not generate real inheritance for
        // (TextValue does not actually extend Value in the generated
        // code), so the name is escaped and inlined directly into the
        // PQL query text instead of using a bind parameter.
        String escapedName = accountName.replace('\'', '\\\'');

        GAMCompanyServiceStub.Statement lookupStatement = new GAMCompanyServiceStub.Statement();
        lookupStatement.query = 'WHERE name = \'' + escapedName + '\' LIMIT 1';

        GAMCompanyServiceStub.CompanyPage existingPage = port.getCompaniesByStatement(lookupStatement);

        Long companyId;

        if (existingPage.results != null && !existingPage.results.isEmpty()) {
            companyId = existingPage.results[0].id;
        } else {
            GAMCompanyServiceStub.Company newCompany = new GAMCompanyServiceStub.Company();
            newCompany.name = accountName;
            newCompany.type_x = 'ADVERTISER';

            GAMCompanyServiceStub.Company[] created =
                port.createCompanies(new GAMCompanyServiceStub.Company[]{ newCompany });

            companyId = created[0].id;
        }

        return companyId;
    }


    /*
     * Find-or-create by name, same pattern as findOrCreateGamCompany.
     * A previous push attempt can fail AFTER the GAM Order was
     * already created (e.g. a later LineItem validation error) - GAM
     * has no transaction to roll that back, so a retry must reuse the
     * existing Order rather than fail on a name collision.
     */
    private static Long createGamOrder(Order sfOrder, Long gamCompanyId, Long gamUserId, String networkCode) {

        GAMOrderServiceStub.OrderServiceInterfacePort port =
            new GAMOrderServiceStub.OrderServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'OrderService';
        port.RequestHeader = buildOrderHeader(networkCode);

        String orderName = 'SF Order ' + sfOrder.OrderNumber;

        GAMOrderServiceStub.Statement lookupStatement = new GAMOrderServiceStub.Statement();
        lookupStatement.query = 'WHERE name = \'' + orderName.replace('\'', '\\\'') + '\' LIMIT 1';

        GAMOrderServiceStub.OrderPage existingPage = port.getOrdersByStatement(lookupStatement);

        if (existingPage.results != null && !existingPage.results.isEmpty()) {
            return existingPage.results[0].id;
        }

        GAMOrderServiceStub.Order newOrder = new GAMOrderServiceStub.Order();
        newOrder.name = orderName;
        newOrder.advertiserId = gamCompanyId;
        newOrder.traffickerId = gamUserId;
        newOrder.salespersonId = gamUserId;
        newOrder.startDateTime = toGamOrderDateTime(sfOrder.EffectiveDate);

        if (sfOrder.EndDate != null) {
            newOrder.endDateTime = toGamOrderDateTime(sfOrder.EndDate);
        } else {
            newOrder.unlimitedEndDateTime = true;
        }

        GAMOrderServiceStub.Order[] created =
            port.createOrders(new GAMOrderServiceStub.Order[]{ newOrder });

        return created[0].id;
    }


    private static GAMLineItemServiceStub.LineItem buildGamLineItem(
        OrderItem oi, Long gamOrderId, String gamAdUnitId, Date endDate, String uniqueLineItemName,
        Integer creativeWidth, Integer creativeHeight
    ) {

        GAMLineItemServiceStub.LineItem lineItem = new GAMLineItemServiceStub.LineItem();
        lineItem.orderId = gamOrderId;
        lineItem.name = uniqueLineItemName;
        lineItem.lineItemType = 'STANDARD';
        lineItem.costType = 'CPM';
        lineItem.startDateTimeType = 'IMMEDIATELY';
        lineItem.endDateTime = toGamLineItemDateTime(endDate);
        lineItem.creativeRotationType = 'EVEN';

        GAMLineItemServiceStub.Money costPerUnit = new GAMLineItemServiceStub.Money();
        costPerUnit.currencyCode = 'USD';
        costPerUnit.microAmount = ((oi.UnitPrice != null ? oi.UnitPrice : 0) * 1000000).longValue();
        lineItem.costPerUnit = costPerUnit;

        GAMLineItemServiceStub.Goal goal = new GAMLineItemServiceStub.Goal();
        goal.goalType = 'LIFETIME';
        goal.unitType = 'IMPRESSIONS';
        goal.units = (oi.Quantity != null ? oi.Quantity : 1000).longValue();
        lineItem.primaryGoal = goal;

        GAMLineItemServiceStub.Size creativeSize = new GAMLineItemServiceStub.Size();
        creativeSize.width = creativeWidth;
        creativeSize.height = creativeHeight;
        creativeSize.isAspectRatio = false;

        GAMLineItemServiceStub.CreativePlaceholder placeholder = new GAMLineItemServiceStub.CreativePlaceholder();
        placeholder.size = creativeSize;
        lineItem.creativePlaceholders = new List<GAMLineItemServiceStub.CreativePlaceholder>{ placeholder };

        GAMLineItemServiceStub.AdUnitTargeting adUnitTargeting = new GAMLineItemServiceStub.AdUnitTargeting();
        adUnitTargeting.adUnitId = gamAdUnitId;
        adUnitTargeting.includeDescendants = true;

        GAMLineItemServiceStub.InventoryTargeting inventoryTargeting = new GAMLineItemServiceStub.InventoryTargeting();
        inventoryTargeting.targetedAdUnits = new List<GAMLineItemServiceStub.AdUnitTargeting>{ adUnitTargeting };

        GAMLineItemServiceStub.Targeting targeting = new GAMLineItemServiceStub.Targeting();
        targeting.inventoryTargeting = inventoryTargeting;
        lineItem.targeting = targeting;

        return lineItem;
    }


    private static List<GAMLineItemServiceStub.LineItem> createGamLineItems(
        List<GAMLineItemServiceStub.LineItem> lineItems, String networkCode
    ) {

        GAMLineItemServiceStub.LineItemServiceInterfacePort port =
            new GAMLineItemServiceStub.LineItemServiceInterfacePort();
        port.endpoint_x = GAM_NAMED_CREDENTIAL + 'LineItemService';
        port.RequestHeader = buildLineItemHeader(networkCode);

        List<GAMLineItemServiceStub.LineItem> results = new List<GAMLineItemServiceStub.LineItem>();
        List<GAMLineItemServiceStub.LineItem> toCreate = new List<GAMLineItemServiceStub.LineItem>();
        List<Integer> toCreateOriginalIndex = new List<Integer>();
        List<GAMLineItemServiceStub.LineItem> toUpdate = new List<GAMLineItemServiceStub.LineItem>();
        List<Integer> toUpdateOriginalIndex = new List<Integer>();

        for (Integer i = 0; i < lineItems.size(); i++) {
            results.add(null);
            GAMLineItemServiceStub.LineItem candidate = lineItems[i];

            GAMLineItemServiceStub.Statement lookupStatement = new GAMLineItemServiceStub.Statement();
            lookupStatement.query = 'WHERE orderId = ' + candidate.orderId +
                ' AND name = \'' + String.valueOf(candidate.name).replace('\'', '\\\'') + '\' LIMIT 1';

            GAMLineItemServiceStub.LineItemPage existingPage = port.getLineItemsByStatement(lookupStatement);

            if (existingPage != null && existingPage.results != null && !existingPage.results.isEmpty()) {
                /*
                 * A same-named Line Item already exists in GAM (this
                 * Order was pushed before). Rather than leaving it
                 * untouched - which would silently ignore any real
                 * change (e.g. an approved optimization amendment) -
                 * push the candidate's current goal/cost onto the
                 * existing Line Item via updateLineItems, so a
                 * re-push genuinely reflects the latest approved
                 * values in GAM.
                 */
                GAMLineItemServiceStub.LineItem existing = existingPage.results[0];
                existing.primaryGoal = candidate.primaryGoal;
                existing.costPerUnit = candidate.costPerUnit;
                existing.endDateTime = candidate.endDateTime;
                toUpdate.add(existing);
                toUpdateOriginalIndex.add(i);
            } else {
                toCreate.add(candidate);
                toCreateOriginalIndex.add(i);
            }
        }

        if (!toUpdate.isEmpty()) {
            List<GAMLineItemServiceStub.LineItem> updated = port.updateLineItems(toUpdate);
            for (Integer i = 0; i < updated.size(); i++) {
                results[toUpdateOriginalIndex[i]] = updated[i];
            }
        }

        if (!toCreate.isEmpty()) {
            List<GAMLineItemServiceStub.LineItem> created = port.createLineItems(toCreate);
            for (Integer i = 0; i < created.size(); i++) {
                results[toCreateOriginalIndex[i]] = created[i];
            }
        }

        return results;
    }


    private static GAMOrderServiceStub.DateTime_x toGamOrderDateTime(Date d) {

        GAMOrderServiceStub.Date_x gamDate = new GAMOrderServiceStub.Date_x();
        gamDate.year = d.year();
        gamDate.month = d.month();
        gamDate.day = d.day();

        GAMOrderServiceStub.DateTime_x gamDateTime = new GAMOrderServiceStub.DateTime_x();
        gamDateTime.date_x = gamDate;
        gamDateTime.hour = 0;
        gamDateTime.minute = 0;
        gamDateTime.second = 0;
        gamDateTime.timeZoneId = UserInfo.getTimeZone().getID();

        return gamDateTime;
    }


    private static GAMLineItemServiceStub.DateTime_x toGamLineItemDateTime(Date d) {

        GAMLineItemServiceStub.Date_x gamDate = new GAMLineItemServiceStub.Date_x();
        gamDate.year = d.year();
        gamDate.month = d.month();
        gamDate.day = d.day();

        GAMLineItemServiceStub.DateTime_x gamDateTime = new GAMLineItemServiceStub.DateTime_x();
        gamDateTime.date_x = gamDate;
        gamDateTime.hour = 23;
        gamDateTime.minute = 59;
        gamDateTime.second = 59;
        gamDateTime.timeZoneId = UserInfo.getTimeZone().getID();

        return gamDateTime;
    }
}
