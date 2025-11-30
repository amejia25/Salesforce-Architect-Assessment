trigger AccountSelfAssignmentLimit on Account (before insert, before update) {

    // Collect accounts that are being self-assigned
    List<Account> selfAssignedThisTxn = new List<Account>();

    for (Account acc : Trigger.new) {
        Account oldAcc = Trigger.isUpdate ? Trigger.oldMap.get(acc.Id) : null;

        // Owner is the current user
        Boolean ownerNowSelf = acc.OwnerId == UserInfo.getUserId();

        // Owner changed in this transaction (or it's a new record)
        Boolean ownerChanged = Trigger.isInsert ||
            (oldAcc != null && acc.OwnerId != oldAcc.OwnerId);

        // Reason is currently filled in
        Boolean reasonNowHasValue = !String.isBlank(acc.Self_Assignment_Reason__c);

        // Reason became non-blank in this transaction
        Boolean reasonBecameNonBlank = Trigger.isInsert ||
            (oldAcc != null &&
             String.isBlank(oldAcc.Self_Assignment_Reason__c) &&
             !String.isBlank(acc.Self_Assignment_Reason__c));

        // We treat it as a self-assignment event if:
        // - owner is the current user
        // - reason is filled
        // - AND either the owner changed, or the reason is being newly set
        if (ownerNowSelf && reasonNowHasValue && (ownerChanged || reasonBecameNonBlank)) {
            selfAssignedThisTxn.add(acc);
        }
    }

    // If nothing is being self-assigned, we're done
    if (selfAssignedThisTxn.isEmpty()) {
        return;
    }

    // Collect IDs from this transaction so we don't double-count them in the query
    Set<Id> txnIds = new Set<Id>();
    for (Account a : selfAssignedThisTxn) {
        if (a.Id != null) {
            txnIds.add(a.Id);
        }
    }

    // Count existing self-assigned accounts owned by this user
    Integer existingCount = [
        SELECT COUNT()
        FROM Account
        WHERE OwnerId = :UserInfo.getUserId()
          AND Self_Assignment_Reason__c != null
          AND Id NOT IN :txnIds
    ];

    Integer totalAfterThisChange = existingCount + selfAssignedThisTxn.size();

    // Enforce max 3 rule
    if (totalAfterThisChange > 3) {
        for (Account acc : selfAssignedThisTxn) {
            acc.addError(
                'You cannot hold more than 3 self-assigned accounts at a time. ' +
                'This change would bring you to ' + totalAfterThisChange +
                ' self-assigned account(s). Please reassign one before taking another.'
            );
        }
    }
}