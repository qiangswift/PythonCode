ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Reeder

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReederPortraitLock
ReederPortraitLock_FILES = Tweak.xm
ReederPortraitLock_CFLAGS = -fobjc-arc
ReederPortraitLock_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
