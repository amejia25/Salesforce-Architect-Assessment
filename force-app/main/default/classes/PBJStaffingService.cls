public with sharing class PBJStaffingService {

    // DTO the LWC will consume
    public class QuarterlyContractHoursDTO {
        @AuraEnabled public String  quarter;   // e.g. "2025Q2"
        @AuraEnabled public Decimal cnaHours;
        @AuraEnabled public Decimal lpnHours;
        @AuraEnabled public Decimal rnHours;
    }

    // Helper: normalize CCN to 6 digits (e.g. "65316" -> "065316")
    private static String normalizeCcn(String rawCcn) {
        if (String.isBlank(rawCcn)) {
            return null;
        }

        String ccn = rawCcn.trim();

        // Keep only digits (safety in case something weird is in the field)
        String digits = '';
        for (Integer i = 0; i < ccn.length(); i++) {
            String ch = ccn.substring(i, i + 1);
            if (ch >= '0' && ch <= '9') {
                digits += ch;
            }
        }

        if (String.isBlank(digits)) {
            return null;
        }

        // Left-pad to 6 characters
        while (digits.length() < 6) {
            digits = '0' + digits;
        }

        return digits;
    }

    @AuraEnabled(cacheable=true)
    public static List<QuarterlyContractHoursDTO> getQuarterlyContractHours(Id accountId) {
        List<QuarterlyContractHoursDTO> result = new List<QuarterlyContractHoursDTO>();

        if (accountId == null) {
            return result;
        }

        // 1) Look up the Account + CCN
        Account acc = [
            SELECT CMS_Certification_Number__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        // Normalize CCN to 6 digits
        String ccn = normalizeCcn(acc.CMS_Certification_Number__c);
        if (String.isBlank(ccn)) {
            // No usable CCN => nothing to query
            return result;
        }

        // 2) Call the CMS PBJ API via Named Credential
        //    Base URL (in Named Credential CMS_PBJ_API):
        //    https://data.cms.gov/data-api/v1/dataset/7e0d53ba-8f02-4c66-98a5-14a1c997c50d
        //
        // Here we call /data and filter by PROVNUM
        String path = '/data'
            + '?filter[PROVNUM]=' + EncodingUtil.urlEncode(ccn, 'UTF-8')
            + '&page[size]=5000';

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:CMS_PBJ_API' + path);
        req.setTimeout(20000);

        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            System.debug('PBJ callout failed: ' + e.getMessage());
            return result;
        }

        if (res.getStatusCode() != 200) {
            System.debug('PBJ API non-200: ' + res.getStatusCode() + ' body=' + res.getBody());
            return result;
        }

        // 3) Parse JSON. The CMS "data-api" returns a JSON array for /data
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            System.debug('Failed to parse PBJ JSON: ' + e.getMessage());
            return result;
        }

        List<Object> rows;

        if (parsed instanceof List<Object>) {
            rows = (List<Object>) parsed;
        } else if (parsed instanceof Map<String, Object>) {
            // In case CMS ever wraps in { data: [...] }
            Map<String, Object> m = (Map<String, Object>) parsed;
            rows = (List<Object>) m.get('data');
        } else {
            rows = new List<Object>();
        }

        if (rows == null || rows.isEmpty()) {
            return result;
        }

        // 4) Aggregate by quarter
        Map<String, QuarterlyContractHoursDTO> byQuarter =
            new Map<String, QuarterlyContractHoursDTO>();

        for (Object rowObj : rows) {
            if (!(rowObj instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> row = (Map<String, Object>) rowObj;

            // Field names per PBJ dataset
            String qtr = (String) row.get('CY_Qtr');
            if (String.isBlank(qtr)) {
                continue;
            }

            QuarterlyContractHoursDTO dto = byQuarter.get(qtr);
            if (dto == null) {
                dto = new QuarterlyContractHoursDTO();
                dto.quarter  = qtr;
                dto.cnaHours = 0;
                dto.lpnHours = 0;
                dto.rnHours  = 0;
                byQuarter.put(qtr, dto);
            }

            dto.cnaHours += toDecimal(row.get('Hrs_CNA_ctr'));
            dto.lpnHours += toDecimal(row.get('Hrs_LPN_ctr'));
            dto.rnHours  += toDecimal(row.get('Hrs_RN_ctr'));
        }

        // 5) Turn map into a sorted list of DTOs
        List<String> quarters = new List<String>(byQuarter.keySet());
        quarters.sort(); // string sort is fine: 2023Q1, 2023Q2, etc.

        for (String q : quarters) {
            result.add(byQuarter.get(q));
        }

        return result;
    }

    // Helper to safely convert numeric-looking values into Decimal
    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
        }

        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            System.debug('Could not parse decimal from value: ' + value);
            return 0;
        }
    }
}
