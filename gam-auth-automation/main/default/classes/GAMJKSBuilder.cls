public with sharing class GAMJKSBuilder {

    /*
     * ================================================================
     * Pure-Apex replacement for the external Node.js/keytool-based
     * JKS conversion service. Everything here runs inside Salesforce
     * with zero external infrastructure, per the explicit "everything
     * in Salesforce, no Python/ngrok/custom services" requirement.
     *
     * Given a client's pasted Google service-account JSON, this:
     *   1. Extracts the PKCS8 private key and derives its RSA
     *      modulus/exponent.
     *   2. Builds a minimal self-signed X.509 certificate for that
     *      key pair (signed with the client's own private key via
     *      Crypto.sign, using a raw key Blob - never imported into
     *      Salesforce as a Certificate first).
     *   3. Encrypts the private key using Java's proprietary JKS
     *      key-protection algorithm and assembles the full binary JKS
     *      container, matching the format `keytool` produces.
     *
     * The resulting bytes are byte-for-byte compatible with a real
     * JKS file - validated against OpenJDK's keytool during
     * development (see .dev_jks_validation/, dev-time only, not
     * shipped).
     * ================================================================
     */

    private static final String HEX_CHARS = '0123456789abcdef';
    private static final Map<String, Integer> HEX_MAP = new Map<String, Integer>{
        '0' => 0, '1' => 1, '2' => 2, '3' => 3, '4' => 4,
        '5' => 5, '6' => 6, '7' => 7, '8' => 8, '9' => 9,
        'a' => 10, 'b' => 11, 'c' => 12, 'd' => 13, 'e' => 14, 'f' => 15
    };

    public class ConversionResult {
        public Boolean success;
        public String jksBase64;
        public String keystorePassword;
        public String alias;
        public String issuer;
        public String errorMessage;
    }

    public class JKSBuildException extends Exception {}

    // ============================================================
    // Public entry point
    // ============================================================

    public static ConversionResult build(String serviceAccountJsonText) {
        ConversionResult result = new ConversionResult();
        result.success = false;

        try {
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(serviceAccountJsonText);

            String privateKeyPem = (String) parsed.get('private_key');
            String clientEmail = (String) parsed.get('client_email');

            if (String.isBlank(privateKeyPem) || String.isBlank(clientEmail)) {
                throw new JKSBuildException(
                    'This does not look like a Google service account key - missing "private_key" or "client_email".'
                );
            }

            String pkcs8Hex = pemToHex(privateKeyPem);

            Map<String, String> rsaComponents = extractRsaModulusAndExponent(pkcs8Hex);
            String modulusHex = rsaComponents.get('modulus');
            String exponentHex = rsaComponents.get('exponent');

            String certHex = buildSelfSignedCertificate(
                pkcs8Hex, modulusHex, exponentHex, clientEmail
            );

            String password = generatePassword(24);
            String alias = 'gam_service_account_key';

            Blob jksBlob = buildJksContainer(password, alias, pkcs8Hex, certHex);

            result.jksBase64 = EncodingUtil.base64Encode(jksBlob);
            result.keystorePassword = password;
            result.alias = alias;
            result.issuer = clientEmail;
            result.success = true;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    // ============================================================
    // PEM / hex / byte-level helpers
    // (Apex Blobs are not directly indexable, so all binary
    // construction is done on lowercase hex strings, 2 chars/byte)
    // ============================================================

    private static String pemToHex(String pem) {
        String cleaned = pem
            .replace('-----BEGIN PRIVATE KEY-----', '')
            .replace('-----END PRIVATE KEY-----', '')
            .replace('\r', '')
            .replace('\n', '')
            .trim();
        Blob der = EncodingUtil.base64Decode(cleaned);
        return EncodingUtil.convertToHex(der);
    }

    private static Integer hexByteAt(String hex, Integer bytePos) {
        Integer i = bytePos * 2;
        Integer hi = HEX_MAP.get(hex.substring(i, i + 1));
        Integer lo = HEX_MAP.get(hex.substring(i + 1, i + 2));
        return hi * 16 + lo;
    }

    private static String byteToHex(Integer v) {
        Integer b = v & 255;
        return '' + HEX_CHARS.substring(b / 16, b / 16 + 1) + HEX_CHARS.substring(Math.mod(b, 16), Math.mod(b, 16) + 1);
    }

    private static String intToHex32(Long v) {
        // big-endian, 4 bytes
        Long uv = v & 4294967295L;
        String hex = '';
        for (Integer i = 3; i >= 0; i--) {
            Long shifted = (uv >> (i * 8)) & 255;
            hex += byteToHex(shifted.intValue());
        }
        return hex;
    }

    private static String longToHex64(Long v) {
        // big-endian, 8 bytes
        String high = intToHex32((v >> 32) & 4294967295L);
        String low = intToHex32(v & 4294967295L);
        return high + low;
    }

    private static String randomBytesHex(Integer numBytes) {
        List<String> parts = new List<String>();
        Integer remaining = numBytes;
        while (remaining > 0) {
            Integer chunk = Math.min(remaining, 4);
            Long r = (0L + Crypto.getRandomInteger()) & 4294967295L;
            String hex4 = intToHex32(r);
            parts.add(hex4.substring(0, chunk * 2));
            remaining -= chunk;
        }
        return String.join(parts, '');
    }

    private static String generatePassword(Integer length) {
        String charset = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
        String password = '';
        for (Integer i = 0; i < length; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), charset.length());
            password += charset.substring(idx, idx + 1);
        }
        return password;
    }

    // ASCII-only UTF-16BE encoding of a string (sufficient for our
    // generated passwords, which are restricted to ASCII charset).
    private static String asciiToUtf16BeHex(String s) {
        String hex = '';
        for (Integer i = 0; i < s.length(); i++) {
            Integer code = s.substring(i, i + 1).getChars()[0];
            hex += '00' + byteToHex(code);
        }
        return hex;
    }

    private static String writeUtfHex(String s) {
        Blob utf8 = Blob.valueOf(s);
        String contentHex = EncodingUtil.convertToHex(utf8);
        Integer len = contentHex.length() / 2;
        return intToHex32((0L + len)).substring(4) + contentHex; // 2-byte length prefix
    }

    private static String xorHex(String aHex, String bHex) {
        Integer len = aHex.length() / 2;
        List<String> outParts = new List<String>();
        for (Integer i = 0; i < len; i++) {
            Integer x = hexByteAt(aHex, i) ^ hexByteAt(bHex, i);
            outParts.add(byteToHex(x));
        }
        return String.join(outParts, '');
    }

    private static String sha1Hex(String dataHex) {
        Blob data = EncodingUtil.convertFromHex(dataHex);
        Blob digest = Crypto.generateDigest('SHA1', data);
        return EncodingUtil.convertToHex(digest);
    }

    // ============================================================
    // Minimal DER helpers
    // ============================================================

    private static String derLength(Integer n) {
        if (n < 128) {
            return byteToHex(n);
        }
        List<Integer> reversedBytes = new List<Integer>();
        Integer remaining = n;
        while (remaining > 0) {
            reversedBytes.add(Math.mod(remaining, 256));
            remaining = remaining / 256;
        }
        String hex = byteToHex(128 | reversedBytes.size());
        for (Integer i = reversedBytes.size() - 1; i >= 0; i--) {
            hex += byteToHex(reversedBytes[i]);
        }
        return hex;
    }

    private static String derTlv(Integer tag, String contentHex) {
        Integer len = contentHex.length() / 2;
        return byteToHex(tag) + derLength(len) + contentHex;
    }

    private static String derSequence(String contentHex) {
        return derTlv(48, contentHex);
    }

    private static String derSet(String contentHex) {
        return derTlv(49, contentHex);
    }

    private static String derInteger(String contentHex) {
        return derTlv(2, contentHex);
    }

    private static String derOctetString(String contentHex) {
        return derTlv(4, contentHex);
    }

    private static String derBitString(String contentHex) {
        return derTlv(3, '00' + contentHex); // 0 unused bits
    }

    private static String derUtf8String(String s) {
        return derTlv(12, EncodingUtil.convertToHex(Blob.valueOf(s)));
    }

    private static String derNull() {
        return byteToHex(5) + byteToHex(0);
    }

    private static String derOid(String dottedContentHex) {
        return derTlv(6, dottedContentHex);
    }

    // parses a TLV at byte offset `pos`, returns tag/length/valueStart/nextPos (all byte offsets)
    private static Map<String, Integer> parseTlv(String hex, Integer pos) {
        Integer tag = hexByteAt(hex, pos);
        Integer lenByte = hexByteAt(hex, pos + 1);
        Integer lenNumBytes;
        Integer length;
        if (lenByte < 128) {
            length = lenByte;
            lenNumBytes = 1;
        } else {
            Integer numBytes = lenByte - 128;
            length = 0;
            for (Integer i = 0; i < numBytes; i++) {
                length = length * 256 + hexByteAt(hex, pos + 2 + i);
            }
            lenNumBytes = 1 + numBytes;
        }
        Integer valueStart = pos + 1 + lenNumBytes;
        Integer nextPos = valueStart + length;
        Map<String, Integer> result = new Map<String, Integer>();
        result.put('tag', tag);
        result.put('length', length);
        result.put('valueStart', valueStart);
        result.put('nextPos', nextPos);
        return result;
    }

    private static String sliceHex(String hex, Integer startByte, Integer lengthBytes) {
        return hex.substring(startByte * 2, (startByte + lengthBytes) * 2);
    }

    // ============================================================
    // PKCS8 -> RSA modulus/exponent extraction
    // ============================================================

    private static Map<String, String> extractRsaModulusAndExponent(String pkcs8Hex) {
        Map<String, Integer> outerNode = parseTlv(pkcs8Hex, 0); // PrivateKeyInfo SEQUENCE
        Map<String, Integer> versionNode = parseTlv(pkcs8Hex, outerNode.get('valueStart'));
        Map<String, Integer> algIdNode = parseTlv(pkcs8Hex, versionNode.get('nextPos'));
        Map<String, Integer> privKeyOctetNode = parseTlv(pkcs8Hex, algIdNode.get('nextPos'));

        String rsaPrivateKeyHex = sliceHex(
            pkcs8Hex, privKeyOctetNode.get('valueStart'), privKeyOctetNode.get('length')
        );

        Map<String, Integer> rsaTop = parseTlv(rsaPrivateKeyHex, 0); // RSAPrivateKey SEQUENCE
        Map<String, Integer> rsaVersionNode = parseTlv(rsaPrivateKeyHex, rsaTop.get('valueStart'));
        Map<String, Integer> modulusNode = parseTlv(rsaPrivateKeyHex, rsaVersionNode.get('nextPos'));
        Map<String, Integer> exponentNode = parseTlv(rsaPrivateKeyHex, modulusNode.get('nextPos'));

        String modulusHex = sliceHex(rsaPrivateKeyHex, modulusNode.get('valueStart'), modulusNode.get('length'));
        String exponentHex = sliceHex(rsaPrivateKeyHex, exponentNode.get('valueStart'), exponentNode.get('length'));

        Map<String, String> result = new Map<String, String>();
        result.put('modulus', modulusHex);
        result.put('exponent', exponentHex);
        return result;
    }

    // ============================================================
    // Self-signed X.509 certificate construction
    // ============================================================

    private static String buildSelfSignedCertificate(
        String pkcs8Hex, String modulusHex, String exponentHex, String commonName
    ) {
        // rsaEncryption OID 1.2.840.113549.1.1.1
        String rsaEncryptionOidContent = '2a864886f70d0101 01'.replace(' ', '');
        // sha256WithRSAEncryption OID 1.2.840.113549.1.1.11
        String sha256RsaOidContent = '2a864886f70d0101 0b'.replace(' ', '');
        // commonName OID 2.5.4.3
        String cnOidContent = '550403';

        String algIdRsaEncryption = derSequence(derOid(rsaEncryptionOidContent) + derNull());
        String algIdSha256Rsa = derSequence(derOid(sha256RsaOidContent) + derNull());

        String rsaPublicKeyDer = derSequence(derInteger(modulusHex) + derInteger(exponentHex));
        String subjectPublicKeyInfo = derSequence(algIdRsaEncryption + derBitString(rsaPublicKeyDer));

        String nameDer = derSequence(
            derSet(derSequence(derOid(cnOidContent) + derUtf8String(commonName)))
        );

        Datetime notBefore = Datetime.now();
        Datetime notAfter = notBefore.addYears(10);
        String notBeforeUtc = formatUtcTime(notBefore);
        String notAfterUtc = formatUtcTime(notAfter);
        String validity = derSequence(
            derTlv(23, EncodingUtil.convertToHex(Blob.valueOf(notBeforeUtc))) +
            derTlv(23, EncodingUtil.convertToHex(Blob.valueOf(notAfterUtc)))
        );

        String serialContent = randomBytesHex(8);
        // force MSB clear so the INTEGER is interpreted as positive
        Integer firstByte = hexByteAt(serialContent, 0) & 127;
        serialContent = byteToHex(firstByte) + serialContent.substring(2);
        String serialNumber = derInteger(serialContent);

        String tbsCertificate = derSequence(
            serialNumber +
            algIdSha256Rsa +
            nameDer +   // issuer
            validity +
            nameDer +   // subject (self-signed)
            subjectPublicKeyInfo
        );

        Blob tbsBlob = EncodingUtil.convertFromHex(tbsCertificate);
        Blob privateKeyBlob = EncodingUtil.convertFromHex(pkcs8Hex);
        Blob signatureBlob = Crypto.sign('RSA-SHA256', tbsBlob, privateKeyBlob);
        String signatureHex = EncodingUtil.convertToHex(signatureBlob);

        String certificateDer = derSequence(
            tbsCertificate +
            algIdSha256Rsa +
            derBitString(signatureHex)
        );

        return certificateDer;
    }

    private static String formatUtcTime(Datetime dt) {
        // UTCTime format: YYMMDDHHMMSSZ, always UTC
        Datetime utcDt = dt;
        String yy = String.valueOf(Math.mod(utcDt.yearGmt(), 100)).leftPad(2, '0');
        String mm = String.valueOf(utcDt.monthGmt()).leftPad(2, '0');
        String dd = String.valueOf(utcDt.dayGmt()).leftPad(2, '0');
        String hh = String.valueOf(utcDt.hourGmt()).leftPad(2, '0');
        String mi = String.valueOf(utcDt.minuteGmt()).leftPad(2, '0');
        String ss = String.valueOf(utcDt.secondGmt()).leftPad(2, '0');
        return yy + mm + dd + hh + mi + ss + 'Z';
    }

    // ============================================================
    // JKS container assembly (validated algorithm - see
    // .dev_jks_validation/jks_writer_prototype.py for the reference
    // implementation this was ported from and verified against)
    // ============================================================

    private static final String MAGIC_HEX = 'feedfeed';
    private static final String VERSION_HEX = '00000002';
    private static final String JAVASOFT_OID_CONTENT = '2b0601040 12a021101 01'.replace(' ', '');

    private static Blob buildJksContainer(
        String password, String alias, String pkcs8Hex, String certHex
    ) {
        String out = '';
        out += MAGIC_HEX;
        out += VERSION_HEX;
        out += intToHex32(1); // entry count

        out += intToHex32(1); // tag = private key entry
        out += writeUtfHex(alias);
        out += longToHex64(Datetime.now().getTime());

        String encryptedKeyInfoHex = encryptPrivateKey(password, pkcs8Hex);
        out += intToHex32((0L + encryptedKeyInfoHex.length() / 2));
        out += encryptedKeyInfoHex;

        out += intToHex32(1); // cert chain length
        out += writeUtfHex('X.509');
        out += intToHex32((0L + certHex.length() / 2));
        out += certHex;

        String passwordUtf16BeHex = asciiToUtf16BeHex(password);
        String integrityInputHex = passwordUtf16BeHex + EncodingUtil.convertToHex(Blob.valueOf('Mighty Aphrodite')) + out;
        String integrityHex = sha1Hex(integrityInputHex);

        out += integrityHex;

        return EncodingUtil.convertFromHex(out);
    }

    private static String encryptPrivateKey(String password, String pkcs8Hex) {
        String saltHex = randomBytesHex(20);
        String passwordUtf16BeHex = asciiToUtf16BeHex(password);

        Integer keyLenBytes = pkcs8Hex.length() / 2;
        String keystreamHex = '';
        String digestInputHex = saltHex;

        while (keystreamHex.length() / 2 < keyLenBytes) {
            digestInputHex = sha1Hex(passwordUtf16BeHex + digestInputHex);
            keystreamHex += digestInputHex;
        }
        keystreamHex = keystreamHex.substring(0, keyLenBytes * 2);

        String encryptedKeyHex = xorHex(pkcs8Hex, keystreamHex);
        String checksumHex = sha1Hex(passwordUtf16BeHex + pkcs8Hex);

        String blobHex = saltHex + encryptedKeyHex + checksumHex;

        String algorithmIdentifier = derSequence(derOid(JAVASOFT_OID_CONTENT));
        String encryptedPrivateKeyInfo = derSequence(
            algorithmIdentifier + derOctetString(blobHex)
        );

        return encryptedPrivateKeyInfo;
    }
}
