# 12306 Ad Block

## v1.1.7 scoped page rules

This build does not replace 12306 private Objective-C methods. It injects
precise rules into confirmed web advertisement containers. File and console
logging have been removed.

The home-page banner remains visible at its native size because collapsing it
caused 12306 to restore an invalid scroll offset after tab switching. Its
private automatic-scroll timer is disabled, so the initially displayed item
does not rotate automatically. The order rule targets the statically confirmed `OrderAD` component located
after `.added-services-contain`, covering runtime builds that no longer expose
the older advertisement class name.

The travel-services miniapp was identified as preset app `60000002`. Its
confirmed `G0008` top-ad wrapper (`.top-ad-class`) and the horizontal
recommendation banner (`.train-mall`) immediately above “精彩旅程 尽在12306”
are removed.

Launch ads are handled at the UIKit window boundary. After `UIWindow` performs
its original `addSubview:`, only a descendant whose exact runtime class is
`UIAdBgView` is hidden. The tweak does not replace any `AdvertisService` or
`BonSplashAD` implementation and does not skip their initialization lifecycle.

A focused tweak for Railway 12306 5.9.6 (`cn.12306.rails12306`) that removes:

- the launch-page advertisement;
- the `OrderAD` advertisement at the bottom of the order page;
- the two confirmed advertisement banners on the travel-services page.

It injects only into Railway 12306 and never injects into SpringBoard. The
web rules target only confirmed advertisement wrappers; order, payment, and
normal service elements are not blocked.

The implementation was informed by static analysis of a user-supplied,
decrypted Railway 12306 5.9.6 IPA. The IPA and extracted files are not included.

## Build targets

- rootfull
- rootless (including Dopamine)
- roothide
