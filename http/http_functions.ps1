# 1. AUTOMATIZACION DE CHOCOLATEY
function Instalar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Instalando gestor de paquetes Chocolatey..." -ForegroundColor Cyan
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) > $null 2>&1
        $env:Path += ";C:\ProgramData\chocolatey\bin"
        Write-Host "[+] Chocolatey instalado correctamente." -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
}

# 2. VALIDACION DE PUERTOS
function Validar-Puerto {
    param([string]$Puerto)
    if ($Puerto -notmatch "^\d+$" -or [int]$Puerto -le 0 -or [int]$Puerto -gt 65535) {
        Write-Host "[!] Error: El puerto debe ser un numero entre 1 y 65535." -ForegroundColor Red
        return $false
    }
    if ($Puerto -in @("21","22","3389")) {
        Write-Host "[!] Error: Puerto reservado." -ForegroundColor Red
        return $false
    }
    $Conexion = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    if ($Conexion.TcpTestSucceeded) {
        Write-Host "[!] Error: El puerto $Puerto ya esta en uso." -ForegroundColor Red
        return $false
    }
    return $true
}

# 3. BUSQUEDA DINAMICA DE VERSIONES
function Seleccionar-VersionChoco {
    param([string]$Paquete)
    Write-Host "`n[*] Buscando versiones para $Paquete..." -ForegroundColor Cyan
    $salida = choco search $Paquete --exact --all -r
    if (-not $salida) {
        Write-Host "[!] No se encontro el paquete." -ForegroundColor Red
        return $null
    }
    $versiones = $salida | ForEach-Object { ($_ -split '\|')[1] } | Select-Object -First 5
    Write-Host "--- VERSIONES DISPONIBLES ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $versiones.Count; $i++) { Write-Host "  $($i + 1)) $($versiones[$i])" }

    while ($true) {
        $sel = Read-Host "Digita el numero de la version a instalar"
        if ($sel -match "^\d+$" -and [int]$sel -ge 1 -and [int]$sel -le $versiones.Count) {
            return $versiones[[int]$sel - 1]
        }
    }
}

# 4. INSTALACION IIS
function Instalar-HardenedIIS {
    param([string]$Puerto)
    Write-Host "[*] Instalando IIS..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName "IIS-WebServerRole","IIS-WebServer","IIS-CommonHttpFeatures","IIS-Security","IIS-RequestFiltering" -All -NoRestart > $null
    Import-Module WebAdministration
    
    Get-WebBinding -Name "Default Web Site" | Remove-WebBinding -ErrorAction Ignore 2>$null
    New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port $Puerto -Protocol http

    # Limpieza de Headers
    Remove-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/httpProtocol/customHeaders" -name "." -AtElement @{name='X-Powered-By'} -ErrorAction Ignore 2>$null
    Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST' -filter "system.webServer/security/requestFiltering" -name "removeServerHeader" -value "True" -ErrorAction Ignore 2>$null

    $versionIIS = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString
    $html = "<h3>Servicio: IIS</h3><p>Estado: Activo</p><p>Puerto: $Puerto</p><p>Version: $versionIIS</p>"
    $html | Out-File "C:\inetpub\wwwroot\index.html" -Encoding utf8

    New-NetFirewallRule -DisplayName "HTTP-IIS-$Puerto" -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction Ignore 2>$null
    Restart-Service W3SVC -ErrorAction SilentlyContinue
    Write-Host "[+] IIS instalado en el puerto $Puerto" -ForegroundColor Green
}

# 5. INSTALACION TOMCAT
function Instalar-TomcatWindows {
    param([string]$Version, [string]$Puerto)
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Instalando OpenJDK..." -ForegroundColor Cyan
        choco install openjdk -y --force > $null
    }
    Write-Host "[*] Instalando Tomcat v$Version..." -ForegroundColor Yellow
    choco install tomcat --version $Version -y --force > $null
    
    $tomcatDir = "C:\ProgramData\Tomcat9"
    if (Test-Path "$tomcatDir\conf\server.xml") {
        (Get-Content "$tomcatDir\conf\server.xml") -replace 'port="8080"', "port=`"$Puerto`"" | Set-Content "$tomcatDir\conf\server.xml"
        
        $html = "<h3>Servicio: Tomcat</h3><p>Estado: Activo</p><p>Puerto: $Puerto</p><p>Version: $Version</p>"
        $html | Out-File "$tomcatDir\webapps\ROOT\index.html" -Encoding utf8
        if (Test-Path "$tomcatDir\webapps\ROOT\index.jsp") { Remove-Item "$tomcatDir\webapps\ROOT\index.jsp" -Force }

        $installServiceCmd = "$tomcatDir\bin\service.bat"
        if (Test-Path $installServiceCmd) {
             $javaPath = (Get-Command java).Source
             $env:JAVA_HOME = Split-Path (Split-Path $javaPath -Parent) -Parent
             Start-Process -FilePath cmd.exe -ArgumentList "/c `"$installServiceCmd`" install Tomcat9" -Wait -WindowStyle Hidden
        }
        New-NetFirewallRule -DisplayName "HTTP-Tomcat-$Puerto" -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction Ignore > $null 2>&1
        Start-Service Tomcat9 -ErrorAction SilentlyContinue
        Write-Host "[+] Tomcat instalado y corriendo en el puerto $Puerto" -ForegroundColor Green
    }
}

# 6. INSTALACION APACHE
function Instalar-ApacheWindows {
    param([string]$Version, [string]$Puerto)
    Write-Host "[*] Instalando Apache v$Version..." -ForegroundColor Yellow
    choco install apache-httpd --version $Version -y --force > $null
    
    # Resolucion dinamica de rutas
    $apacheDir = $null
    $posiblesRutas = @("C:\tools\Apache24", "C:\Users\Administrador\AppData\Roaming\Apache24", "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24")
    foreach ($ruta in $posiblesRutas) { if (Test-Path $ruta) { $apacheDir = $ruta; break } }

    if ($apacheDir -and (Test-Path "$apacheDir\conf\httpd.conf")) {
        (Get-Content "$apacheDir\conf\httpd.conf") -replace "Listen \d+", "Listen $Puerto" | Set-Content "$apacheDir\conf\httpd.conf"
        
        $html = "<h3>Servicio: Apache</h3><p>Estado: Activo</p><p>Puerto: $Puerto</p><p>Version: $Version</p>"
        $html | Out-File "$apacheDir\htdocs\index.html" -Encoding utf8

        New-NetFirewallRule -DisplayName "HTTP-Apache-$Puerto" -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction Ignore 2>$null
        Start-Service Apache* -ErrorAction SilentlyContinue
        Write-Host "[+] Apache instalado y corriendo en el puerto $Puerto" -ForegroundColor Green
    } else {
         Write-Host "[!] No se encontro el archivo de configuracion de Apache." -ForegroundColor Red
    }
}

# 7. GESTION DE ESTADO DE SERVICIOS (Start/Stop)
function Gestionar-Servicio {
    param([string]$NombreServicio, [string]$NombreVisual)
    
    # Si es Apache, resolvemos el nombre real del servicio
    if ($NombreServicio -eq "Apache*") {
        $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svc) { $NombreServicio = $svc.Name }
    }

    $servicio = Get-Service -Name $NombreServicio -ErrorAction SilentlyContinue
    
    if (-not $servicio) {
        Write-Host "`n[!] El servicio $NombreVisual no esta instalado." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    while ($true) {
        [Console]::Clear()
        $servicio = Get-Service -Name $NombreServicio
        Write-Host "--- GESTION DE $NombreVisual ---" -ForegroundColor Cyan
        
        if ($servicio.Status -eq 'Running') {
            Write-Host "Estado actual: CORRIENDO" -ForegroundColor Green
        } else {
            Write-Host "Estado actual: DETENIDO" -ForegroundColor Red
        }
        
        Write-Host "`n1. Iniciar"
        Write-Host "2. Detener"
        Write-Host "3. Reiniciar"
        Write-Host "4. Volver"
        
        $acc = Read-Host "Elige una accion"
        switch ($acc) {
            "1" { Start-Service $NombreServicio -ErrorAction SilentlyContinue; Write-Host "[+] Iniciando..." -ForegroundColor Cyan; Start-Sleep 1 }
            "2" { Stop-Service $NombreServicio -Force -ErrorAction SilentlyContinue; Write-Host "[+] Deteniendo..." -ForegroundColor Cyan; Start-Sleep 1 }
            "3" { Restart-Service $NombreServicio -Force -ErrorAction SilentlyContinue; Write-Host "[+] Reiniciando..." -ForegroundColor Cyan; Start-Sleep 1 }
            "4" { return }
            default { Write-Host "Opcion invalida." }
        }
    }
}