#!/usr/bin/env bash
QT_SCALE_FACTOR=1
QT_AUTO_SCREEN_SCALE_FACTOR=0
QT_SCREEN_SCALE_FACTORS=1
exec ./build/beagley_cluster -platform cocoa

# macOS: use Cocoa platform plugin
export QT_QPA_PLATFORM=cocoa
