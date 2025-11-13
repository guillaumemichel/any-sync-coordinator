#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if services are running
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

# Function to get account identities from MongoDB
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

# Function to check current whitelist configuration
check_whitelist_config() {
    log_info "Current whitelist configuration:"
    cat etc/any-sync-coordinator/config.yml | grep -A 3 "spaceCreation:" || log_warning "Config file not found or spaceCreation section missing"
}

# Function to set whitelist configuration
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
    log_warning "You must restart services for changes to take effect:"
    echo "  make down && rm -rf etc/ storage/ && make start"
}

# Function to watch coordinator logs
watch_logs() {
    log_info "Watching coordinator logs (press Ctrl+C to stop)..."
    docker compose logs -f any-sync-coordinator
}

# Function to search for errors in logs
check_errors() {
    log_info "Checking coordinator logs for errors..."
    docker compose logs any-sync-coordinator | grep -i "error\|forbidden\|whitelist" | tail -20
}

# Main menu
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

# Main loop
main() {
    if [ ! -f "docker-compose.yml" ]; then
        log_error "docker-compose.yml not found. Please run this script from the any-sync-dockercompose directory."
        exit 1
    fi

    while true; do
        show_menu
        read -p "Select an option: " choice

        case $choice in
            1)
                check_services
                ;;
            2)
                check_whitelist_config
                ;;
            3)
                get_account_identities
                ;;
            4)
                set_whitelist "false" "[]"
                ;;
            5)
                echo ""
                echo "Enter account identities (comma-separated):"
                echo "Example: A4KzkKEuB86mP3sc4Vz6MjWEJvYZh2fGCFivGUDBPVhFDZaR,A5AbCdEfGhIjKlMnOpQrStUvWxYz1234567890AbCdEfGhIj"
                read -p "Identities: " identities

                # Convert to JSON array format
                json_array="["
                IFS=',' read -ra ADDR <<< "$identities"
                for i in "${!ADDR[@]}"; do
                    if [ $i -gt 0 ]; then
                        json_array+=", "
                    fi
                    json_array+="\"${ADDR[$i]}\""
                done
                json_array+="]"

                set_whitelist "true" "$json_array"
                ;;
            6)
                set_whitelist "true" "[]"
                log_warning "Empty whitelist - NO ONE can create spaces!"
                ;;
            7)
                watch_logs
                ;;
            8)
                check_errors
                ;;
            9)
                log_info "Restarting services..."
                make down
                rm -rf etc/ storage/
                make start
                log_success "Services restarted"
                ;;
            0)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main
main
