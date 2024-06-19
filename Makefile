.PHONY: all Heimdall portresolver set-plist-env clean

export THEOS=~/theos
export THEOS_MAKE_PATH=$THEOS/makesfiles
export THEOS_DEVICE_IP=localhost
export THEOS_DEVICE_PORT=2222
export THEOS_DEVICE_USER=mobile

SHELL_PATH = /var/jb/usr/bin/sh
PATH = /usr/local/sbin:/var/jb/usr/local/sbin:/usr/local/bin:/var/jb/usr/local/bin:/usr/sbin:/var/jb/usr/sbin:/usr/bin:/var/jb/usr/bin:/sbin:/var/jb/sbin:/bin:/var/jb/bin
HEIMDALL_DATABASE_PATH = /var/mobile/Documents/heimdall.sqlite3
APP_DUMP_DATABASE_PATH = /var/mobile/Documents/appDump.sqlite3
DAEMON_PLIST_PATH = /var/jb/Library/LaunchDaemons/
DAEMON_LABEL = de.tomcory.portresolver

all: set-plist-env Heimdall portresolver

set-plist-env:
	@echo "Setting plist environment information..."
	# Heimdall
	@plutil -replace DaemonLabel -string "$(DAEMON_LABEL)" Heimdall/Heimdall/Info.plist
	@plutil -replace PATH -string "$(PATH)" Heimdall/Heimdall/Info.plist
	@plutil -replace HeimdallDatabasePath -string "$(HEIMDALL_DATABASE_PATH)" Heimdall/Heimdall/Info.plist
	@plutil -replace AppDumpDatabasePath -string "$(APP_DUMP_DATABASE_PATH)" Heimdall/Heimdall/Info.plist
	@plutil -replace "SHELL" -string "$(SHELL_PATH)" Heimdall/Heimdall/Info.plist
	@plutil -replace DaemonPlistPath -string "$(DAEMON_PLIST_PATH)" Heimdall/Heimdall/Info.plist
	
	# PacketTunnel
	@plutil -replace HeimdallDatabasePath -string "$(HEIMDALL_DATABASE_PATH)" Heimdall/PacketTunnel/Info.plist
	@plutil -replace AppDumpDatabasePath -string "$(APP_DUMP_DATABASE_PATH)" Heimdall/PacketTunnel/Info.plist

	# PortResolver
	@plutil -replace EnvironmentVariables.PATH -string "$(PATH)" PortResolver/layout/Library/LaunchDaemons/de.tomcory.portresolver.plist
	@plutil -replace EnvironmentVariables.HeimdallDatabasePath -string "$(HEIMDALL_DATABASE_PATH)" PortResolver/layout/Library/LaunchDaemons/de.tomcory.portresolver.plist
	@plutil -replace EnvironmentVariables.AppDumpDatabasePath -string "$(APP_DUMP_DATABASE_PATH)" PortResolver/layout/Library/LaunchDaemons/de.tomcory.portresolver.plist
	@plutil -replace EnvironmentVariables.SHELL -string "$(SHELL_PATH)" PortResolver/layout/Library/LaunchDaemons/de.tomcory.portresolver.plist
	@plutil -replace EnvironmentVariables.DaemonLable -string "$(DAEMON_LABEL)" PortResolver/layout/Library/LaunchDaemons/de.tomcory.portresolver.plist

Heimdall:
	$(MAKE) do -C Heimdall

portresolver:
	$(MAKE) do -C portresolver

clean:
	$(MAKE) -C Heimdall clean
	$(MAKE) -C portresolver clean
