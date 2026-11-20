# OpenCreator Display Manager

Gestisce GrumpyScreen e HelixScreen sulla FlashForge Creator 5.

## Selezione

File: /usr/data/opencreator/screen

Valori ammessi:
- grumpy
- helix

Il servizio controlla il file ogni secondo.

## Modalità

La modalità SoC/Tunneled viene rilevata all'avvio.

SoC:
127.0.0.1:7125

Tunneled:
192.168.1.197:7125

## Configurazioni

Grumpy:
 /usr/data/opencreator/klipper/config/grumpyscreen.cfg

Helix:
 /usr/data/helixscreen/config/settings.json

Il manager aggiorna solo l'indirizzo Moonraker.

## Log

/tmp/oc-display-manager.log
/tmp/grumpyscreen.log
/tmp/HelixScreen.log
/tmp/helixscreen-launcher.log
