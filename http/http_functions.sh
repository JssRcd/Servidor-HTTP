#!/bin/bash

# Definicion de colores para la salida en consola
VERDE="\e[32m"
ROJO="\e[31m"
AMARILLO="\e[33m"
CIAN="\e[36m"
RESET="\e[0m"

# 1. VALIDACION DE PUERTOS
validar_puerto() {
    local puerto=$1
    if ! [[ "$puerto" =~ ^[0-9]+$ ]] || [ "$puerto" -le 0 ] || [ "$puerto" -gt 65535 ]; then
        echo -e "${ROJO}[!] Error: El puerto debe ser un numero entre 1 y 65535.${RESET}" >&2
        return 1
    fi
    if [[ "$puerto" == "21" || "$puerto" == "22" || "$puerto" == "3389" ]]; then
        echo -e "${ROJO}[!] Error: Puerto reservado.${RESET}" >&2
        return 1
    fi
    if ss -tuln | grep -q ":$puerto "; then
        echo -e "${ROJO}[!] Error: El puerto $puerto ya esta en uso.${RESET}" >&2
        return 1
    fi
    return 0
}

# 2. SELECCION DE VERSIONES PARA DNF (Nginx / Apache)
seleccionar_version_dnf() {
    local paquete=$1
    echo -e "\n${CIAN}[*] Buscando versiones para $paquete...${RESET}" >&2
    
    # Extraer las ultimas 5 versiones disponibles en los repositorios
    mapfile -t versiones < <(dnf list --showduplicates "$paquete" 2>/dev/null | awk -v pkg="$paquete" '$1 ~ pkg {print $2}' | sort -ur | head -n 5)

    if [ ${#versiones[@]} -eq 0 ]; then
        echo -e "${ROJO}[!] No se encontraron versiones para $paquete.${RESET}" >&2
        return 1
    fi

    echo -e "${AMARILLO}--- VERSIONES DISPONIBLES ---${RESET}" >&2
    for i in "${!versiones[@]}"; do
        echo "  $((i + 1))) ${versiones[$i]}" >&2
    done

    while true; do
        read -p "Digita el numero de la version a instalar: " sel </dev/tty
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#versiones[@]} ]; then
            echo "${versiones[$((sel - 1))]}"
            return 0
        else
            echo -e "${ROJO}[!] Opcion invalida.${RESET}" >&2
        fi
    done
}

# 3. SELECCION DE VERSIONES PARA TOMCAT (Binarios)
seleccionar_version_tomcat() {
    echo -e "\n${CIAN}[*] Buscando versiones para tomcat...${RESET}" >&2
    local versiones=("9.0.87" "9.0.86" "9.0.85" "9.0.84" "9.0.83")
    
    echo -e "${AMARILLO}--- VERSIONES DISPONIBLES ---${RESET}" >&2
    for i in "${!versiones[@]}"; do
        echo "  $((i + 1))) ${versiones[$i]}" >&2
    done

    while true; do
        read -p "Digita el numero de la version a instalar: " sel </dev/tty
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#versiones[@]} ]; then
            echo "${versiones[$((sel - 1))]}"
            return 0
        else
            echo -e "${ROJO}[!] Opcion invalida.${RESET}" >&2
        fi
    done
}

# 4. INSTALACION NGINX
instalar_nginx() {
    local version=$1
    local puerto=$2
    echo -e "${AMARILLO}[*] Instalando Nginx v$version...${RESET}"
    dnf install nginx-$version -y >/dev/null 2>&1 || dnf install nginx -y >/dev/null 2>&1

    echo -e "${CIAN}[*] Configurando Nginx en el puerto $puerto...${RESET}"
    sed -i "s/listen       80;/listen       $puerto;/g" /etc/nginx/nginx.conf
    sed -i "s/listen       \[::\]:80;/listen       \[::\]:$puerto;/g" /etc/nginx/nginx.conf

    # Crear index.html personalizado
    local real_ver=$(nginx -v 2>&1 | awk -F/ '{print $2}')
    echo "<h3>Servicio: Nginx</h3><p>Estado: Activo</p><p>Puerto: $puerto</p><p>Version: $real_ver</p>" > /usr/share/nginx/html/index.html

    # Configuracion de seguridad y arranque
    firewall-cmd --add-port=${puerto}/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    setenforce 0 2>/dev/null

    systemctl restart nginx
    systemctl enable nginx >/dev/null 2>&1
    echo -e "${VERDE}[+] Nginx instalado y corriendo en el puerto $puerto${RESET}"
}

# 5. INSTALACION TOMCAT
instalar_tomcat() {
    local version=$1
    local puerto=$2
    
    echo -e "${CIAN}[*] Descargando e instalando motor Java 17...${RESET}"
    dnf install wget tar -y >/dev/null 2>&1
    
    # Descargar Java en /opt para evitar restricciones de permisos en /tmp
    wget --tries=3 https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz -O /opt/java.tar.gz
    rm -rf /opt/java
    mkdir -p /opt/java
    tar -xzf /opt/java.tar.gz -C /opt/java --strip-components=1
    rm -f /opt/java.tar.gz

    echo -e "${AMARILLO}[*] Descargando e instalando Tomcat v$version...${RESET}"
    id -u tomcat &>/dev/null || useradd -m -U -d /opt/tomcat -s /bin/false tomcat

    # Descargar Tomcat en /opt
    wget --tries=3 https://archive.apache.org/dist/tomcat/tomcat-9/v${version}/bin/apache-tomcat-${version}.tar.gz -O /opt/tomcat.tar.gz
    mkdir -p /opt/tomcat
    tar -xzf /opt/tomcat.tar.gz -C /opt/tomcat --strip-components=1
    rm -f /opt/tomcat.tar.gz
    
    echo -e "${CIAN}[*] Configurando Tomcat en el puerto $puerto...${RESET}"
    sed -i "s/port=\"8080\"/port=\"$puerto\"/g" /opt/tomcat/conf/server.xml

    # Crear index.html personalizado
    mkdir -p /opt/tomcat/webapps/ROOT
    echo "<h3>Servicio: Tomcat</h3><p>Estado: Activo</p><p>Puerto: $puerto</p><p>Version: $version</p>" > /opt/tomcat/webapps/ROOT/index.html
    rm -f /opt/tomcat/webapps/ROOT/index.jsp 2>/dev/null
    
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R u+x /opt/tomcat/bin

    # Generar archivo de servicio systemd
    cat <<EOF > /etc/systemd/system/tomcat.service
[Unit]
Description=Tomcat 9 servlet container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/opt/java"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    # Configuracion de seguridad y arranque
    firewall-cmd --add-port=${puerto}/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    setenforce 0 2>/dev/null

    systemctl restart tomcat
    systemctl enable tomcat >/dev/null 2>&1
    echo -e "${VERDE}[+] Tomcat instalado y corriendo en el puerto $puerto${RESET}"
}

# 6. INSTALACION APACHE
instalar_apache() {
    local version=$1
    local puerto=$2
    echo -e "${AMARILLO}[*] Instalando Apache (httpd) v$version...${RESET}"
    dnf install httpd-$version -y >/dev/null 2>&1 || dnf install httpd -y >/dev/null 2>&1

    echo -e "${CIAN}[*] Configurando Apache en el puerto $puerto...${RESET}"
    sed -i "s/^Listen .*/Listen $puerto/" /etc/httpd/conf/httpd.conf

    # Crear index.html personalizado
    local real_ver=$(httpd -v | grep version | awk -F/ '{print $2}' | awk '{print $1}')
    echo "<h3>Servicio: Apache</h3><p>Estado: Activo</p><p>Puerto: $puerto</p><p>Version: $real_ver</p>" > /var/www/html/index.html

    # Configuracion de seguridad y arranque
    firewall-cmd --add-port=${puerto}/tcp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    setenforce 0 2>/dev/null

    systemctl restart httpd
    systemctl enable httpd >/dev/null 2>&1
    echo -e "${VERDE}[+] Apache instalado y corriendo en el puerto $puerto${RESET}"
}

# 7. GESTION DE ESTADO DE SERVICIOS
gestionar_servicio() {
    local servicio=$1
    local nombre_visual=$2

    if ! systemctl list-unit-files | grep -q "^${servicio}.service"; then
        echo -e "\n${ROJO}[!] El servicio $nombre_visual no esta instalado.${RESET}"
        sleep 2
        return
    fi

    while true; do
        clear
        echo -e "${CIAN}--- GESTION DE $nombre_visual ---${RESET}"
        
        if systemctl is-active --quiet $servicio; then
            echo -e "Estado actual: ${VERDE}CORRIENDO${RESET}"
        else
            echo -e "Estado actual: ${ROJO}DETENIDO${RESET}"
        fi
        
        echo -e "\n1. Iniciar"
        echo "2. Detener"
        echo "3. Reiniciar"
        echo "4. Volver"
        
        read -p "Elige una accion: " acc
        case $acc in
            1) systemctl start $servicio 2>/dev/null; echo -e "${CIAN}[+] Iniciando...${RESET}"; sleep 1 ;;
            2) systemctl stop $servicio 2>/dev/null; echo -e "${CIAN}[+] Deteniendo...${RESET}"; sleep 1 ;;
            3) systemctl restart $servicio 2>/dev/null; echo -e "${CIAN}[+] Reiniciando...${RESET}"; sleep 1 ;;
            4) return ;;
            *) echo "Opcion invalida." ;;
        esac
    done
}
