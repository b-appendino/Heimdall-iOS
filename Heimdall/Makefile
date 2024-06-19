TARGET = iphone:16.5
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Heimdall
THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME = Heimdall
Heimdall_XCODE_SCHEME = Heimdall
Heimdall_CODESIGN_FLAGS = -SHeimdallEntitlements.xml

include $(THEOS_MAKE_PATH)/xcodeproj.mk
