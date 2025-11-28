public with sharing class AccountProximityService {

    // DTO exposed to LWC
    public class NearbyAccountDTO {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  city;
        @AuraEnabled public String  state;
        @AuraEnabled public Decimal distanceMiles;
    }

    @AuraEnabled(cacheable=true)
    public static List<NearbyAccountDTO> findNearbyFacilities(Id accountId, Decimal radiusMiles) {

        List<NearbyAccountDTO> results = new List<NearbyAccountDTO>();

        if (accountId == null) {
            return results;
        }

        // Default radius if not provided or invalid
        if (radiusMiles == null || radiusMiles <= 0) {
            radiusMiles = 50; // default 50 miles
        }

        // 1) Get the “center” account with its coordinates
        Account center = [
            SELECT Facility_Latitude__c, Facility_Longitude__c, Type
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (center.Facility_Latitude__c == null || center.Facility_Longitude__c == null) {
            // No coordinates on this facility, nothing we can do
            return results;
        }

        Double centerLat  = Double.valueOf(String.valueOf(center.Facility_Latitude__c));
        Double centerLong = Double.valueOf(String.valueOf(center.Facility_Longitude__c));

        // 2) Get all other facility accounts that have coordinates
        List<Account> candidates = [
            SELECT Id, Name, BillingCity, BillingState,
                   Facility_Latitude__c, Facility_Longitude__c, Type
            FROM Account
            WHERE Facility_Latitude__c  != null
              AND Facility_Longitude__c != null
              AND Id != :accountId
              AND (Type = null OR Type != 'Chain')
        ];

        for (Account acc : candidates) {
            Double lat = Double.valueOf(String.valueOf(acc.Facility_Latitude__c));
            Double lon = Double.valueOf(String.valueOf(acc.Facility_Longitude__c));

            Double d = distanceMiles(centerLat, centerLong, lat, lon);

            if (d <= radiusMiles) {
                NearbyAccountDTO dto = new NearbyAccountDTO();
                dto.id            = acc.Id;
                dto.name          = acc.Name;
                dto.city          = acc.BillingCity;
                dto.state         = acc.BillingState;
                dto.distanceMiles = Decimal.valueOf(String.valueOf(d)).setScale(1); // 1 decimal place
                results.add(dto);
            }
        }

        // 3) Sort by distance ascending
        sortByDistance(results);

        return results;
    }

    // Haversine distance between two lat/long points
    private static Double distanceMiles(Double lat1, Double lon1,
                                        Double lat2, Double lon2) {

        Double R = 3958.8; // Earth radius in miles

        Double latRad1 = toRadians(lat1);
        Double latRad2 = toRadians(lat2);
        Double dLat    = toRadians(lat2 - lat1);
        Double dLon    = toRadians(lon2 - lon1);

        Double sinDLat = Math.sin(dLat / 2);
        Double sinDLon = Math.sin(dLon / 2);

        Double a = sinDLat * sinDLat
                 + Math.cos(latRad1) * Math.cos(latRad2)
                 * sinDLon * sinDLon;

        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c;
    }

    // Degrees → radians (couldnt use math.radians for some reason)
    private static Double toRadians(Double degrees) {
        if (degrees == null) {
            return 0;
        }
        Double pi = 3.14159265358979323846;
        return degrees * pi / 180.0;
    }

    // Manual selection sort by distanceMiles ascending
    private static void sortByDistance(List<NearbyAccountDTO> items) {
        Integer n = items.size();
        for (Integer i = 0; i < n; i++) {
            Integer minIndex = i;
            for (Integer j = i + 1; j < n; j++) {
                if (items.get(j).distanceMiles < items.get(minIndex).distanceMiles) {
                    minIndex = j;
                }
            }
            if (minIndex != i) {
                NearbyAccountDTO tmp = items.get(i);
                items.set(i, items.get(minIndex));
                items.set(minIndex, tmp);
            }
        }
    }
}