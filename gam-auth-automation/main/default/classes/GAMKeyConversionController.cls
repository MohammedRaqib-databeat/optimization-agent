public with sharing class GAMKeyConversionController {

    /*
     * ================================================================
     * GAM ONBOARDING - KEY CONVERSION BRIDGE
     *
     * This Apex class never stores, logs, or persists the client's
     * service account JSON or the resulting JKS bytes anywhere. It is
     * a pure in-memory pass-through: the LWC sends the pasted JSON to
     * GAMJKSBuilder, which converts it entirely within Apex (no
     * external callout, no custom object, no platform event, no debug
     * log containing the key material), and the result is handed
     * straight back to the browser to download.
     * ================================================================
     */

    public class ConversionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String jksBase64;
        @AuraEnabled public String keystorePassword;
        @AuraEnabled public String alias;
        @AuraEnabled public String issuer;
        @AuraEnabled public String errorMessage;
    }


    @AuraEnabled
    public static ConversionResult convertServiceAccountKey(String serviceAccountJsonText) {

        ConversionResult result = new ConversionResult();
        result.success = false;

        try {

            if (String.isBlank(serviceAccountJsonText)) {
                throw new GAMOnboardingException(
                    'Please paste the full contents of your Google service account JSON key file.'
                );
            }

            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(serviceAccountJsonText);

            if (!parsed.containsKey('private_key') || !parsed.containsKey('client_email')) {
                throw new GAMOnboardingException(
                    'This does not look like a Google service account key - it is missing "private_key" or "client_email". Please upload the exact JSON file Google Cloud Console gave you.'
                );
            }

            GAMJKSBuilder.ConversionResult buildResult =
                GAMJKSBuilder.build(serviceAccountJsonText);

            if (!buildResult.success) {
                throw new GAMOnboardingException(buildResult.errorMessage);
            }

            result.jksBase64 = buildResult.jksBase64;
            result.keystorePassword = buildResult.keystorePassword;
            result.alias = buildResult.alias;
            result.issuer = buildResult.issuer;
            result.success = true;

        } catch (Exception e) {

            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }


    public class GAMOnboardingException extends Exception {
    }
}
