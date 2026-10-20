# LyroTV v0.1.0

Ein eigenständiger Glass-Launcher für Samsung Tizen über TizenBrew.

## Installation
TizenBrew öffnen → Modulmanager → GitHub-Modul hinzufügen → `liadbrooo/lyrotv` eingeben → LyroTV starten.

## Enthalten
- Liquid-Glass-Startseite und TV-Fernbedienungsnavigation
- Installierte Apps über `tizen.application.getAppsInfo` ermitteln
- Apps über `tizen.application.launch` starten (sofern von TV und TizenBrew erlaubt)
- Favoriten, Verlauf und manuelle Tizen-App-IDs
- Akzentfarben, Performance-Modus und optionale Start-App
- Lokale Speicherung ohne Server oder Konto

## Grenzen
Die originale Samsung-Oberfläche wird nicht ersetzt. Automatischer Start beim Einschalten ist nicht garantiert. Die Tizen-API-Funktionen müssen auf dem echten Samsung-TV noch getestet werden. Bei fehlenden Berechtigungen zeigt LyroTV eine Fehlermeldung.

## Vorschau
`app/index.html` im Browser öffnen; App-Start ist dort nicht möglich.
