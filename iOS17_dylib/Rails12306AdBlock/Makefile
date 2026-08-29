ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = MTPotal

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Rails12306AdBlock
Rails12306AdBlock_FILES = Tweak.xm
Rails12306AdBlock_CFLAGS = -fobjc-arc
Rails12306AdBlock_FRAMEWORKS = UIKit Foundation WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
