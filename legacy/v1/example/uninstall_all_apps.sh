#!/bin/bash

adb shell pm list packages | grep -v "package:com.android" | while read -r package; do
    package=${package#package:}
    adb uninstall "$package"
done
