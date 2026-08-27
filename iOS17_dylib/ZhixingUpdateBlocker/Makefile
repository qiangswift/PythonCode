ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Zhixing

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZhixingUpdateBlocker
ZhixingUpdateBlocker_FILES = Tweak.xm
ZhixingUpdateBlocker_CFLAGS = -fobjc-arc
ZhixingUpdateBlocker_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
