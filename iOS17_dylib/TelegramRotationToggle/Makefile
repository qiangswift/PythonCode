ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Telegram Swiftgram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TelegramRotationToggle
TelegramRotationToggle_FILES = Tweak.xm
TelegramRotationToggle_CFLAGS = -fobjc-arc
TelegramRotationToggle_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
