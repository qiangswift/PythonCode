ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Telegram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TelegramSystemDNS
TelegramSystemDNS_FILES = Tweak.xm
TelegramSystemDNS_CFLAGS = -fobjc-arc
TelegramSystemDNS_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
