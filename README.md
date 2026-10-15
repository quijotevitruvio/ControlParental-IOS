# InstitutionalApp iOS

App nativa iOS para supervisión institucional de dispositivos (iPhone/iPad).
Compatible con iOS 17+, Swift 5.9, Xcode 15+.

## 🎯 Qué hace

- **Telemetría periódica**: batería, red, ubicación, Screen Time agregado
- **Ubicación continua**: permiso "Siempre", geocercas (máx 20), alertas entrada/salida
- **SOS voluntario**: botón de emergencia con foto/galería + ubicación
- **Push silencioso (APNs)**: comandos del panel (request_location, policy_update, sos_ack)
- **MDM Integration**: ManagedAppConfiguration, webhooks MDM → panel
- **Screen Time**: DeviceActivity para reportes agregados de uso
- **Offline-first**: cola local de eventos, flush al reconectar

## ⚠️ Qué NO hace (limitaciones iOS)

| Función | Estado | Por qué |
|---|---|---|
| Cámara remota/silenciosa | ❌ | Requiere UI + consentimiento |
| Galería remota | ❌ | Requiere picker nativo |
| Keylogger | ❌ | No hay AccessibilityService |
| Captura pantalla | ❌ | ReplayKit requiere UI |
| Micrófono silencioso | ❌ | Indicador obligatorio |
| Leer WhatsApp/Signal/Telegram | ❌ | Cifrado E2E + sandbox |
| SMS / Llamadas | ❌ | No API pública |
| Servicio 24/7 garantizado | ❌ | iOS gestiona memoria/batería |

## 📋 Requisitos

- **Apple Developer Enterprise** ($299/año) o **Ad Hoc** (100 dispositivos/año)
- **Xcode 15+**, **Swift 5.9+**, **iOS 17.0+**
- **Apple Business Manager (ABM)** + **MDM** (Miradore Free, Jamf, Intune)
- **Certificados**: APNs AuthKey (.p8), Provisioning Profile, Entitlements

## 🔧 Entitlements Requeridos

```xml
<!-- InstitutionalApp.entitlements -->
<key>aps-environment</key><string>production</string>
<key>com.apple.developer.device-activity</key><true/>
<key>com.apple.developer.managed-app-configuration</key><true/>
<key>com.apple.developer.networking.networkextension</key><true/>  <!-- si NEFilterProvider -->
<key>com.apple.developer.networking.wifi-info</key><true/>
```

Background Modes en Info.plist:
- `location` (ubicación background)
- `remote-notification` (silent push)
- `fetch` (BGAppRefreshTask)
- `processing` (BGProcessingTask)

## 🚀 Build & Deploy

```bash
chmod +x build.sh
./build.sh
```

### Requisitos previos:
1. **Apple Developer Enterprise** ($299/año) en developer.apple.com
2. **Certificado APNs** (.p8 AuthKey) en Certificates > Keys
3. **App ID** con entitlements: Push Notifications, Background Modes, DeviceActivity
4. **Provisioning Profile** (Distribution/Enterprise) vinculado al App ID
5. **MDM** configurado (Miradore Free recomendado para piloto)

### ExportOptions.plist (ejemplo Enterprise):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>enterprise</string>
    <key>teamID</key><string>TU_TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>stripSwiftSymbols</key><true/>
    <key>uploadSymbols</key><true/>
    <key>compileBitcode</key><false/>
</dict>
```

## 🔗 Integración con Panel Web

### Endpoints usados:
- `POST /api/institution_events.php` - Telemetría + eventos riesgo
- `POST /api/upload.php` - Subida media (SOS)
- `POST /api/mdm_webhook.php` - Webhooks MDM → panel
- Silent push APNs → `content-available: 1` + `command`

### ManagedAppConfiguration (MDM → App)
```json
{
  "server_base": "https://tudominio.com/elojodeja",
  "org_id": 1,
  "case_id": 123,
  "risk_thresholds": {"critical": 90, "high": 60},
  "geofences": [{"id": "school", "latitude": 4.1, "longitude": -74.2, "radius_meters": 200, "name": "Colegio"}],
  "apns_topic": "com.tuorg.institucional"
}
```

## 📱 Enrolamiento iPhone

1. **ABM/DEP**: Registra institución en business.apple.com
2. **MDM**: Crea cuenta Miradore Free (20 disp. gratis) o Jamf/Intune
3. **DEP Profile**: Asigna MDM en ABM → dispositivos se enrolan al encender
4. **Perfil MDM**: Restricciones, Wi-Fi, certs, apps VPP, `isRemovable=false`
5. **App**: Se instala vía VPP o se descarga de portal MDM
3. **Config**: Llega vía `ManagedAppConfiguration` → app lista

## ⚖️ Legal Colombia

- **Ley 1098/2006**: Código Infancia - interés superior, consentimiento
- **Ley 1581/2012**: Protección Datos - habeas data, datos sensibles menores
- **Ley 1996/2019**: Interceptación - solo con orden judicial
- **Protocolo firmado**: Antes de entregar equipo (ya en panel)

## 📁 Estructura

```
Sources/InstitutionalApp/
├── InstitutionalApp.swift      # @main entry
├── AppDelegate.swift           # APNs, background tasks
├── APIClient.swift             # Networking, APNs token
├── ConfigManager.swift         # ManagedAppConfiguration
├── TelemetryManager.swift      # BGTasks, telemetría, evasión
├── LocationManager.swift       # CLLocationManager, geocercas
├── DeviceActivityManager.swift # Screen Time (iOS 16+)
├── SOSManager.swift            # SOS voluntario
├── PushHandler.swift           # APNs, silent push
├── ConfigManager.swift         # ManagedAppConfiguration
├── EventLogger.swift           # Cola offline + flush
├── NetworkMonitor.swift        # NWPathMonitor
├── SOSManager.swift            # SOS voluntario
├── PushHandler.swift           # APNs, silent push
├── ContentView.swift           # UI principal
├── PermissionsView.swift       # Guía permisos
├── SettingsView.swift          # Ajustes
├── Resources/Info.plist
└── InstitutionalApp.entitlements
```

## 📄 Licencia

Uso institucional. Ver `LEGAL_COLOMBIA.md` en repo-web/DOCS/