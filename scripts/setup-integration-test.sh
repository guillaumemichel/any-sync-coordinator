#!/bin/bash
set -e

echo "==================================================="
echo "  Setting up Space Creation Whitelist Integration Test"
echo "==================================================="
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "ERROR: Please run this from the any-sync-dockercompose directory"
    exit 1
fi

echo "Step 1: Creating repos directory..."
mkdir -p repos

echo "Step 2: Cloning modified coordinator..."
if [ -d "repos/any-sync-coordinator" ]; then
    echo "  Coordinator already exists, pulling latest..."
    cd repos/any-sync-coordinator
    git fetch origin
    git checkout claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF
    git pull origin claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF
    cd ../..
else
    cd repos
    git clone -b claude/whitelist-space-creation-011CV5mqHBV8W12jCRaNj8LF \
        https://github.com/guillaumemichel/any-sync-coordinator.git
    cd ..
fi

echo "Step 3: Creating docker-compose.override.yml..."
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

echo "Step 4: Creating .env.override..."
cat > .env.override << 'EOF'
# Whitelist configuration - initially disabled for baseline testing
ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=false
ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=[]
EOF

echo "Step 5: Updating coordinator config template..."
# Check if spaceCreation section already exists
if grep -q "spaceCreation:" docker-generateconfig/etc/coordinator.yml; then
    echo "  Config template already updated"
else
    cat >> docker-generateconfig/etc/coordinator.yml << 'EOF'

spaceCreation:
    restrictCreation: %ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT%
    allowedCreators: %ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS%
EOF
    echo "  Config template updated"
fi

echo "Step 6: Creating test helper script..."
cat > test-whitelist.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_services() {
    log_info "Checking if any-sync-coordinator is running..."
    if docker compose ps any-sync-coordinator | grep -q "Up"; then
        log_success "Coordinator is running"
        return 0
    else
        log_error "Coordinator is not running"
        return 1
    fi
}

get_account_identities() {
    log_info "Fetching account identities from MongoDB..."
    MONGO_CONTAINER=$(docker ps -q -f name=mongo-1)
    if [ -z "$MONGO_CONTAINER" ]; then
        log_error "MongoDB container not found"
        return 1
    fi
    docker exec -it $MONGO_CONTAINER mongosh \
        "mongodb://mongo-1:27001/coordinator?replicaSet=rs0" \
        --quiet \
        --eval "db.spaces.find({}, {identity: 1, _id: 1}).forEach(doc => print(doc._id + ' -> ' + doc.identity))"
}

check_whitelist_config() {
    log_info "Current whitelist configuration:"
    cat etc/any-sync-coordinator/config.yml | grep -A 3 "spaceCreation:" || log_warning "Config not found"
}

set_whitelist() {
    local restrict=$1
    local identities=$2
    log_info "Setting whitelist configuration..."
    log_info "  Restrict Creation: $restrict"
    log_info "  Allowed Creators: $identities"
    cat > .env.override << EOF
ANY_SYNC_COORDINATOR_SPACE_CREATION_RESTRICT=$restrict
ANY_SYNC_COORDINATOR_SPACE_CREATION_ALLOWED_CREATORS=$identities
EOF
    log_success "Configuration updated in .env.override"
    log_warning "You must restart services: make down && rm -rf etc/ storage/ && make start"
}

show_menu() {
    echo ""
    echo "=========================================="
    echo "  Space Creation Whitelist Test Helper"
    echo "=========================================="
    echo ""
    echo "1. Check services status"
    echo "2. View current whitelist configuration"
    echo "3. Get account identities from MongoDB"
    echo "4. Disable whitelist (allow all)"
    echo "5. Enable whitelist with custom identities"
    echo "6. Enable empty whitelist (block all)"
    echo "7. Watch coordinator logs"
    echo "8. Check for errors in logs"
    echo "9. Restart services with new config"
    echo "0. Exit"
    echo ""
}

main() {
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Run this from any-sync-dockercompose directory"
        exit 1
    fi

    while true; do
        show_menu
        read -p "Select option: " choice
        case $choice in
            1) check_services ;;
            2) check_whitelist_config ;;
            3) get_account_identities ;;
            4) set_whitelist "false" "[]" ;;
            5)
                echo "Enter account identities (comma-separated):"
                read -p "Identities: " identities
                json_array="["
                IFS=',' read -ra ADDR <<< "$identities"
                for i in "${!ADDR[@]}"; do
                    [ $i -gt 0 ] && json_array+=", "
                    json_array+="\"${ADDR[$i]}\""
                done
                json_array+="]"
                set_whitelist "true" "$json_array"
                ;;
            6) set_whitelist "true" "[]" ;;
            7) docker compose logs -f any-sync-coordinator ;;
            8) docker compose logs any-sync-coordinator | grep -i "error\|forbidden\|whitelist" | tail -20 ;;
            9) log_info "Restarting..."; make down; rm -rf etc/ storage/; make start ;;
            0) exit 0 ;;
            *) log_error "Invalid option" ;;
        esac
        echo ""; read -p "Press Enter to continue..."
    done
}

main
SCRIPT_EOF

chmod +x test-whitelist.sh

echo ""
echo "==================================================="
echo "  ✅ Setup Complete!"
echo "==================================================="
echo ""
echo "Next steps:"
echo "  1. Start the environment:       make start"
echo "  2. Use the test helper:         ./test-whitelist.sh"
echo "  3. Or read the full guide:      cat WHITELIST_INTEGRATION_TEST.md"
echo ""
echo "Files created:"
echo "  - repos/any-sync-coordinator/    (modified coordinator)"
echo "  - docker-compose.override.yml    (local build config)"
echo "  - .env.override                  (whitelist settings)"
echo "  - test-whitelist.sh              (test helper)"
echo ""
