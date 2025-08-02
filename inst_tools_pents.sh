#!/bin/bash


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' 


function message() {
    local color=$1
    local text=$2
    
    case $color in
        "red")    echo -e "${RED}[*] $text${NC}" ;;
        "green")  echo -e "${GREEN}[*] $text${NC}" ;;
        "yellow") echo -e "${YELLOW}[*] $text${NC}" ;;
        "blue")   echo -e "${BLUE}[*] $text${NC}" ;;
        "cyan")   echo -e "${CYAN}[*] $text${NC}" ;;
        "white")  echo -e "${WHITE}[*] $text${NC}" ;;
        *)        echo -e "[*] $text" ;;
    esac
}


tools=(
    "nmap"
    "gobuster"
    "ffuf"
    "nikto"
    "netcat-traditional"
    "smbclient"
    "exploitdb"  
    "john"
    "hashcat"
    "openvpn"
    "sqlmap"
    "whatweb"
)


declare -A installation_errors


message "blue" "Actualizando lista de paquetes..."

if sudo apt-get update > /dev/null 2>&1; then
    message "green" "Lista de paquetes actualizada!"
else

    message "red" "Error al actualizar lista de paquetes"
    exit 1
fi

message "cyan" "Iniciando instalación..."
echo -e "${BLUE}----------------------------------------${NC}"


success=0
failures=0
skipped=0

for tool in "${tools[@]}"; do

    if dpkg -s "$tool" > /dev/null 2>&1; then
        message "yellow" "$tool ya esta instalado - omitiendo"
        ((skipped++))
        echo -e "${BLUE}----------------------------------------${NC}"

        continue
    fi

    message "white" "Instalando $tool..."
    

    error_log=$(mktemp)
    if sudo apt-get install -y "$tool" > /dev/null 2>"$error_log"; then
        if dpkg -s "$tool" > /dev/null 2>&1; then
            message "green" "$tool instalado correctamente"
            ((success++))

        else

            message "yellow" "$tool instalado pero no verificado"
            installation_errors["$tool"]="Instalado pero no verificado"
            ((failures++))
        fi
    else
        message "red" "Error al instalar $tool"
        installation_errors["$tool"]=$(grep -i "error\|failed\|E:" "$error_log" | head -n 1 || echo "Error desconocido")
        ((failures++))
    fi
    
    rm -f "$error_log"
    echo -e "${BLUE}----------------------------------------${NC}"
done


message "cyan" "Resumen de instalacion:"
message "green" "Herramientas instaladas correctamente: $success"
message "yellow" "Herramientas ya instaladas: $skipped"
message "red" "Herramientas con problemas: $failures"

message "white" "Total de herramientas procesadas: ${#tools[@]}"


if [ $failures -gt 0 ]; then
    echo ""
    message "red" "Errores durante la instalación:"
    for tool in "${!installation_errors[@]}"; do
        message "yellow" "  - $tool: ${installation_errors[$tool]}"
    done
fi


if [ $failures -eq 0 ]; then
    message "green" "Todas las herramientas se instalaron correctamente!:)"
else
    message "red" "Algunas herramientas tuvieron problemas durante la instalación.:("
fi


