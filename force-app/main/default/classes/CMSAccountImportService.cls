public with sharing class CMSAccountImportService {

    // Main import method
    public static void loadFacilities() {
        // 1. Load the CSV from the static resource
        StaticResource sr = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'CMS_NursingHomes'
            LIMIT 1
        ];

        String csv = sr.Body.toString();
        List<String> lines = csv.split('\n');

        if (lines.isEmpty()) {
            System.debug('No lines found in CSV.');
            return;
        }

        // 2. Parse header row
        String headerLine = cleanLineEnd(lines[0]);
        List<String> headerFields = parseCsvLine(headerLine);

        // Map column name -> index
        Map<String, Integer> headerIndex = new Map<String, Integer>();
        for (Integer i = 0; i < headerFields.size(); i++) {
            String colName = headerFields[i] != null ? headerFields[i].trim() : null;
            if (!String.isBlank(colName)) {
                headerIndex.put(colName, i);
            }
        }

        System.debug('Header columns found: ' + headerIndex.keySet());

        // Sanity check: make sure Provider Name column exists
        if (!headerIndex.containsKey('Provider Name')) {
            System.debug('ERROR: "Provider Name" column not found. Headers were: ' + headerIndex.keySet());
            return;
        }

        // States we care about
        Set<String> allowedStates = new Set<String>{ 'AZ', 'NV', 'UT', 'CO' };

        List<Account> toInsert = new List<Account>();
        Integer totalInserted = 0;

        // 3. Loop over data rows
        for (Integer i = 1; i < lines.size(); i++) {
            String rawLine = lines[i];
            if (String.isBlank(rawLine)) {
                continue;
            }

            String line = cleanLineEnd(rawLine);
            List<String> cols = parseCsvLine(line);

            // State filter
            String state = getFieldValue(cols, headerIndex, 'State');
            if (String.isBlank(state) || !allowedStates.contains(state)) {
                continue; // skip rows outside the 4 states
            }

            // Provider Name -> Account.Name
            String providerName = getFieldValue(cols, headerIndex, 'Provider Name');
            if (String.isBlank(providerName)) {
                System.debug('Row ' + i + ' has blank Provider Name. Skipping. Row: ' + line);
                continue; // do NOT insert accounts with no name
            }

            Account acc = new Account();
            acc.Name = providerName;

            // Address fields
            acc.BillingStreet     = getFieldValue(cols, headerIndex, 'Provider Address');
            acc.BillingCity       = getFieldValue(cols, headerIndex, 'City/Town');

            // Use code fields because State & Country Picklists are enabled
            acc.BillingCountryCode = 'US';
            acc.BillingStateCode   = state; // 'AZ', 'NV', 'UT', 'CO'

            acc.BillingPostalCode = getFieldValue(cols, headerIndex, 'ZIP Code');

            // Phone
            String phone = getFieldValue(cols, headerIndex, 'Telephone Number');
            if (!String.isBlank(phone)) {
                acc.Phone = phone;
            }

            // Custom CMS fields
            acc.CMS_Certification_Number__c = getFieldValue(cols, headerIndex, 'CMS Certification Number (CCN)');
            acc.Chain_Name__c               = getFieldValue(cols, headerIndex, 'Chain Name');

            // Nurse hours field
            String nurseHoursStr = getFieldValue(cols, headerIndex, 'Nurse Staffing Hrs Per Resident Per Day');
            if (!String.isBlank(nurseHoursStr)) {
                try {
                    acc.Nurse_Staffing_Hrs_Per_Resident_Per_Day__c = Decimal.valueOf(nurseHoursStr);
                } catch (Exception e) {
                    System.debug('Could not parse nurse hours on line ' + i + ': ' +
                                 nurseHoursStr + ' -> ' + e.getMessage());
                }
            }

            // Latitude / Longitude into simple number fields
            String latStr = getFieldValue(cols, headerIndex, 'Latitude');
            String lonStr = getFieldValue(cols, headerIndex, 'Longitude');

            if (!String.isBlank(latStr)) {
                try {
                    acc.Facility_Latitude__c = Decimal.valueOf(latStr);
                } catch (Exception e) {
                    System.debug('Could not parse latitude on line ' + i + ': ' +
                                 latStr + ' -> ' + e.getMessage());
                }
            }

            if (!String.isBlank(lonStr)) {
                try {
                    acc.Facility_Longitude__c = Decimal.valueOf(lonStr);
                } catch (Exception e) {
                    System.debug('Could not parse longitude on line ' + i + ': ' +
                                 lonStr + ' -> ' + e.getMessage());
                }
            }

            toInsert.add(acc);

            // Insert in batches of 200
            if (toInsert.size() == 200) {
                insert toInsert;
                totalInserted += toInsert.size();
                toInsert.clear();
            }
        }

        // Insert any remaining
        if (!toInsert.isEmpty()) {
            insert toInsert;
            totalInserted += toInsert.size();
        }

        System.debug('Finished loading facilities. Total inserted: ' + totalInserted);
    }

    // --- Helper: remove trailing \r if present (Windows line endings) ---
    private static String cleanLineEnd(String line) {
        if (line != null && line.endsWith('\r')) {
            return line.substring(0, line.length() - 1);
        }
        return line;
    }

    // --- Helper: safely get a field by column name ---
    private static String getFieldValue(List<String> row, Map<String, Integer> headerIndex, String columnName) {
        Integer idx = headerIndex.get(columnName);
        if (idx == null) {
            return null;
        }
        if (idx < 0 || idx >= row.size()) {
            return null;
        }
        String value = row[idx];
        return value != null ? value.trim() : null;
    }

    // --- Core CSV parser that respects quotes and commas inside quotes ---
    private static List<String> parseCsvLine(String line) {
        List<String> fields = new List<String>();
        if (line == null) {
            return fields;
        }

        Boolean inQuotes = false;
        String current = '';
        Integer len = line.length();

        for (Integer i = 0; i < len; i++) {
            String ch = line.substring(i, i + 1);

            if (ch == '"') {
                if (inQuotes) {
                    Boolean isEscapedQuote =
                        (i + 1 < len) && line.substring(i + 1, i + 2) == '"';
                    if (isEscapedQuote) {
                        current += '"';
                        i++; // skip the next quote
                    } else {
                        inQuotes = false; // closing quote
                    }
                } else {
                    inQuotes = true; // starting quoted section
                }
            } else if (ch == ',' && !inQuotes) {
                fields.add(current);
                current = '';
            } else {
                current += ch;
            }
        }

        // Add the last field
        fields.add(current);

        return fields;
    }
}