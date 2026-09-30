public with sharing class ApexMinimalZip {

    /*
     * ================================================================
     * A minimal ZIP file writer for Apex, used to package metadata for
     * an in-org Metadata API deployment (see GAMOnboardingProvisioningService).
     *
     * Apex has no native compression/deflate API, so every entry is
     * written using ZIP's "Stored" method (method 0, no compression) -
     * this is fully valid per the ZIP spec and accepted by Salesforce's
     * Metadata API deploy() call, it just means slightly larger
     * payloads (fine for the small XML files we deploy here).
     *
     * All binary construction is done on lowercase hex strings, since
     * Apex Blobs are not directly indexable (see GAMJKSBuilder for the
     * same pattern, used and validated there first).
     * ================================================================
     */

    private static final String HEX_CHARS = '0123456789abcdef';

    public class ZipEntry {
        public String path;
        public String content;
    }

    // Standard reflected CRC-32 table (polynomial 0xEDB88320)
    private static List<Long> crcTable;

    private static void ensureCrcTable() {
        if (crcTable != null) {
            return;
        }
        crcTable = new List<Long>();
        for (Integer i = 0; i < 256; i++) {
            Long c = (0L + i);
            for (Integer j = 0; j < 8; j++) {
                if ((c & 1L) == 1L) {
                    c = (c >>> 1) ^ 3988292384L; // 0xEDB88320
                } else {
                    c = c >>> 1;
                }
            }
            crcTable.add(c);
        }
    }

    private static Long crc32(Blob data) {
        ensureCrcTable();
        String hex = EncodingUtil.convertToHex(data);
        Integer len = hex.length() / 2;
        Long crc = 4294967295L; // 0xFFFFFFFF
        for (Integer i = 0; i < len; i++) {
            Long b = (0L + hexByteAt(hex, i));
            Integer tableIndex = ((crc ^ b) & 255L).intValue();
            crc = crcTable[tableIndex] ^ (crc >>> 8);
        }
        return crc ^ 4294967295L;
    }

    private static Integer hexByteAt(String hex, Integer bytePos) {
        Integer i = bytePos * 2;
        return hexNibble(hex.substring(i, i + 1)) * 16 + hexNibble(hex.substring(i + 1, i + 2));
    }

    private static Integer hexNibble(String c) {
        Integer v = HEX_CHARS.indexOf(c.toLowerCase());
        return v;
    }

    private static String byteToHex(Integer v) {
        Integer b = v & 255;
        return '' + HEX_CHARS.substring(b / 16, b / 16 + 1) + HEX_CHARS.substring(Math.mod(b, 16), Math.mod(b, 16) + 1);
    }

    private static String uint16LEHex(Integer v) {
        Integer x = v & 65535;
        return byteToHex(Math.mod(x, 256)) + byteToHex(x / 256);
    }

    private static String uint32LEHex(Long v) {
        Long x = v & 4294967295L;
        String hex = '';
        for (Integer i = 0; i < 4; i++) {
            Long b = (x >> (i * 8)) & 255;
            hex += byteToHex(b.intValue());
        }
        return hex;
    }

    public static Blob build(List<ZipEntry> entries) {
        String localHeadersHex = '';
        String centralDirHex = '';
        Integer offset = 0;

        for (ZipEntry entryItem : entries) {
            Blob contentBlob = Blob.valueOf(entryItem.content);
            String contentHex = EncodingUtil.convertToHex(contentBlob);
            Integer size = contentHex.length() / 2;
            Long crc = crc32(contentBlob);

            Blob nameBlob = Blob.valueOf(entryItem.path);
            String nameHex = EncodingUtil.convertToHex(nameBlob);
            Integer nameLen = nameHex.length() / 2;

            String localHeader =
                '504b0304' +          // local file header signature
                '1400' +               // version needed
                '0000' +               // flags
                '0000' +               // compression method = 0 (stored)
                '0000' + '2100' +      // mod time / mod date (arbitrary fixed values)
                uint32LEHex(crc) +
                uint32LEHex((0L + size)) + // compressed size
                uint32LEHex((0L + size)) + // uncompressed size
                uint16LEHex(nameLen) +
                '0000' +               // extra field length
                nameHex +
                contentHex;

            localHeadersHex += localHeader;

            String centralHeader =
                '504b0102' +           // central directory header signature
                '1400' +               // version made by
                '1400' +               // version needed
                '0000' +               // flags
                '0000' +               // compression method
                '0000' + '2100' +      // mod time / mod date
                uint32LEHex(crc) +
                uint32LEHex((0L + size)) +
                uint32LEHex((0L + size)) +
                uint16LEHex(nameLen) +
                '0000' +               // extra field length
                '0000' +               // comment length
                '0000' +               // disk number start
                '0000' +               // internal attrs
                '00000000' +           // external attrs
                uint32LEHex((0L + offset)) + // relative offset of local header
                nameHex;

            centralDirHex += centralHeader;

            offset += (localHeader.length() / 2);
        }

        Integer centralDirSize = centralDirHex.length() / 2;
        Integer centralDirOffset = offset;

        String endOfCentralDir =
            '504b0506' +               // end of central dir signature
            '0000' +                   // disk number
            '0000' +                   // disk with central dir
            uint16LEHex(entries.size()) + // entries on this disk
            uint16LEHex(entries.size()) + // total entries
            uint32LEHex((0L + centralDirSize)) +
            uint32LEHex((0L + centralDirOffset)) +
            '0000';                    // comment length

        String fullZipHex = localHeadersHex + centralDirHex + endOfCentralDir;

        return EncodingUtil.convertFromHex(fullZipHex);
    }
}
