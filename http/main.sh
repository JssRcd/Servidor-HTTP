#!/bin/bash

source ./http_functions.sh

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31m[!] Por favor ejecuta el script como Root (ej. sudo ./main.sh)\e[0m"
  exit 1
fi

while true; do
    clear
    echo "========================================"
    echo "   GESTOR DE SERVIDORES HTTP (FEDORA)"
    echo "========================================"
    echo "1. Instalacion de Servicios"
    echo "2. Gestionar Servicios (Activar/Desactivar)"
    echo "3. Salir"
    
    read -p "Selecciona una opcion: " opcionPrincipal

    if [ "$opcionPrincipal" == "1" ]; then
        while true; do
            clear
            echo -e "${CIAN}--- SUBMENU DE INSTALACION ---${RESET}"
            echo "1. Nginx"
            echo "2. Tomcat"
            echo "3. Apache"
            echo "4. Volver al menu principal"
            
            read -p "Selecciona el servicio a instalar: " subOpcion

            if [ "$subOpcion" == "1" ]; then
                versionElegida=$(seleccionar_version_dnf "nginx" 2>/dev/tty)
                if [ -n "$versionElegida" ]; then
                    while true; do
                        read -p "Introduce el puerto de escucha para Nginx: " puertoApp
                        validar_puerto "$puertoApp" && break
                    done
                    instalar_nginx "$versionElegida" "$puertoApp"
                fi
                read -p "Presiona Enter para continuar..."
                
            elif [ "$subOpcion" == "2" ]; then
                versionElegida=$(seleccionar_version_tomcat 2>/dev/tty)
                if [ -n "$versionElegida" ]; then
                    while true; do
                        read -p "Introduce el puerto de escucha para Tomcat: " puertoApp
                        validar_puerto "$puertoApp" && break
                    done
                    instalar_tomcat "$versionElegida" "$puertoApp"
                fi
                read -p "Presiona Enter para continuar..."
                
            elif [ "$subOpcion" == "3" ]; then
                versionElegida=$(seleccionar_version_dnf "httpd" 2>/dev/tty)
                if [ -n "$versionElegida" ]; then
                    while true; do
                        read -p "Introduce el puerto de escucha para Apache: " puertoApp
                        validar_puerto "$puertoApp" && break
                    done
                    instalar_apache "$versionElegida" "$puertoApp"
                fi
                read -p "Presiona Enter para continuar..."
                
            elif [ "$subOpcion" == "4" ]; then
                break
            fi
        done
        
    elif [ "$opcionPrincipal" == "2" ]; then
        while true; do
            clear
            echo -e "${CIAN}--- GESTION DE SERVICIOS ---${RESET}"
            echo "1. Controlar Nginx"
            echo "2. Controlar Tomcat"
            echo "3. Controlar Apache"
            echo "4. Volver al menu principal"

            read -p "Selecciona el servicio a gestionar: " subGest
            
            if [ "$subGest" == "1" ]; then
                gestionar_servicio "nginx" "Nginx"
            elif [ "$subGest" == "2" ]; then
                gestionar_servicio "tomcat" "Tomcat"
            elif [ "$subGest" == "3" ]; then
                gestionar_servicio "httpd" "Apache"
            elif [ "$subGest" == "4" ]; then
                break
            fi
        done
        
    elif [ "$opcionPrincipal" == "3" ]; then
        echo -e "${CIAN}Saliendo...${RESET}"
        exit 0
    fi
done
