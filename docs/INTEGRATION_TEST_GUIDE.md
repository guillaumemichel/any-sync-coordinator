# Space Creation Whitelist - Integration Testing Guide

This guide walks you through testing the space creation whitelist feature with the any-sync-dockercompose setup and Anytype clients.

## Prerequisites

- Docker and Docker Compose installed
- Any modified coordinator code in `repos/any-sync-coordinator/`
- Anytype desktop or mobile client for testing
- `jq` for JSON parsing (optional but recommended)

## Setup Overview

The integration test environment has been configured with:

1. **Modified Coordinator**: Local build with whitelist feature
2. **Configuration Template**: Updated to support `spaceCreation` section
3. **Environment Variables**: Configurable whitelist settings in `.env.override`

## Test Plan

### Phase 1: Baseline Test (Whitelist Disabled)

**Objective**: Verify normal operation without whitelist enforcement

1. **Start the environment with whitelist disabled:**
   ```bash
   cd /path/to/any-sync-dockercompose

   # Ensure whitelist is disabled
   cat > .env.override << 'EOF'
   ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=false
   ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=[]
   EOF

   # Start services
   make start
   ```

2. **Configure Anytype client:**
   - In Anytype settings, go to "Network"
   - Upload the network configuration from `etc/client.yml`
   - Restart Anytype

3. **Create Account 1 (will be whitelisted later):**
   - Create a new account in Anytype
   - Create a space (should succeed)
   - **Extract Account Identity** (see below)

4. **Create Account 2 (will NOT be whitelisted):**
   - Create another account in Anytype
   - Create a space (should succeed)
   - **Extract Account Identity** (see below)

**Expected Results:**
- ✅ Both accounts can create spaces
- ✅ No `ErrForbidden` errors in coordinator logs

### Phase 2: Whitelist Enforcement Test

**Objective**: Verify only whitelisted accounts can create spaces

1. **Get the account identities from Phase 1**

   **Method A: From MongoDB** (if you have access):
   ```bash
   # Connect to MongoDB
   docker exec -it <mongo-container> mongosh coordinator_test

   # Query spaces to see account identities
   db.spaces.find({}, {identity: 1, _id: 1}).pretty()
   ```

   **Method B: From coordinator logs**:
   ```bash
   # Watch coordinator logs when creating a space
   docker compose logs -f any-sync-coordinator | grep "account"
   ```

   Account identities look like: `A4KzkKEuB86mP3sc4Vz6MjWEJvYZh2fGCFivGUDBPVhFDZaR`

2. **Stop the environment:**
   ```bash
   make stop
   ```

3. **Enable whitelist with Account 1 only:**
   ```bash
   # Replace with actual Account 1 identity
   ACCOUNT1_IDENTITY="A4KzkKEuB86mP3sc4Vz6MjWEJvYZh2fGCFivGUDBPVhFDZaR"

   cat > .env.override << EOF
   ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=true
   ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=["${ACCOUNT1_IDENTITY}"]
   EOF
   ```

4. **Regenerate configuration:**
   ```bash
   # Clean existing configs
   rm -rf etc/ storage/

   # Restart with new configuration
   make start
   ```

5. **Test Account 1 (whitelisted):**
   - Log in with Account 1 in Anytype
   - Try to create a new space
   - **Expected**: ✅ Space creation succeeds

6. **Test Account 2 (not whitelisted):**
   - Log out and log in with Account 2
   - Try to create a new space
   - **Expected**: ❌ Space creation fails with error

7. **Verify coordinator logs:**
   ```bash
   docker compose logs any-sync-coordinator | grep -i "forbidden\|whitelist"
   ```

   **Expected log output for Account 2**:
   ```
   "error": "forbidden"
   ```

### Phase 3: Multiple Whitelisted Accounts

**Objective**: Verify multiple accounts can be whitelisted

1. **Update whitelist to include both accounts:**
   ```bash
   ACCOUNT1_IDENTITY="A4KzkKEuB86mP3sc4Vz6MjWEJvYZh2fGCFivGUDBPVhFDZaR"
   ACCOUNT2_IDENTITY="A5AbCdEfGhIjKlMnOpQrStUvWxYz1234567890AbCdEfGhIj"

   cat > .env.override << EOF
   ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=true
   ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=["${ACCOUNT1_IDENTITY}", "${ACCOUNT2_IDENTITY}"]
   EOF

   # Regenerate and restart
   make restart
   ```

2. **Test both accounts:**
   - Test space creation with Account 1: ✅ Should succeed
   - Test space creation with Account 2: ✅ Should succeed
   - Create Account 3 (not in whitelist): ❌ Should fail

### Phase 4: Empty Whitelist (Lockdown)

**Objective**: Verify complete lockdown when whitelist is empty

1. **Set empty whitelist:**
   ```bash
   cat > .env.override << 'EOF'
   ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=true
   ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=[]
   EOF

   make restart
   ```

2. **Test any account:**
   - Try to create space with any account
   - **Expected**: ❌ All space creation attempts fail

## Extracting Account Identity

### Method 1: MongoDB Query

```bash
# Connect to MongoDB
docker exec -it $(docker ps -q -f name=mongo-1) mongosh "mongodb://mongo-1:27001/coordinator?replicaSet=rs0"

# List all spaces with account identities
db.spaces.find({}, {_id: 1, identity: 1}).pretty()
```

### Method 2: Coordinator Config After Space Creation

After a space is created, the account identity is logged:

```bash
docker compose logs any-sync-coordinator | grep "Identity"
```

### Method 3: From Client (if available)

Some Anytype clients may expose the account identity in debug mode or logs.

## Verification Checklist

- [ ] Phase 1: Both accounts can create spaces when whitelist is disabled
- [ ] Phase 2: Only whitelisted account can create spaces when enabled
- [ ] Phase 2: Non-whitelisted account gets forbidden error
- [ ] Phase 3: Multiple whitelisted accounts all work
- [ ] Phase 3: New non-whitelisted account fails
- [ ] Phase 4: Empty whitelist blocks everyone
- [ ] Existing spaces remain accessible in all phases (read/sync works)

## Important Notes

1. **Account vs Peer ID**: The whitelist uses **account-level identities** (format: `A...`), not peer IDs (format: `12D3Koo...`). This is correct - users should be whitelisted by account, not by device.

2. **Existing Spaces**: The whitelist only affects **new space creation**. Users can always read/sync existing spaces, even if they're not whitelisted.

3. **Configuration Regeneration**: After changing `.env.override`, you must regenerate configs:
   ```bash
   rm -rf etc/ storage/
   make start
   ```

4. **Logs Location**: Coordinator logs are crucial for debugging:
   ```bash
   docker compose logs -f any-sync-coordinator
   ```

## Troubleshooting

### Issue: Space creation fails even when whitelist is disabled

**Check**: Verify coordinator config:
```bash
cat etc/any-sync-coordinator/config.yml | grep -A 3 "spaceCreation"
```

Expected:
```yaml
spaceCreation:
  restrictCreation: false
  allowedCreators: []
```

### Issue: Can't extract account identity

**Solution**: Create a space and check MongoDB:
```bash
docker exec -it $(docker ps -q -f name=mongo-1) mongosh \
  "mongodb://mongo-1:27001/coordinator?replicaSet=rs0" \
  --eval "db.spaces.findOne()"
```

### Issue: Configuration changes not taking effect

**Solution**: Ensure you regenerated configs:
```bash
make down
rm -rf etc/ storage/
make start
```

## Test Results Template

```
# Whitelist Integration Test Results

Date: ___________
Tester: ___________

## Phase 1: Baseline (Whitelist Disabled)
- [ ] Account 1 created space: PASS/FAIL
- [ ] Account 2 created space: PASS/FAIL
- Account 1 Identity: _____________________
- Account 2 Identity: _____________________

## Phase 2: Whitelist Enforcement
- [ ] Account 1 (whitelisted) created space: PASS/FAIL
- [ ] Account 2 (not whitelisted) failed to create: PASS/FAIL
- [ ] Error message was "forbidden": PASS/FAIL

## Phase 3: Multiple Whitelisted Accounts
- [ ] Account 1 created space: PASS/FAIL
- [ ] Account 2 created space: PASS/FAIL
- [ ] Account 3 (new, not whitelisted) failed: PASS/FAIL

## Phase 4: Empty Whitelist Lockdown
- [ ] All accounts blocked from creating spaces: PASS/FAIL

## Overall Result: PASS/FAIL

Notes:
_________________________________________________
_________________________________________________
```

## Next Steps

After successful integration testing:

1. Document any issues or edge cases discovered
2. Consider adding metrics/monitoring for whitelist rejections
3. Create admin tools for managing the whitelist
4. Consider adding API endpoint to query whitelist status

