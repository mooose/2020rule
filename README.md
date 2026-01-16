# 20-20-20 Rule - macOS Eye Care App

Eine macOS-Anwendung zur Durchsetzung der **20-20-20 Augenregel**: Alle 20 Minuten wird ein Fullscreen-Overlay für 20 Sekunden angezeigt, das Sie dazu zwingt, vom Bildschirm wegzuschauen und in die Ferne zu blicken.

## Features

- **Automatische Erinnerungen**: Alle 20 Minuten erscheint ein nicht-ignorierbares Fullscreen-Overlay
- **Inaktivitätserkennung**: Timer pausiert automatisch wenn Sie nicht am Computer sind
- **Statistik-Tracking**: Verfolgen Sie Ihre Compliance-Rate (täglich, wöchentlich, monatlich)
- **Anpassbare Timer**: Konfigurieren Sie Work- und Break-Dauer nach Ihren Bedürfnissen
- **Pause-Funktion**: Manuelles Pausieren für Meetings oder Präsentationen
- **Menu Bar Integration**: Diskretes Menu Bar Icon ohne Dock-Präsenz

## Installation

### Voraussetzungen

- macOS 10.15 (Catalina) oder neuer
- Go 1.21 oder neuer (für Build)

### Build & Installation

1. Repository klonen:
```bash
git clone <repository-url>
cd 2020rule
```

2. Dependencies installieren:
```bash
go mod download
```

3. App bauen:
```bash
./scripts/build.sh
```

4. Nach `/Applications` kopieren:
```bash
cp -r build/2020Rule.app /Applications/
```

5. App starten:
- Öffnen Sie `/Applications/2020Rule.app`
- Beim ersten Start werden Sie nach Accessibility-Berechtigungen gefragt
- Erlauben Sie diese in den Systemeinstellungen

## Verwendung

### Menu Bar

Nach dem Start erscheint ein Icon in der Menu Bar mit Countdown bis zur nächsten Pause.

**Menu-Optionen:**
- **Nächste Pause in**: Zeigt verbleibende Zeit
- **Pausieren/Fortsetzen**: Timer manuell steuern
- **Statistiken**: Compliance-Daten einsehen
- **Beenden**: App beenden

### Konfiguration

Konfigurationsdatei: `~/Library/Application Support/2020Rule/config.json`

```json
{
  "work_duration_minutes": 20,
  "break_duration_seconds": 20,
  "idle_threshold_minutes": 5,
  "auto_start_on_login": true,
  "notification_sound": true,
  "overlay_opacity": 0.95
}
```

### Datenbank

Statistiken werden gespeichert in: `~/Library/Application Support/2020Rule/stats.db`

## Architektur

```
┌─────────────── App Coordinator ────────────────┐
│                                                 │
├─ Config Manager      (JSON persistence)        │
├─ Stats Store         (SQLite)                  │
├─ Timer Manager       (State machine)           │
├─ Activity Monitor    (Idle detection)          │
├─ Overlay Window      (Fullscreen display)      │
└─ Menu Bar UI         (Status & controls)       │
```

## Entwicklung

### Projekt-Struktur

```
2020rule/
├── cmd/2020rule/           # Entry point
├── internal/
│   ├── app/                # Main coordinator
│   ├── config/             # Configuration management
│   ├── stats/              # Statistics & database
│   ├── timer/              # Timer state machine
│   ├── activity/           # Idle detection
│   ├── overlay/            # Fullscreen window
│   └── ui/                 # Menu bar UI
├── scripts/                # Build scripts
└── resources/              # App icons & assets
```

### Dependencies

- **DarwinKit**: Native macOS API bindings
- **Menuet**: Menu bar integration
- **Idle**: User activity detection
- **SQLite**: Statistics storage

### Tests ausführen

```bash
go test ./...
```

## Fehlerbehebung

### Overlay erscheint nicht

- Überprüfen Sie Accessibility-Berechtigungen in Systemeinstellungen
- Stellen Sie sicher, dass die App nicht im Hintergrund pausiert ist

### Timer pausiert ständig

- Überprüfen Sie die Idle-Threshold in der Konfiguration
- Möglicherweise erkennt das System Ihre Aktivität nicht korrekt

### Statistiken werden nicht gespeichert

- Überprüfen Sie Schreibrechte für `~/Library/Application Support/2020Rule/`
- Prüfen Sie die Logs auf Datenbankfehler

## Lizenz

[Ihre Lizenz hier]

## Credits

Entwickelt zur Unterstützung der Augengesundheit bei langer Bildschirmarbeit.

Basierend auf der **20-20-20 Regel** von Augenärzten empfohlen.
