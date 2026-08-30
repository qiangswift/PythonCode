ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = QDReaderAppStore

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QDReaderAutoCheckin
QDReaderAutoCheckin_FILES = Tweak.xm SwiftClosure.S
QDReaderAutoCheckin_CFLAGS = -fobjc-arc
QDReaderAutoCheckin_FRAMEWORKS = UIKit Foundation JavaScriptCore

include $(THEOS_MAKE_PATH)/tweak.mk
