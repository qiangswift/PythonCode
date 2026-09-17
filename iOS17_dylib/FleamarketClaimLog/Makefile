TARGET = iphone:clang:latest:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Runner

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FleamarketClaimLog
FleamarketClaimLog_FILES = Tweak.xm
FleamarketClaimLog_CFLAGS = -fobjc-arc
FleamarketClaimLog_FRAMEWORKS = Foundation UIKit WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
