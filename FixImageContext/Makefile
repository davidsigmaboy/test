# Build on macOS with Xcode. Put fishhook.c / fishhook.h
# (https://github.com/facebook/fishhook) next to this file first.
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)

FixImageContext.dylib: FixImageContext.m fishhook.c fishhook.h
	clang -arch arm64 -isysroot $(SDK) -miphoneos-version-min=14.0 \
	  -dynamiclib -fobjc-arc -O2 \
	  -framework UIKit -framework Foundation -framework CoreGraphics \
	  -install_name @rpath/FixImageContext.dylib \
	  -o $@ FixImageContext.m fishhook.c
	-ldid -S $@

clean:
	rm -f FixImageContext.dylib
