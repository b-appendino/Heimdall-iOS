include $(THEOS)/makefiles/common.mk

SOURCE_DIR = sources

TOOL_NAME = portresolver
portresolver_FILES = $(foreach ext, c cpp m mm x xm xi xmi swift, $(wildcard $(SOURCE_DIR)/*.$(ext)))
portresolver_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/tool.mk
