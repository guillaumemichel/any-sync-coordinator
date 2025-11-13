# Testing the Space Creation Whitelist Feature

This document provides instructions for testing the space creation whitelist feature at different levels.

## Quick Links

- **[Integration Test Guide](docs/INTEGRATION_TEST_GUIDE.md)** - Complete end-to-end testing with any-sync-dockercompose
- **[Unit Tests](#unit-tests)** - Running the unit tests
- **[Setup Scripts](#integration-test-setup)** - Automated setup for integration testing

## Unit Tests

The whitelist feature includes comprehensive unit tests in `coordinator/coordinator_test.go`.

### Running Unit Tests

```bash
# Run all whitelist tests
go test -v -run TestCoordinator_SpaceSign_Whitelist ./coordinator

# Run all coordinator tests
go test -v ./coordinator

# Run all tests in the project
go test ./...
```

### Test Coverage

The unit tests cover:

1. **Whitelist Disabled** - All users can create spaces (backward compatibility)
2. **Whitelisted User** - Can create spaces when whitelist is enabled
3. **Non-whitelisted User** - Gets `ErrForbidden` when attempting to create
4. **Multiple Whitelisted Users** - All whitelisted users can create
5. **Empty Whitelist** - Complete lockdown, no one can create

## Integration Testing

Integration testing validates the feature works end-to-end with:
- Real any-sync infrastructure (MongoDB, Redis, etc.)
- Docker Compose orchestration
- Anytype client applications

### Prerequisites

- Docker and Docker Compose
- Anytype client (desktop or mobile)
- `any-sync-dockercompose` repository

### Quick Setup

```bash
# 1. Clone any-sync-dockercompose
git clone https://github.com/anyproto/any-sync-dockercompose.git
cd any-sync-dockercompose

# 2. Download and run the setup script
curl -O https://raw.githubusercontent.com/guillaumemichel/any-sync-coordinator/claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF/scripts/setup-integration-test.sh
chmod +x setup-integration-test.sh
./setup-integration-test.sh

# 3. Start the environment
make start

# 4. Run the test helper
./test-whitelist.sh
```

### Manual Setup

If you prefer to set up manually:

```bash
# 1. In any-sync-dockercompose directory
mkdir -p repos
git clone -b claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF \
  https://github.com/guillaumemichel/any-sync-coordinator.git \
  repos/any-sync-coordinator

# 2. Create docker-compose.override.yml
cat > docker-compose.override.yml << 'EOF'
services:
  any-sync-coordinator:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        REPO_DIR: repos/any-sync-coordinator/
    image: any-sync-coordinator:local

  any-sync-coordinator_bootstrap:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        REPO_DIR: repos/any-sync-coordinator/
    image: any-sync-coordinator:local
EOF

# 3. Create .env.override
cat > .env.override << 'EOF'
ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=false
ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=[]
EOF

# 4. Update coordinator config template
cat >> docker-generateconfig/etc/coordinator.yml << 'EOF'

spaceCreation:
    restrictCreation: %ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT%
    allowedCreators: %ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS%
EOF

# 5. Start services
make start
```

### Running Integration Tests

See the **[Integration Test Guide](docs/INTEGRATION_TEST_GUIDE.md)** for:
- Complete 4-phase test procedure
- How to extract account identities
- Configuring the whitelist
- Expected results and verification
- Troubleshooting tips

### Interactive Test Helper

Use the `test-whitelist.sh` script for easier testing:

```bash
# Download the script
curl -o test-whitelist.sh https://raw.githubusercontent.com/guillaumemichel/any-sync-coordinator/claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF/scripts/test-whitelist.sh
chmod +x test-whitelist.sh

# Run it (must be in any-sync-dockercompose directory)
./test-whitelist.sh
```

The script provides an interactive menu to:
- Check service status
- View/update whitelist configuration
- Extract account identities from MongoDB
- Watch coordinator logs
- Restart services with new configuration

## Configuration

### YAML Configuration

```yaml
spaceCreation:
  restrictCreation: false  # Set to true to enable whitelisting
  allowedCreators:         # List of account identities (NOT peer IDs)
    # - "A4KzkKEuB86mP3sc4Vz6MjWEJvYZh2fGCFivGUDBPVhFDZaR"  # user1
    # - "A5AbCdEfGhIjKlMnOpQrStUvWxYz1234567890AbCdEfGhIj"  # user2
```

### Environment Variables (for docker-compose)

```bash
ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=false
ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=[]
```

### Important Notes

1. **Identity Format**: Use account identities (start with `A`), NOT peer IDs (start with `12D3Koo`)
2. **Account-Level**: Whitelist is by account, not device - whitelisted users can create from any device
3. **Backward Compatible**: Default `restrictCreation: false` maintains existing behavior
4. **Read Access**: Whitelist only affects NEW space creation; all users can read/sync existing spaces

## Test Phases

### Phase 1: Baseline (Whitelist Disabled)
**Objective**: Verify normal operation

- Create 2 test accounts
- Both should create spaces successfully
- Extract account identities for next phases

### Phase 2: Whitelist Enforcement
**Objective**: Verify only whitelisted accounts can create

- Enable whitelist with Account 1 only
- Account 1 creates space ✓
- Account 2 gets forbidden error ✗

### Phase 3: Multiple Accounts
**Objective**: Verify multiple whitelisted accounts work

- Whitelist both Account 1 and Account 2
- Both can create spaces ✓
- Create Account 3 (not whitelisted) ✗

### Phase 4: Lockdown
**Objective**: Verify empty whitelist blocks everyone

- Set empty whitelist with `restrictCreation: true`
- No one can create spaces ✗

## Verification Checklist

- [ ] Unit tests pass
- [ ] Whitelist disabled allows all users
- [ ] Whitelisted user can create spaces
- [ ] Non-whitelisted user gets `ErrForbidden`
- [ ] Multiple whitelisted accounts work
- [ ] Empty whitelist blocks everyone
- [ ] Existing spaces remain accessible to all users
- [ ] Account identities are extracted correctly (format: `A...`)
- [ ] Configuration regenerates properly in docker-compose

## Extracting Account Identities

### Method 1: MongoDB Query

```bash
docker exec -it $(docker ps -q -f name=mongo-1) mongosh \
  "mongodb://mongo-1:27001/coordinator?replicaSet=rs0" \
  --eval "db.spaces.find({}, {_id: 1, identity: 1}).pretty()"
```

### Method 2: Coordinator Logs

```bash
docker compose logs any-sync-coordinator | grep -i "identity"
```

### Method 3: Test Helper Script

```bash
./test-whitelist.sh
# Select option 3: "Get account identities from MongoDB"
```

## Troubleshooting

### Unit Tests Failing

```bash
# Clean and rebuild
go clean -testcache
go test -v ./coordinator
```

### Integration Test Issues

**Services won't start:**
```bash
docker compose logs
make down
docker system prune -a
rm -rf etc/ storage/
make start
```

**Configuration not taking effect:**
```bash
# Ensure you regenerated configs
cat etc/any-sync-coordinator/config.yml | grep -A 3 "spaceCreation"
# If missing or wrong, regenerate:
rm -rf etc/ storage/
make start
```

**Can't find account identities:**
```bash
# Verify spaces were created
docker exec -it $(docker ps -q -f name=mongo-1) mongosh \
  "mongodb://mongo-1:27001/coordinator?replicaSet=rs0" \
  --eval "db.spaces.find().count()"
```

## Support & Resources

- **Detailed Test Guide**: [docs/INTEGRATION_TEST_GUIDE.md](docs/INTEGRATION_TEST_GUIDE.md)
- **Setup Script**: [scripts/setup-integration-test.sh](scripts/setup-integration-test.sh)
- **Test Helper**: [scripts/test-whitelist.sh](scripts/test-whitelist.sh)
- **Source Code**:
  - Configuration: [config/config.go](config/config.go)
  - Implementation: [coordinator/coordinator.go](coordinator/coordinator.go)
  - Tests: [coordinator/coordinator_test.go](coordinator/coordinator_test.go)

## Architecture Overview

```
┌─────────────┐
│   Anytype   │
│   Client    │
└──────┬──────┘
       │ SpaceSign RPC (with account identity)
       ↓
┌─────────────────────────────────────┐
│  any-sync-coordinator               │
│                                     │
│  SpaceSign() function:              │
│  1. Extract accountPubKey from ctx  │
│  2. Get account identity:           │
│     accountIdentity =               │
│       accountPubKey.Account()       │ ← Account-level (not device)
│  3. Check whitelist:                │
│     if restrictCreation:            │
│       if identity ∉ allowedCreators:│
│         return ErrForbidden ✗       │
│  4. Proceed with space creation ✓   │
└─────────────────────────────────────┘
```

## Next Steps After Testing

1. **Production Deployment**: Build and deploy coordinator image
2. **Monitoring**: Add metrics for whitelist rejections
3. **Administration**: Create tools to manage the whitelist
4. **Documentation**: Update production docs with whitelist procedures
