public with sharing class GAMNetworkServiceClient {

    /*
     * ================================================================
     * GAM CONNECTION VERIFIER
     *
     * Thin wrapper around the WSDL2Apex-generated GAMNetworkServiceStub.
     * Calls NetworkService.getCurrentNetwork() - the standard, minimal
     * call used purely to prove the JWT Bearer auth chain (Certificate
     * -> External Credential -> Named Credential) actually authenticates
     * against a live GAM network. Returns no business data on its own;
     * this is a connectivity/auth check, not part of the Optimization
     * Agent's evidence pipeline.
     * ================================================================
     */

    private static final String APPLICATION_NAME = 'Salesforce Media Cloud Optimization Agent';

    // Reads the network code detected during onboarding (see
    // discoverNetwork()) from the GAM_Config__c hierarchy custom
    // setting. No more hardcoded per-org constant - each client's
    // package install gets its own value written here once, during
    // their onboarding wizard flow.
    private static String getConfiguredNetworkCode() {
        GAM_Config__c config = GAM_Config__c.getOrgDefaults();
        if (config == null || String.isBlank(config.Network_Code__c)) {
            throw new GAMDiscoveryException(
                'No GAM network code is configured yet. Run the GAM onboarding wizard first.'
            );
        }
        return config.Network_Code__c;
    }


    public class GAMConnectionResult {

        public Boolean success;
        public String networkDisplayName;
        public String networkCode;
        public String currencyCode;
        public String timeZone;
        public String errorMessage;
    }


    // Auto-detects the client's GAM network code without needing it
    // supplied up front - GAM's getAllNetworks() is the one operation
    // that doesn't require a networkCode in the request header
    // (confirmed via direct test: getCurrentNetwork() fails with
    // AuthenticationError.NETWORK_CODE_REQUIRED when the header is
    // blank, getAllNetworks() does not). Used by the onboarding
    // wizard right after the Named Credential is provisioned, so a
    // brand-new client never has to go find their own network code.
    public static GAMConnectionResult discoverNetwork() {

        GAMConnectionResult result = new GAMConnectionResult();
        result.success = false;

        try {

            GAMNetworkServiceStub.NetworkServiceInterfacePort port =
                new GAMNetworkServiceStub.NetworkServiceInterfacePort();

            port.endpoint_x = 'callout:GAM_API/NetworkService';

            GAMNetworkServiceStub.SoapRequestHeader requestHeader =
                new GAMNetworkServiceStub.SoapRequestHeader();

            requestHeader.applicationName = APPLICATION_NAME;
            port.RequestHeader = requestHeader;

            GAMNetworkServiceStub.Network[] networks = port.getAllNetworks();

            if (networks == null || networks.isEmpty()) {
                throw new GAMDiscoveryException(
                    'This service account is not yet linked to any GAM network. Ask your GAM administrator to add it as a user in your GAM Admin panel first.'
                );
            }

            GAMNetworkServiceStub.Network network = networks[0];

            result.success = true;
            result.networkDisplayName = network.displayName;
            result.networkCode = network.networkCode;
            result.currencyCode = network.currencyCode;
            result.timeZone = network.timeZone;

            GAM_Config__c config = GAM_Config__c.getOrgDefaults();
            config.Network_Code__c = network.networkCode;
            upsert config;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    public class GAMDiscoveryException extends Exception {}

    public static GAMConnectionResult getCurrentNetwork() {

        GAMConnectionResult result =
            new GAMConnectionResult();

        result.success = false;

        try {

            GAMNetworkServiceStub.NetworkServiceInterfacePort port =
                new GAMNetworkServiceStub.NetworkServiceInterfacePort();

            port.endpoint_x =
                'callout:GAM_API/NetworkService';

            GAMNetworkServiceStub.SoapRequestHeader requestHeader =
                new GAMNetworkServiceStub.SoapRequestHeader();

            requestHeader.networkCode = getConfiguredNetworkCode();
            requestHeader.applicationName = APPLICATION_NAME;

            port.RequestHeader = requestHeader;

            GAMNetworkServiceStub.Network network =
                port.getCurrentNetwork();

            result.success = true;
            result.networkDisplayName = network.displayName;
            result.networkCode = network.networkCode;
            result.currencyCode = network.currencyCode;
            result.timeZone = network.timeZone;

        } catch (Exception e) {

            result.success = false;
            result.errorMessage =
                e.getMessage();
        }

        return result;
    }
}
