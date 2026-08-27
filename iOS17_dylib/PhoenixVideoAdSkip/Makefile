ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Eggplant

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoenixVideoAdSkip
PhoenixVideoAdSkip_FILES = Tweak.xm
PhoenixVideoAdSkip_CFLAGS = -fobjc-arc
PhoenixVideoAdSkip_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
