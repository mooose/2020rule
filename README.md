# 20-20-20 Rule - macOS Eye Care App (Swift)

Eine native macOS-Menubar-Anwendung in **Swift/AppKit**, die die **20-20-20 Augenregel** durchsetzt: Alle 20 Minuten erscheint ein Fullscreen-Overlay für 20 Sekunden.

## Features

- Automatische Erinnerungen mit Fullscreen-Overlay
- Inaktivitätserkennung (Timer pausiert bei Idle-Zeit)
- Statistik-Tracking in SQLite (heute, Woche, Monat)
- Anpassbare Zeiten und Overlay-Deckkraft direkt im Menü
- Auswahl für Overlay-Monitor: beide, nur links oder nur rechts
- Optionales Box-Breathing während der Pause (4-4-4-4)
- Pause manuell entsperren mit `Esc` 3x
- Option: Start beim Login (macOS 13+)
- Persistente Konfiguration in JSON
- Pause/Fortsetzen direkt aus der Menu Bar
- Menüleisten-App ohne Dock-Icon

## Voraussetzungen

- macOS 12 oder neuer
- Xcode Command Line Tools (inkl. Swift)

## Build

```bash
./scripts/build.sh
```

Das Skript erstellt:

- Binary: `build/2020Rule`
- App-Bundle: `build/2020Rule.app`

Installation:

```bash
cp -r build/2020Rule.app /Applications/
```

## Konfiguration

Datei:

`~/Library/Application Support/2020Rule/config.json`

Standardwerte:

```json
{
  "work_duration_minutes": 20,
  "break_duration_seconds": 20,
  "idle_threshold_minutes": 5,
  "auto_start_on_login": true,
  "pause_on_fullscreen_app": false,
  "notification_sound": true,
  "overlay_opacity": 0.95,
  "first_run": true,
  "show_box_breathing": false,
  "overlay_screen_mode": "both"
}
```

## Statistikdatenbank

SQLite-Datei:

`~/Library/Application Support/2020Rule/stats.db`

## Architektur (Swift)

- `ConfigManager`: Laden/Speichern der Konfiguration
- `StatsStore`: SQLite-Persistenz für Breaks/Sessions/Reports
- `TimerManager`: Zustandsmaschine für Work/Break/Pause
- `ActivityMonitor`: Idle-Erkennung via `CGEventSource`
- `OverlayWindowController`: Fullscreen-Overlay auf allen oder ausgewählten Screens
- `MenuBarController`: Statusanzeige und Benutzeraktionen
- `AppCoordinator`: Verdrahtung aller Komponenten

## Projektstruktur

```text
2020rule/
├── Sources/Rule2020/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── Core/
│   └── UI/
├── scripts/build.sh
└── resources/
```

## Hinweise

- Die bestehenden Go-Dateien bleiben im Repository, die aktuelle Runtime ist die Swift-Version.
- Beim ersten Start sind ggf. macOS-Berechtigungen erforderlich.
