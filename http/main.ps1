. .\http_functions.ps1

# Validar Administrador
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Ejecuta el script como Administrador." -ForegroundColor Red
    exit
}

# Asegurar que Chocolatey está instalado y listo para usarse
Instalar-Chocolatey

while ($true) {
    [Console]::Clear()
    Write-Host "========================================"
    Write-Host "   GESTOR DE SERVIDORES HTTP (TAREA 6)"
    Write-Host "========================================"
    Write-Host "1. Instalacion de Servicios"
    Write-Host "2. Gestionar Servicios (Activar/Desactivar)"
    Write-Host "3. Salir"
    
    $opcionPrincipal = Read-Host "Selecciona una opcion"

    if ($opcionPrincipal -eq "1") {
        while ($true) {
            [Console]::Clear()
            Write-Host "--- SUBMENU DE INSTALACION ---" -ForegroundColor Cyan
            Write-Host "1. IIS (Internet Information Services)"
            Write-Host "2. Tomcat"
            Write-Host "3. Apache"
            Write-Host "4. Volver al menu principal"
            
            $subOpcion = Read-Host "Selecciona el servicio a instalar"

            if ($subOpcion -eq "1") {
                while ($true) {
                    $puertoApp = Read-Host "Introduce el puerto de escucha para IIS"
                    if (Validar-Puerto -Puerto $puertoApp) { break }
                }
                Instalar-HardenedIIS -Puerto $puertoApp
                Pause
            }
            elseif ($subOpcion -eq "2") {
                $versionElegida = Seleccionar-VersionChoco -Paquete "tomcat"
                if ($versionElegida) {
                    while ($true) {
                        $puertoApp = Read-Host "Introduce el puerto de escucha para Tomcat"
                        if (Validar-Puerto -Puerto $puertoApp) { break }
                    }
                    Instalar-TomcatWindows -Version $versionElegida -Puerto $puertoApp
                }
                Pause
            }
            elseif ($subOpcion -eq "3") {
                $versionElegida = Seleccionar-VersionChoco -Paquete "apache-httpd"
                if ($versionElegida) {
                    while ($true) {
                        $puertoApp = Read-Host "Introduce el puerto de escucha para Apache"
                        if (Validar-Puerto -Puerto $puertoApp) { break }
                    }
                    Instalar-ApacheWindows -Version $versionElegida -Puerto $puertoApp
                }
                Pause
            }
            elseif ($subOpcion -eq "4") { break }
        }
    }
    elseif ($opcionPrincipal -eq "2") {
        while ($true) {
            [Console]::Clear()
            Write-Host "--- GESTION DE SERVICIOS ---" -ForegroundColor Cyan
            Write-Host "1. Controlar IIS"
            Write-Host "2. Controlar Tomcat"
            Write-Host "3. Controlar Apache"
            Write-Host "4. Volver al menu principal"

            $subGest = Read-Host "Selecciona el servicio a gestionar"
            
            if ($subGest -eq "1") { Gestionar-Servicio -NombreServicio "W3SVC" -NombreVisual "IIS" }
            elseif ($subGest -eq "2") { Gestionar-Servicio -NombreServicio "Tomcat9" -NombreVisual "Tomcat" }
            elseif ($subGest -eq "3") { Gestionar-Servicio -NombreServicio "Apache*" -NombreVisual "Apache" }
            elseif ($subGest -eq "4") { break }
        }
    }
    elseif ($opcionPrincipal -eq "3") {
        Write-Host "Saliendo..." -ForegroundColor Cyan
        exit
    }
}