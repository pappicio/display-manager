OpenCreator Display Manager

OpenCreator Display Manager manages GrumpyScreen and HelixScreen on the FlashForge Creator 5.

It allows switching between the two interfaces using Klipper G-code macros.

Screen Selection

The selected interface is controlled by:

/usr/data/opencreator/screen

Accepted values:

grumpy

helix

The Display Manager monitors this file every second and switches the active interface whenever its contents change.

The installer creates this file with grumpy as the default value if it does not already exist. An existing valid selection is preserved.

Operating Modes

The operating mode (SoC or Tunneled) is detected when the Display Manager starts.

Moonraker addresses:

Mode

Moonraker address

SoC

127.0.0.1:7125

Tunneled

192.168.1.197:7125

The manager automatically updates the Moonraker address in the respective screen configuration.

Configuration Files

GrumpyScreen

/usr/data/opencreator/klipper/config/grumpyscreen.cfg

HelixScreen

/usr/data/helixscreen/config/settings.json

Only the Moonraker address is modified. Other configuration settings are preserved.

Klipper Integration

The installer creates or updates:

/usr/data/opencreator/klipper/config/oc-macros.cfg

It also adds the following include to:

/usr/data/opencreator/klipper/config/printer.base.cfg

# BEGIN display-manager include
[include oc-macros.cfg]
# END display-manager include

G-code Commands

The generated oc-macros.cfg contains two shell command definitions and two user-facing G-code macros.

Shell command definitions:

[gcode_shell_command switch_grumpy]
command: sh -c "echo grumpy > /usr/data/opencreator/screen"
timeout: 5.
verbose: False

[gcode_shell_command switch_helix]
command: sh -c "echo helix > /usr/data/opencreator/screen"
timeout: 5.
verbose: False

G-code macros:

[gcode_macro SCREEN_GRUMPY]
description: Switch to GrumpyScreen
gcode:
    RUN_SHELL_COMMAND CMD=switch_grumpy

[gcode_macro SCREEN_HELIX]
description: Switch to HelixScreen
gcode:
    RUN_SHELL_COMMAND CMD=switch_helix

How to Switch Screens

Run either command from the Klipper console:

SCREEN_GRUMPY – switches to GrumpyScreen.

SCREEN_HELIX – switches to HelixScreen.

You can also assign these macros to buttons in your preferred interface.

The switch is handled automatically by the Display Manager. No manual restart is required.

Log Files

The Display Manager and screen applications write their logs to:

Component

Log file

Display Manager

/tmp/oc-display-manager.log

GrumpyScreen

/tmp/grumpyscreen.log

HelixScreen

/tmp/HelixScreen.log

HelixScreen Launcher

/tmp/helixscreen-launcher.log

Requirements

Script Runner must be installed before installing Display Manager.

Both GrumpyScreen and HelixScreen must be available.

Klipper must support the gcode_shell_command extension.
