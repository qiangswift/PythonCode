ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeCameraEnhancer
AwemeCameraEnhancer_FILES = Tweak.xm
AwemeCameraEnhancer_CFLAGS = -fobjc-arc
AwemeCameraEnhancer_FRAMEWORKS = Foundation UIKit Photos

include $(THEOS_MAKE_PATH)/tweak.mk
