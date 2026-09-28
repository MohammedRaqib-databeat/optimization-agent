public with sharing class GAMOnboardingProvisioningService {

    /*
     * ================================================================
     * PHASE 2 of GAM onboarding automation: once the client has
     * imported their JKS keystore via Setup (the one unavoidable
     * manual step), this class deploys the ExternalCredential,
     * NamedCredential, and PermissionSet metadata needed to actually
     * use it - entirely from Apex, using the running admin's own
     * session to call this org's own Metadata API (no external
     * service, no stored session/credentials, nothing persisted
     * beyond the metadata itself).
     *
     * This mirrors, exactly, the metadata that was hand-built once in
     * Setup and confirmed working for real GAM API authentication
     * (see PROJECT_HANDOFF.md §6) - retrieved from the org as the
     * canonical template, then parameterized per-client (only the
     * `iss` JWT claim, which must be the client's own service account
     * email, changes between clients).
     * ================================================================
     */

    private static final String EXTERNAL_CREDENTIAL_NAME = 'GAM_API_Cred_OAuth';
    private static final String NAMED_CREDENTIAL_NAME = 'GAM_API';
    private static final String PERMISSION_SET_NAME = 'GAM_API_Access';
    private static final String PRINCIPAL_NAME = 'GAM_Integration_Principal_OAuth';
    private static final String CERTIFICATE_NAME = 'gam_service_account_key';
    private static final String METADATA_API_VERSION = '62.0';

    public class ProvisioningResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String deployId;
        @AuraEnabled public String status;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String networkCode;
        @AuraEnabled public String networkDisplayName;
    }

    public class ProvisioningException extends Exception {}

    // ============================================================
    // Public entry points (called from the gamOnboardingWizard LWC)
    // ============================================================

    @AuraEnabled
    public static ProvisioningResult startProvisioning(String clientEmail) {
        ProvisioningResult result = new ProvisioningResult();
        result.success = false;

        try {
            if (String.isBlank(clientEmail)) {
                throw new ProvisioningException('Missing client service account email.');
            }

            String zipBase64 = buildDeploymentZipBase64(clientEmail);
            String deployId = submitDeploy(zipBase64);

            result.deployId = deployId;
            result.success = true;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    @AuraEnabled
    public static ProvisioningResult checkStatus(String deployId) {
        ProvisioningResult result = new ProvisioningResult();
        result.deployId = deployId;

        try {
            Map<String, String> statusInfo = checkDeployStatus(deployId);
            result.status = statusInfo.get('status');
            result.success = (statusInfo.get('status') == 'Succeeded');

            if (statusInfo.get('status') == 'Failed') {
                result.errorMessage = statusInfo.get('errorMessage');
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // Assigns the permission set (native DML, no metadata deploy
    // needed) so the running admin can actually use the External
    // Credential principal once it exists. Called after a successful
    // deploy, as its own Apex round trip - a callout (like the
    // network-code discovery step that follows) can't happen in the
    // same transaction as this DML per platform governor rules.
    @AuraEnabled
    public static ProvisioningResult assignPermissionSet() {
        ProvisioningResult result = new ProvisioningResult();

        try {
            PermissionSet ps = [
                SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME LIMIT 1
            ];

            Id currentUserId = UserInfo.getUserId();

            List<PermissionSetAssignment> existing = [
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :currentUserId AND PermissionSetId = :ps.Id
            ];

            if (existing.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = currentUserId,
                    PermissionSetId = ps.Id
                );
            }

            result.success = true;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // Auto-detects and persists the client's GAM network code, once
    // the permission set has been assigned and the Named Credential
    // is actually usable. Thin @AuraEnabled wrapper so the LWC only
    // needs to talk to this one class for the whole Phase 2 flow.
    @AuraEnabled
    public static ProvisioningResult discoverNetwork() {
        ProvisioningResult result = new ProvisioningResult();

        GAMNetworkServiceClient.GAMConnectionResult discovery =
            GAMNetworkServiceClient.discoverNetwork();

        result.success = discovery.success;
        result.networkCode = discovery.networkCode;
        result.networkDisplayName = discovery.networkDisplayName;
        result.errorMessage = discovery.errorMessage;

        return result;
    }

    // ============================================================
    // Metadata XML templates (parameterized per-client only where
    // needed - the iss claim and the label are the only client-
    // specific values; everything else is a fixed, already-verified
    // working configuration)
    // ============================================================

    private static String buildExternalCredentialXml(String clientEmail) {
        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<ExternalCredential xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<authenticationProtocol>Oauth</authenticationProtocol>' +
                '<externalCredentialParameters>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>Oauth</parameterName>' +
                    '<parameterType>AuthProtocolVariant</parameterType>' +
                    '<parameterValue>JwtBearer</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>Scope</parameterName>' +
                    '<parameterType>AuthParameter</parameterType>' +
                    '<parameterValue>https://www.googleapis.com/auth/dfp</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>AuthProviderUrl</parameterName>' +
                    '<parameterType>AuthProviderUrl</parameterType>' +
                    '<parameterValue>https://oauth2.googleapis.com/token</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<certificate>' + CERTIFICATE_NAME + '</certificate>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>SigningCertificate</parameterName>' +
                    '<parameterType>SigningCertificate</parameterType>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Issuer</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>iss</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>' + escapeXml(clientEmail) + '</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Audience</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>aud</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>&quot;https://oauth2.googleapis.com/token&quot;</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Expiration Time</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>exp</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>{!Text(FLOOR((NOW() - DATETIMEVALUE( &quot;1970-01-01 00:00:00&quot; )) * 86400 + 3600))}</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Algorithm</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>alg</parameterName>' +
                    '<parameterType>JwtHeaderClaim</parameterType>' +
                    '<parameterValue>RS256</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Type</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>typ</parameterName>' +
                    '<parameterType>JwtHeaderClaim</parameterType>' +
                    '<parameterValue>JWT</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Issued At</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>iat</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>{!Text(FLOOR((NOW() - DATETIMEVALUE( &quot;1970-01-01 00:00:00&quot; )) * 86400))}</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Not Before</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>nbf</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>{!Text(FLOOR((NOW() - DATETIMEVALUE( &quot;1970-01-01 00:00:00&quot; )) * 86400))}</parameterValue>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<parameterGroup>' + PRINCIPAL_NAME + '</parameterGroup>' +
                    '<parameterName>' + PRINCIPAL_NAME + '</parameterName>' +
                    '<parameterType>NamedPrincipal</parameterType>' +
                    '<sequenceNumber>1</sequenceNumber>' +
                '</externalCredentialParameters>' +
                '<externalCredentialParameters>' +
                    '<description>Scope</description>' +
                    '<parameterGroup>DefaultGroup</parameterGroup>' +
                    '<parameterName>scope</parameterName>' +
                    '<parameterType>JwtBodyClaim</parameterType>' +
                    '<parameterValue>https://www.googleapis.com/auth/dfp</parameterValue>' +
                '</externalCredentialParameters>' +
                '<label>GAM API Cred OAuth</label>' +
            '</ExternalCredential>';
    }

    private static String buildNamedCredentialXml() {
        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<allowMergeFieldsInBody>false</allowMergeFieldsInBody>' +
                '<allowMergeFieldsInHeader>false</allowMergeFieldsInHeader>' +
                '<calloutStatus>Enabled</calloutStatus>' +
                '<generateAuthorizationHeader>true</generateAuthorizationHeader>' +
                '<label>GAM API</label>' +
                '<namedCredentialParameters>' +
                    '<parameterName>Url</parameterName>' +
                    '<parameterType>Url</parameterType>' +
                    '<parameterValue>https://ads.google.com/apis/ads/publisher/v202608</parameterValue>' +
                '</namedCredentialParameters>' +
                '<namedCredentialParameters>' +
                    '<externalCredential>' + EXTERNAL_CREDENTIAL_NAME + '</externalCredential>' +
                    '<parameterName>ExternalCredential</parameterName>' +
                    '<parameterType>Authentication</parameterType>' +
                '</namedCredentialParameters>' +
                '<namedCredentialParameters>' +
                    '<certificate>' + CERTIFICATE_NAME + '</certificate>' +
                    '<parameterName>ClientCertificate</parameterName>' +
                    '<parameterType>ClientCertificate</parameterType>' +
                '</namedCredentialParameters>' +
                '<namedCredentialType>SecuredEndpoint</namedCredentialType>' +
            '</NamedCredential>';
    }

    private static String buildPermissionSetXml() {
        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<description>Grants access to the GAM API Named Credential for Optimization Agent callouts</description>' +
                '<externalCredentialPrincipalAccesses>' +
                    '<enabled>true</enabled>' +
                    '<externalCredentialPrincipal>' + EXTERNAL_CREDENTIAL_NAME + '-' + PRINCIPAL_NAME + '</externalCredentialPrincipal>' +
                '</externalCredentialPrincipalAccesses>' +
                '<hasActivationRequired>false</hasActivationRequired>' +
                '<label>GAM API Access</label>' +
            '</PermissionSet>';
    }

    private static String buildPackageXml() {
        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' +
                '<types>' +
                    '<members>' + EXTERNAL_CREDENTIAL_NAME + '</members>' +
                    '<name>ExternalCredential</name>' +
                '</types>' +
                '<types>' +
                    '<members>' + NAMED_CREDENTIAL_NAME + '</members>' +
                    '<name>NamedCredential</name>' +
                '</types>' +
                '<types>' +
                    '<members>' + PERMISSION_SET_NAME + '</members>' +
                    '<name>PermissionSet</name>' +
                '</types>' +
                '<version>' + METADATA_API_VERSION + '</version>' +
            '</Package>';
    }

    private static String escapeXml(String s) {
        return s
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&apos;');
    }

    // ============================================================
    // ZIP assembly + Metadata API deploy (raw SOAP callout using the
    // running admin's own session - validated during development to
    // work reliably from an @AuraEnabled/LWC-invoked Apex context)
    // ============================================================

    private static String buildDeploymentZipBase64(String clientEmail) {
        List<ApexMinimalZip.ZipEntry> entries = new List<ApexMinimalZip.ZipEntry>();

        ApexMinimalZip.ZipEntry pkg = new ApexMinimalZip.ZipEntry();
        pkg.path = 'package.xml';
        pkg.content = buildPackageXml();
        entries.add(pkg);

        ApexMinimalZip.ZipEntry ec = new ApexMinimalZip.ZipEntry();
        ec.path = 'externalCredentials/' + EXTERNAL_CREDENTIAL_NAME + '.externalCredential';
        ec.content = buildExternalCredentialXml(clientEmail);
        entries.add(ec);

        ApexMinimalZip.ZipEntry nc = new ApexMinimalZip.ZipEntry();
        nc.path = 'namedCredentials/' + NAMED_CREDENTIAL_NAME + '.namedCredential';
        nc.content = buildNamedCredentialXml();
        entries.add(nc);

        ApexMinimalZip.ZipEntry ps = new ApexMinimalZip.ZipEntry();
        ps.path = 'permissionsets/' + PERMISSION_SET_NAME + '.permissionset';
        ps.content = buildPermissionSetXml();
        entries.add(ps);

        Blob zipBlob = ApexMinimalZip.build(entries);
        return EncodingUtil.base64Encode(zipBlob);
    }

    private static String metadataEndpoint() {
        return 'https://' + URL.getOrgDomainUrl().getHost() + '/services/Soap/m/' + METADATA_API_VERSION;
    }

    private static String submitDeploy(String zipBase64) {
        String sessionId = UserInfo.getSessionId();

        String soapBody =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
                '<soapenv:Header><met:SessionHeader><met:sessionId>' + sessionId + '</met:sessionId></met:SessionHeader></soapenv:Header>' +
                '<soapenv:Body>' +
                    '<met:deploy>' +
                        '<met:ZipFile>' + zipBase64 + '</met:ZipFile>' +
                        '<met:DeployOptions>' +
                            '<met:singlePackage>true</met:singlePackage>' +
                            '<met:rollbackOnError>true</met:rollbackOnError>' +
                        '</met:DeployOptions>' +
                    '</met:deploy>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(metadataEndpoint());
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', '""');
        req.setBody(soapBody);
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new ProvisioningException(
                'Metadata deploy submission failed (HTTP ' + res.getStatusCode() + '): ' + extractFaultString(res.getBody())
            );
        }

        String body = res.getBody();
        Integer idStart = body.indexOf('<id>');
        Integer idEnd = body.indexOf('</id>');

        if (idStart == -1 || idEnd == -1) {
            throw new ProvisioningException('Deploy submitted but no deploy ID was returned: ' + body.substring(0, Math.min(500, body.length())));
        }

        return body.substring(idStart + 4, idEnd);
    }

    private static Map<String, String> checkDeployStatus(String deployId) {
        String sessionId = UserInfo.getSessionId();

        String soapBody =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="http://soap.sforce.com/2006/04/metadata">' +
                '<soapenv:Header><met:SessionHeader><met:sessionId>' + sessionId + '</met:sessionId></met:SessionHeader></soapenv:Header>' +
                '<soapenv:Body>' +
                    '<met:checkDeployStatus>' +
                        '<met:asyncProcessId>' + deployId + '</met:asyncProcessId>' +
                        '<met:includeDetails>true</met:includeDetails>' +
                    '</met:checkDeployStatus>' +
                '</soapenv:Body>' +
            '</soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(metadataEndpoint());
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', '""');
        req.setBody(soapBody);
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        String body = res.getBody();

        if (res.getStatusCode() != 200) {
            throw new ProvisioningException('Status check failed (HTTP ' + res.getStatusCode() + '): ' + extractFaultString(body));
        }

        Map<String, String> result = new Map<String, String>();
        result.put('status', extractTag(body, 'status'));

        Boolean success = extractTag(body, 'success') == 'true';
        Boolean done = extractTag(body, 'done') == 'true';

        if (done && !success) {
            result.put('status', 'Failed');
            result.put('errorMessage', extractAllComponentFailureMessages(body));
        } else if (done && success) {
            result.put('status', 'Succeeded');
        } else {
            result.put('status', 'InProgress');
        }

        return result;
    }

    private static String extractTag(String xml, String tagName) {
        String openTag = '<' + tagName + '>';
        String closeTag = '</' + tagName + '>';
        Integer start = xml.indexOf(openTag);
        if (start == -1) {
            return null;
        }
        Integer closeIdx = xml.indexOf(closeTag, start);
        if (closeIdx == -1) {
            return null;
        }
        return xml.substring(start + openTag.length(), closeIdx);
    }

    private static String extractAllComponentFailureMessages(String xml) {
        List<String> messages = new List<String>();
        Integer searchFrom = 0;

        while (true) {
            Integer failureStart = xml.indexOf('<componentFailures>', searchFrom);
            if (failureStart == -1) {
                break;
            }
            Integer failureEnd = xml.indexOf('</componentFailures>', failureStart);
            if (failureEnd == -1) {
                break;
            }
            String failureBlock = xml.substring(failureStart, failureEnd);
            String problem = extractTag(failureBlock, 'problem');
            String fileName = extractTag(failureBlock, 'fileName');
            if (problem != null) {
                messages.add((fileName != null ? fileName + ': ' : '') + problem);
            }
            searchFrom = failureEnd + 1;
        }

        return messages.isEmpty() ? 'Deploy failed with no component-level detail returned.' : String.join(messages, ' | ');
    }

    private static String extractFaultString(String xml) {
        String faultString = extractTag(xml, 'faultstring');
        return faultString != null ? faultString : xml.substring(0, Math.min(500, xml.length()));
    }
}
