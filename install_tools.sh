#!/bin/sh

LOG_FILE="/tmp/pentest-installer-$(date +%Y%m%d-%H%M%S).log"
MAX_RETRIES=3
RETRY_DELAY=5

SKIP_UPDATE=false
VERBOSE=false
SILENT=false
LIST_TOOLS=false
INSTALL_SPECIFIC=false
TOOLS_LIST=""

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; WHITE=''; NC=''
fi

TOOLS="nmap gobuster ffuf nikto netcat-traditional smbclient exploitdb john hashcat openvpn sqlmap whatweb hydra wireshark aircrack-ng dirb enum4linux"

log_message() {
    level="$1"
    message="$2"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ "$SILENT" = false ]; then
        case "$level" in
            "INFO") printf "${GREEN}[*]${NC} %s\n" "$message" ;;
            "WARN") printf "${YELLOW}[!]${NC} %s\n" "$message" ;;
            "ERROR") printf "${RED}[X]${NC} %s\n" "$message" ;;
            "DEBUG") 
                if [ "$VERBOSE" = true ]; then
                    printf "${CYAN}[D]${NC} %s\n" "$message"
                fi
                ;;
        esac
    fi
}

check_system() {
    log_message "INFO" "Verificando sistema..."
    if [ ! -f /etc/os-release ]; then
        log_message "ERROR" "Sistema operativo no detectado"
        return 1
    fi
    . /etc/os-release
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ] || [ "$ID" = "kali" ]; then
        log_message "INFO" "$NAME $VERSION_ID detectado"
        ARCH=$(uname -m)
        if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv7l" ]; then
            log_message "WARN" "Arquitectura $ARCH no verificada completamente"
        fi
        return 0
    else
        log_message "ERROR" "Sistema $ID no compatible"
        return 1
    fi
}

check_disk_space() {
    required=5000000
    available=$(df / | tail -1 | awk '{print $4}')
    if [ "$available" -lt "$required" ]; then
        log_message "WARN" "Espacio en disco bajo (disponible: ${available}KB, mínimo: ${required}KB)"
        return 1
    fi
    return 0
}

install_tool() {
    tool="$1"
    retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if [ $retry_count -gt 0 ]; then
            log_message "WARN" "Reintento $retry_count para $tool"
            sleep "$RETRY_DELAY"
        fi
        log_message "INFO" "Instalando $tool..."
        if apt-get install -y "$tool" > /dev/null 2>&1; then
            if dpkg -l | grep -q "^ii.*$tool" || command -v "$tool" > /dev/null 2>&1; then
                log_message "INFO" "$tool instalado"
                return 0
            fi
        fi
        retry_count=$((retry_count + 1))
    done
    log_message "ERROR" "Falló instalación de $tool"
    return 1
}

install_group() {
    group_name="$1"
    tools="$2"
    log_message "INFO" "Instalando grupo: $group_name"
    retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if apt-get install -y $tools > /dev/null 2>&1; then
            log_message "INFO" "Grupo $group_name instalado"
            return 0
        fi
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $MAX_RETRIES ] && sleep "$RETRY_DELAY"
    done
    log_message "ERROR" "Falló grupo $group_name"
    return 1
}

update_system() {
    if [ "$SKIP_UPDATE" = true ]; then
        log_message "INFO" "Saltando actualización"
        return 0
    fi
    log_message "INFO" "Actualizando paquetes..."
    temp_file="/tmp/apt-update-$$.log"
    if apt-get update > "$temp_file" 2>&1; then
        rm -f "$temp_file"
        return 0
    else
        log_message "ERROR" "Error al actualizar"
        [ -f "$temp_file" ] && log_message "DEBUG" "Detalles en: $temp_file"
        return 1
    fi
}

create_symlinks() {
    log_message "INFO" "Creando symlinks..."
    [ ! -f /usr/bin/nc ] && [ -f /usr/bin/nc.traditional ] && ln -s /usr/bin/nc.traditional /usr/bin/nc 2>/dev/null
    [ ! -f /usr/bin/ncat ] && [ -f /usr/bin/nc ] && ln -s /usr/bin/nc /usr/bin/ncat 2>/dev/null
}

show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo "  --skip-update           Saltar actualización"
    echo "  --list-tools            Mostrar herramientas"
    echo "  --verbose               Modo verboso"
    echo "  --silent                Modo silencioso"
    echo "  --tools \"nmap sqlmap\"   Instalar herramientas específicas"
    echo "  --help                  Mostrar ayuda"
    exit 0
}

process_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-update) SKIP_UPDATE=true ;;
            --list-tools) LIST_TOOLS=true ;;
            --verbose) VERBOSE=true ;;
            --silent) SILENT=true ;;
            --tools) 
                INSTALL_SPECIFIC=true
                TOOLS_LIST="$2"
                shift
                ;;
            --help) show_help ;;
            *) 
                echo "Opción desconocida: $1" >&2
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    touch "$LOG_FILE"
    log_message "INFO" "Iniciando instalador"
    
    if [ "$(id -u)" -ne 0 ]; then
        log_message "ERROR" "Ejecutar con: sudo $0"
        exit 1
    fi
    
    process_arguments "$@"
    
    if [ "$LIST_TOOLS" = true ]; then
        printf "${CYAN}[*]${NC} Herramientas disponibles:\n"
        for tool in $TOOLS; do
            printf "  - %s\n" "$tool"
        done
        exit 0
    fi
    
    ! check_system && exit 1
    check_disk_space
    
    ! update_system && log_message "WARN" "Continuando sin actualización"
    
    if [ "$INSTALL_SPECIFIC" = true ]; then
        INSTALL_TOOLS="$TOOLS_LIST"
    else
        INSTALL_TOOLS="$TOOLS"
    fi
    
    log_message "INFO" "Agrupando herramientas..."
    WEB_TOOLS="gobuster ffuf nikto whatweb sqlmap dirb"
    PASS_TOOLS="john hashcat hydra"
    NET_TOOLS="nmap smbclient openvpn wireshark aircrack-ng netcat-traditional enum4linux"
    EXPLOIT_TOOLS="exploitdb"
    
    success=0
    failures=0
    skipped=0
    
    for group in "WEB" "PASS" "NET" "EXPLOIT"; do
        eval "group_tools=\$${group}_TOOLS"
        to_install=""
        for tool in $group_tools; do
            if echo "$INSTALL_TOOLS" | grep -qw "$tool"; then
                if dpkg -l | grep -q "^ii.*$tool" || command -v "$tool" > /dev/null 2>&1; then
                    log_message "INFO" "$tool ya instalado"
                    skipped=$((skipped + 1))
                else
                    to_install="$to_install $tool"
                fi
            fi
        done
        [ -n "$to_install" ] && install_group "$group" "$to_install" && success=$((success + $(echo "$to_install" | wc -w))) || failures=$((failures + $(echo "$to_install" | wc -w)))
    done
    
    for tool in $INSTALL_TOOLS; do
        if ! echo "$WEB_TOOLS $PASS_TOOLS $NET_TOOLS $EXPLOIT_TOOLS" | grep -qw "$tool"; then
            if dpkg -l | grep -q "^ii.*$tool" || command -v "$tool" > /dev/null 2>&1; then
                skipped=$((skipped + 1))
                continue
            fi
            install_tool "$tool" && success=$((success + 1)) || failures=$((failures + 1))
        fi
    done
    
    create_symlinks
    
    log_message "INFO" "RESUMEN: $success instaladas, $skipped omitidas, $failures fallidas"
    log_message "INFO" "Log: $LOG_FILE"
    
    if [ $failures -eq 0 ]; then
        printf "${GREEN}[*]${NC} Instalación completada\n"
        exit 0
    else
        printf "${YELLOW}[!]${NC} Instalación con $failures errores\n"
        exit 1
    fi
}

main "$@"
