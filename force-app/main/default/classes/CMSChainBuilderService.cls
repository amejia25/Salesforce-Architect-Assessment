public with sharing class CMSChainBuilderService {

    // Entry point to run all Step 2 logic in order
    public static void runStep2() {
        System.debug('=== Step 2: Starting chain parent build ===');
        createParentChains();
        mapFacilitiesToChains();
        updateChainCounts();
        System.debug('=== Step 2: Completed successfully ===');
    }

    /**
     * 1) Create parent "Chain" Accounts, one per unique Chain_Name__c
     *    from facility Accounts in AZ, NV, UT, CO.
     *    Parents have:
     *      - Name = Chain_Name__c
     *      - Type = 'Chain'
     */
    public static void createParentChains() {
        // Get all facility accounts that have a chain name
        List<Account> facilities = [
            SELECT Id, Name, Chain_Name__c
            FROM Account
            WHERE Chain_Name__c != null
        ];

        // Collect unique chain names from facilities
        Set<String> chainNames = new Set<String>();
        for (Account fac : facilities) {
            String chainName = fac.Chain_Name__c != null ? fac.Chain_Name__c.trim() : null;
            if (!String.isBlank(chainName)) {
                chainNames.add(chainName);
            }
        }

        if (chainNames.isEmpty()) {
            System.debug('No facilities with Chain_Name__c found. Nothing to do.');
            return;
        }

        // Find any chain parents that already exist so it doesnt create duplicates
        Map<String, Account> existingParentsByName = new Map<String, Account>();
        for (Account parent : [
            SELECT Id, Name
            FROM Account
            WHERE Type = 'Chain'
                  AND Name IN :chainNames
        ]) {
            existingParentsByName.put(parent.Name, parent);
        }

        // Create parent accounts for chain names that don't have one yet
        List<Account> parentsToInsert = new List<Account>();
        for (String chainName : chainNames) {
            if (!existingParentsByName.containsKey(chainName)) {
                Account parent = new Account();
                parent.Name = chainName;
                parent.Type = 'Chain';
                parentsToInsert.add(parent);
            }
        }

        if (!parentsToInsert.isEmpty()) {
            insert parentsToInsert;
            System.debug('Created ' + parentsToInsert.size() + ' new chain parent accounts.');
        } else {
            System.debug('No new chain parents to create. All chain names already have parents.');
        }
    }

    /**
     * 2) Map facility Accounts to their parent chain Accounts
     *    by setting Account.ParentId based on Chain_Name__c.
     */
    public static void mapFacilitiesToChains() {
        // Get all chain parent accounts
        Map<String, Id> parentIdByChainName = new Map<String, Id>();
        for (Account parent : [
            SELECT Id, Name
            FROM Account
            WHERE Type = 'Chain'
        ]) {
            String nameKey = parent.Name != null ? parent.Name.trim() : null;
            if (!String.isBlank(nameKey)) {
                parentIdByChainName.put(nameKey, parent.Id);
            }
        }

        if (parentIdByChainName.isEmpty()) {
            System.debug('No chain parents found. Did you run createParentChains()?');
            return;
        }

        // Get all facility accounts that have a chain name
        List<Account> facilities = [
            SELECT Id, Name, Chain_Name__c, ParentId
            FROM Account
            WHERE Chain_Name__c != null
        ];

        List<Account> facilitiesToUpdate = new List<Account>();

        for (Account fac : facilities) {
            String chainName = fac.Chain_Name__c != null ? fac.Chain_Name__c.trim() : null;
            if (String.isBlank(chainName)) {
                continue;
            }

            Id parentId = parentIdByChainName.get(chainName);
            if (parentId == null) {
                // Chain parent not found for this name – log and skip
                System.debug('No parent chain account found for chain name: ' + chainName);
                continue;
            }

            // Only update if ParentId is different or null
            if (fac.ParentId != parentId) {
                fac.ParentId = parentId;
                facilitiesToUpdate.add(fac);
            }
        }

        if (!facilitiesToUpdate.isEmpty()) {
            update facilitiesToUpdate;
            System.debug('Updated ' + facilitiesToUpdate.size() + ' facilities with ParentId.');
        } else {
            System.debug('No facilities needed ParentId updates.');
        }
    }

    /**
     * 3) Update Number_of_Facilities__c on each chain parent Account
     *    to reflect how many child Accounts it has.
     */
    public static void updateChainCounts() {
        // First, zero out counts on all chain parents
        List<Account> chainParents = [
            SELECT Id, Number_of_Facilities__c
            FROM Account
            WHERE Type = 'Chain'
        ];

        if (chainParents.isEmpty()) {
            System.debug('No chain parents found when updating counts.');
            return;
        }

        for (Account parent : chainParents) {
            parent.Number_of_Facilities__c = 0;
        }

        // Aggregate child counts by ParentId
        List<AggregateResult> childCounts = [
            SELECT ParentId pId, COUNT(Id) c
            FROM Account
            WHERE ParentId != null
            GROUP BY ParentId
        ];

        // Map parentId -> count
        Map<Id, Integer> countByParentId = new Map<Id, Integer>();
        for (AggregateResult ar : childCounts) {
            Id pId = (Id) ar.get('pId');
            Integer c = (Integer) ar.get('c');
            countByParentId.put(pId, c);
        }

        // Apply counts to chain parents
        for (Account parent : chainParents) {
            Integer countVal = countByParentId.get(parent.Id);
            if (countVal != null) {
                parent.Number_of_Facilities__c = countVal;
            } else {
                parent.Number_of_Facilities__c = 0;
            }
        }

        update chainParents;
        System.debug('Updated Number_of_Facilities__c for ' + chainParents.size() + ' chain parents.');
    }

    // Helper: remove trailing \r if present (Windows line endings)
    private static String cleanLineEnd(String line) {
        if (line != null && line.endsWith('\r')) {
            return line.substring(0, line.length() - 1);
        }
        return line;
    }

    // Helper: safely get a field by column name
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

    // Core CSV parser for if we ever want to reuse Step 1 logic
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
