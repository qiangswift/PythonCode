ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = ChinaMobile

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChinaMobileSplashAdBlocker
ChinaMobileSplashAdBlocker_FILES = Tweak.xm
ChinaMobileSplashAdBlocker_CFLAGS = -fobjc-arc
ChinaMobileSplashAdBlocker_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
