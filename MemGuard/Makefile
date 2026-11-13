SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)

MemGuard.dylib: MemGuard.m
	clang -arch arm64 -isysroot $(SDK) -miphoneos-version-min=14.0 \
	  -dynamiclib -fobjc-arc -O2 \
	  -framework UIKit -framework Foundation \
	  -install_name @rpath/MemGuard.dylib -o $@ MemGuard.m
	-ldid -S $@

clean:
	rm -f MemGuard.dylib
