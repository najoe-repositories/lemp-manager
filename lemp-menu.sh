#!/usr/bin/env bash
#===============================================================================
# LEMP Stack Manager for Debian 12
# Save as: lemp-menu.sh
# Run with: sudo bash lemp-menu.sh
# Author : Najoe / Harimau99
# Repo: https://github.com/najoe-repositories
# Profile : https://github.com/harimau99/myprofile
#===============================================================================

# Exit on undefined variables only (not on errors - we handle those manually)
set -u

#-------------------------------------------------------------------------------
# COLORS
#-------------------------------------------------------------------------------
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
CYAN='\e[0;36m'
BOLD='\e[1m'
NC='\e[0m'

#-------------------------------------------------------------------------------
# LOG SYSTEM
#-------------------------------------------------------------------------------
declare -a LOG_BUFFER=()
LOG_MAX=100
LOG_HEIGHT=8

print_log() {
    local count=${#LOG_BUFFER[@]}
    local start=0
    
    if [[ $count -gt $LOG_HEIGHT ]]; then
        start=$((count - LOG_HEIGHT))
    fi
    
    echo ""
    echo -e "${CYAN}─────────────────────────── LOGS ───────────────────────────${NC}"
    
    if [[ $count -eq 0 ]]; then
        echo -e "  ${YELLOW}(No logs yet)${NC}"
    else
        for ((i=start; i<count; i++)); do
            echo -e "  ${LOG_BUFFER[$i]}"
        done
    fi
    
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
}

log() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    LOG_BUFFER+=("[$timestamp] $*")
    
    # Trim old logs
    if [[ ${#LOG_BUFFER[@]} -gt $LOG_MAX ]]; then
        LOG_BUFFER=("${LOG_BUFFER[@]:1}")
    fi
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_ok() {
    log "${GREEN}[OK]${NC} $*"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

log_cmd() {
    log "${CYAN}[CMD]${NC} $*"
}

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------
print_header() {
    clear
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║               LEMP STACK MANAGER (Debian 12)                   ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_menu() {
    print_header
    echo -e "  ${BOLD}System${NC}"
    echo -e "    ${GREEN}1)${NC} Update & clean system"
    echo ""
    echo -e "  ${BOLD}Install Packages${NC}"
    echo -e "    ${GREEN}2)${NC} Install PHP 8.3 + extensions"
    echo -e "    ${GREEN}3)${NC} Install MariaDB"
    echo -e "    ${GREEN}4)${NC} Install Nginx"
    echo ""
    echo -e "  ${BOLD}Service Control${NC}"
    echo -e "    ${GREEN}5)${NC} PHP-FPM (enable/disable)"
    echo -e "    ${GREEN}6)${NC} Nginx (enable/disable)"
    echo -e "    ${GREEN}7)${NC} MariaDB (enable/disable)"
    echo ""
    echo -e "    ${RED}0)${NC} Exit"
    echo ""
    print_log
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo -e "Please run: ${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
}

confirm() {
    local prompt="$1"
    local answer
    echo -ne "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

pause() {
    echo ""
    echo -ne "${CYAN}Press ENTER to continue...${NC}"
    read -r
}

#-------------------------------------------------------------------------------
# COMMAND EXECUTION
#-------------------------------------------------------------------------------
run_cmd() {
    local cmd="$1"
    local desc="${2:-$cmd}"
    
    log_cmd "$desc"
    
    local output
    local exit_code
    
    # Execute and capture output
    output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?
    
    # Log output lines (limit to avoid flooding)
    if [[ -n "$output" ]]; then
        local line_count=0
        while IFS= read -r line; do
            ((line_count++))
            if [[ $line_count -le 5 ]]; then
                log "  → $line"
            elif [[ $line_count -eq 6 ]]; then
                log "  → ... (output truncated)"
                break
            fi
        done <<< "$output"
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        log_ok "$desc completed"
        return 0
    else
        log_error "$desc failed (exit code: $exit_code)"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# INSTALLATION FUNCTIONS
#-------------------------------------------------------------------------------
do_update_system() {
    log_info "Starting system update..."
    
    run_cmd "apt-get update -qq" "Update package lists" || return 1
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq" "Upgrade packages" || return 1
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge -qq" "Remove unused packages" || return 1
    run_cmd "apt-get clean" "Clean apt cache" || return 1
    
    log_ok "System update completed!"
    return 0
}

do_install_php() {
    log_info "Starting PHP 8.3 installation..."
    
    # Prerequisites
    run_cmd "apt-get update -qq" "Update package lists" || return 1
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl lsb-release ca-certificates gnupg" "Install prerequisites" || return 1
    
    # Add Sury repository
    log_info "Adding PHP repository..."
    if [[ ! -f /usr/share/keyrings/sury-php.gpg ]]; then
        run_cmd "curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php.gpg" "Add GPG key" || return 1
    else
        log_info "GPG key already exists"
    fi
    
    local codename
    codename=$(lsb_release -sc)
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${codename} main" > /etc/apt/sources.list.d/sury-php.list
    log_ok "Repository added"
    
    run_cmd "apt-get update -qq" "Update with new repository" || return 1
    
    # Install PHP packages
    local php_packages=(
        php8.3
        php8.3-fpm
        php8.3-cli
        php8.3-common
        php8.3-mysql
        php8.3-curl
        php8.3-gd
        php8.3-mbstring
        php8.3-xml
        php8.3-zip
        php8.3-bcmath
        php8.3-intl
        php8.3-opcache
        php8.3-redis
        php8.3-memcached
        php8.3-imagick
        php8.3-soap
    )
    
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${php_packages[*]}" "Install PHP 8.3 packages" || return 1
    
    # Enable and start PHP-FPM
    run_cmd "systemctl enable php8.3-fpm" "Enable PHP-FPM" || return 1
    run_cmd "systemctl restart php8.3-fpm" "Start PHP-FPM" || return 1
    
    log_ok "PHP 8.3 installation completed!"
    return 0
}

do_install_mariadb() {
    log_info "Starting MariaDB installation..."
    
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mariadb-server mariadb-client" "Install MariaDB" || return 1
    run_cmd "systemctl enable mariadb" "Enable MariaDB" || return 1
    run_cmd "systemctl restart mariadb" "Start MariaDB" || return 1
    
    log_ok "MariaDB installation completed!"
    log_warn "Run 'mysql_secure_installation' to secure your installation"
    return 0
}

do_install_nginx() {
    log_info "Starting Nginx installation..."
    
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx" "Install Nginx" || return 1
    run_cmd "systemctl enable nginx" "Enable Nginx" || return 1
    run_cmd "systemctl restart nginx" "Start Nginx" || return 1
    
    log_ok "Nginx installation completed!"
    return 0
}

#-------------------------------------------------------------------------------
# SERVICE MANAGEMENT
#-------------------------------------------------------------------------------
service_menu() {
    local service_name="$1"
    local service_unit="$2"
    
    while true; do
        print_header
        echo -e "  ${BOLD}${service_name} Service Control${NC}"
        echo ""
        
        # Check current status
        local status
        if systemctl is-active --quiet "$service_unit" 2>/dev/null; then
            status="${GREEN}RUNNING${NC}"
        else
            status="${RED}STOPPED${NC}"
        fi
        
        local enabled
        if systemctl is-enabled --quiet "$service_unit" 2>/dev/null; then
            enabled="${GREEN}ENABLED${NC}"
        else
            enabled="${YELLOW}DISABLED${NC}"
        fi
        
        echo -e "  Status: $status | Boot: $enabled"
        echo ""
        echo -e "    ${GREEN}1)${NC} Start service"
        echo -e "    ${GREEN}2)${NC} Stop service"
        echo -e "    ${GREEN}3)${NC} Restart service"
        echo -e "    ${GREEN}4)${NC} Enable at boot"
        echo -e "    ${GREEN}5)${NC} Disable at boot"
        echo ""
        echo -e "    ${RED}0)${NC} Back to main menu"
        echo ""
        print_log
        echo ""
        
        echo -ne "${BOLD}Choose [0-5]: ${NC}"
        local choice
        read -r choice
        
        case "$choice" in
            1)
                log_info "Starting $service_name..."
                if systemctl start "$service_unit" 2>&1; then
                    log_ok "$service_name started"
                else
                    log_error "Failed to start $service_name"
                fi
                ;;
            2)
                if confirm "Stop $service_name?"; then
                    log_info "Stopping $service_name..."
                    if systemctl stop "$service_unit" 2>&1; then
                        log_ok "$service_name stopped"
                    else
                        log_error "Failed to stop $service_name"
                    fi
                fi
                ;;
            3)
                log_info "Restarting $service_name..."
                if systemctl restart "$service_unit" 2>&1; then
                    log_ok "$service_name restarted"
                else
                    log_error "Failed to restart $service_name"
                fi
                ;;
            4)
                log_info "Enabling $service_name at boot..."
                if systemctl enable "$service_unit" 2>&1; then
                    log_ok "$service_name enabled at boot"
                else
                    log_error "Failed to enable $service_name"
                fi
                ;;
            5)
                if confirm "Disable $service_name at boot?"; then
                    log_info "Disabling $service_name at boot..."
                    if systemctl disable "$service_unit" 2>&1; then
                        log_ok "$service_name disabled at boot"
                    else
                        log_error "Failed to disable $service_name"
                    fi
                fi
                ;;
            0|"")
                return
                ;;
            *)
                log_warn "Invalid option: $choice"
                ;;
        esac
        
        sleep 1
    done
}

#-------------------------------------------------------------------------------
# MAIN LOOP
#-------------------------------------------------------------------------------
main() {
    check_root
    
    log_ok "LEMP Manager started"
    log_info "Select an option from the menu"
    
    while true; do
        print_menu
        
        echo -ne "${BOLD}Choose [0-7]: ${NC}"
        local choice
        read -r choice
        
        case "$choice" in
            1)
                log_info "Selected: Update system"
                do_update_system
                pause
                ;;
            2)
                log_info "Selected: Install PHP 8.3"
                if confirm "Install PHP 8.3 and extensions?"; then
                    do_install_php
                fi
                pause
                ;;
            3)
                log_info "Selected: Install MariaDB"
                if confirm "Install MariaDB?"; then
                    do_install_mariadb
                fi
                pause
                ;;
            4)
                log_info "Selected: Install Nginx"
                if confirm "Install Nginx?"; then
                    do_install_nginx
                fi
                pause
                ;;
            5)
                service_menu "PHP-FPM 8.3" "php8.3-fpm"
                ;;
            6)
                service_menu "Nginx" "nginx"
                ;;
            7)
                service_menu "MariaDB" "mariadb"
                ;;
            0|q|Q)
                log_ok "Exiting..."
                echo ""
                echo -e "${GREEN}Goodbye!${NC}"
                echo ""
                exit 0
                ;;
            "")
                log_warn "No input - please enter a number"
                ;;
            *)
                log_warn "Invalid option: $choice"
                ;;
        esac
    done
}

# Run
main
