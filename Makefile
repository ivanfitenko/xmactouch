.PHONY: clean run

all: xmactouch

help:
	@echo make [ clean xmactouch run ]

clean:
	-rm -f xmactouch

xmactouch: xmactouch.m
	gcc -o xmactouch xmactouch.m -F/System/Library/PrivateFrameworks \
		-framework MultitouchSupport \
		-framework CoreFoundation -framework ApplicationServices -lobjc \

run:
	./xmactouch
