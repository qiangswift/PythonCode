ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = LCIphoneAdhocIP

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LechengSplashSkip
LechengSplashSkip_FILES = Tweak.xm
LechengSplashSkip_CFLAGS = -fobjc-arc
LechengSplashSkip_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

