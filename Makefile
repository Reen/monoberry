PROJECT=monoberry
TARGET=target
MONOSRC=mono
PREFIX=/usr/local
SYSTEM:=$(shell uname)
BASE:=$(shell pwd)
ARCH_ARM:=arm-unknown-nto-qnx8.0.0eabi
ARCH_X86:=i486-pc-nto-qnx8.0.0

SUBPROJECTS=glib libffi libgdiplus mono opentk

ifeq (${SYSTEM}, Darwin)
  DESTDIR=/Developer/SDKs/MonoBerry
  NDK=/Applications/bbndk
  LIBTOOLIZE=glibtoolize
  ACLOCAL_FLAGS="-I/usr/local/share/aclocal"
else
  DESTDIR=/usr/local/share/monoberry
  NDK=/opt/bbndk
  LIBTOOLIZE=libtoolize
  ACLOCAL_FLAGS=
endif

VERSION:=$(or $(shell git describe --exact-match 2>/dev/null), HEAD)
RELEASE_NAME:=$(shell echo ${PROJECT}-${VERSION}.tgz)

LDFLAGS_ARM="-L${NDK}/target/qnx6/armle-v7/lib -L${NDK}/target/qnx6/armle-v7/usr/lib"
LDFLAGS_X86="-L${NDK}/target/qnx6/x86/lib -L${NDK}/target/qnx6/x86/usr/lib"

all:	cli mono libs

cli:	${TARGET}/tool/monoberry.exe

${TARGET}/tool/monoberry.sh: tooling/monoberry.sh
	cp $< $@

target/tool/monoberry.exe: tooling/tool.csproj tooling/*.cs
	@rm -rf tooling/bin/Release
	@echo Building MonoBerry CLI tool ...
	@xbuild $< /p:Configuration=Release > /dev/null
	@mkdir -p target/tool
	@cp tooling/bin/Release/*.exe tooling/bin/Release/*.dll tooling/monoberry.sh ${TARGET}/tool

clean:
	@rm -rf target tmp\
		libappdesc/bin libappdesc/obj\
		libblackberry/bin libblackberry/obj
	@for i in ${SUBPROJECTS}; do\
		cd "$$i" 2> /dev/null && test -r Makefile && make clean && cd ..;\
	done || true

install:
	@sh install.sh

release:	all
	@echo Building release ${VERSION} ...
	@env COPYFILE_DISABLE=true tar c target install.sh README.md LICENSE | gzip -9 > ${RELEASE_NAME}
	@du -sh ${RELEASE_NAME}

libs:	${TARGET}/lib/libblackberry.dll ${TARGET}/lib/libappdesc.dll

${TARGET}/lib/libappdesc.dll: libappdesc/libappdesc.csproj libappdesc/*.cs
	@echo Building libappdesc ...
	@xbuild $< /p:Configuration=Release > /dev/null
	@mkdir -p ${TARGET}/lib
	@cp libappdesc/bin/Release/*.dll target/lib

${TARGET}/lib/libblackberry.dll: libblackberry/libblackberry.csproj libblackberry/*.cs
	@echo Building libblackberry ...
	@xbuild $< /p:Configuration=Release > /dev/null
	@mkdir -p ${TARGET}/lib
	@cp libblackberry/bin/Release/*.dll target/lib

#helloworld: helloworld/*.cs helloworld/*.xml
#	@xbuild helloworld/helloworld.csproj /p:Configuration=Release

mono:	${TARGET}/lib/mscorlib.dll ${TARGET}/target/armle-v7/bin/mono ${TARGET}/target/armle-v7/lib/libgdiplus.so.0 ${TARGET}/target/x86/bin/mono ${TARGET}/target/x86/lib/libgdiplus.so.0

libffi-arm: libffi/${ARCH_ARM}/.libs/libffi.a
libffi/${ARCH_ARM}/.libs/libffi.a: libffi/configure
	cd libffi &&\
	. ${NDK}/bbndk-env.sh &&\
	env LDFLAGS=${LDFLAGS_ARM} ./configure --host=${ARCH_ARM} && make

libffi-x86: libffi/${ARCH_X86}/.libs/libffi.a
libffi/${ARCH_X86}/.libs/libffi.a: libffi/configure
	cd libffi &&\
	. ${NDK}/bbndk-env.sh &&\
	env LDFLAGS=${LDFLAGS_X86} ./configure --host=${ARCH_X86} && make

glib-x86: tmp/glib-x86
tmp/glib-x86: glib/autogen.sh libffi/${ARCH_X86}/.libs/libffi.a
	cp glib.cache glib/config.cache
	cd glib &&\
	. ${NDK}/bbndk-env.sh &&\
	env LDFLAGS="-lsocket"\
		CFLAGS="-DSA_RESTART=0 -D_QNX_SOURCE"\
		LIBFFI_CFLAGS="-I${BASE}/libffi/${ARCH_X86}/include"\
		LIBFFI_LIBS="${BASE}/libffi/${ARCH_X86}/libffi.la"\
		./autogen.sh --host=${ARCH_X86} --enable-static=yes --enable-shared=yes\
		--cache-file=config.cache &&\
	make clean &&\
	cd glib &&\
	make -k || test -r .libs/libglib-2.0.a
	install -d $@
	cp -r glib/glib/*.lo glib/glib/.libs glib/glib/pcre/*.lo glib/glib/pcre/.libs $@

glib-arm: tmp/glib-arm
tmp/glib-arm: glib/autogen.sh libffi/${ARCH_ARM}/.libs/libffi.a
	cp glib.cache glib/config.cache
	cd glib &&\
	. ${NDK}/bbndk-env.sh &&\
	env LDFLAGS="-lsocket"\
		CFLAGS="-DSA_RESTART=0 -D_QNX_SOURCE"\
		LIBFFI_CFLAGS="-I${BASE}/libffi/${ARCH_ARM}/include"\
		LIBFFI_LIBS="${BASE}/libffi/${ARCH_ARM}/libffi.la"\
		./autogen.sh --host=${ARCH_ARM} --enable-static=yes --enable-shared=yes\
		--cache-file=config.cache &&\
	make clean &&\
	cd glib &&\
	make -k || test -r .libs/libglib-2.0.a
	install -d $@
	cp -r glib/glib/*.lo glib/glib/.libs glib/glib/pcre/*.lo glib/glib/pcre/.libs $@

libgdiplus-arm: ${TARGET}/target/armle-v7/lib/libgdiplus.so.0
${TARGET}/target/armle-v7/lib/libgdiplus.so.0: libgdiplus/autogen.sh tmp/glib-arm
	cd libgdiplus &&\
		. ${NDK}/bbndk-env.sh &&\
		env LIBTOOLIZE=${LIBTOOLIZE} ACLOCAL_FLAGS=${ACLOCAL_FLAGS} CFLAGS="-I$$QNX_TARGET/usr/include/freetype2 -I../cairo/src -I${BASE}/glib -I${BASE}/glib/glib"\
			./autogen.sh --with-intcairo --enable-static=no --enable-shared=yes --host=${ARCH_ARM} &&\
		make clean &&\
		make
	cd libgdiplus/src &&\
		. ${NDK}/bbndk-env.sh &&\
		/bin/bash ../libtool --tag=CC --mode=link ${ARCH_ARM}-gcc\
			-o libgdiplus.la -rpath /usr/local/lib *.lo -lfontconfig\
			../cairo/src/libcairo.la ${BASE}/tmp/glib-arm/*.lo -lpng -ljpeg
	mkdir -p `dirname $@`
	install libgdiplus/src/.libs/libgdiplus.so.0 $@

libgdiplus-x86: ${TARGET}/target/x86/lib/libgdiplus.so.0
${TARGET}/target/x86/lib/libgdiplus.so.0: libgdiplus/autogen.sh tmp/glib-x86
	cd libgdiplus &&\
		. ${NDK}/bbndk-env.sh &&\
		env LIBTOOLIZE=${LIBTOOLIZE} ACLOCAL_FLAGS=${ACLOCAL_FLAGS} CFLAGS="-I$$QNX_TARGET/usr/include/freetype2 -I../cairo/src -I${BASE}/glib -I${BASE}/glib/glib"\
			./autogen.sh --with-intcairo --enable-static=no --enable-shared=yes --host=${ARCH_X86} &&\
		make clean &&\
		make
	cd libgdiplus/src &&\
		. ${NDK}/bbndk-env.sh &&\
		/bin/bash ../libtool --tag=CC --mode=link ${ARCH_X86}-gcc\
			-o libgdiplus.la -rpath /usr/local/lib *.lo -lfontconfig\
			../cairo/src/libcairo.la ${BASE}/tmp/glib-x86/*.lo -lpng -ljpeg
	mkdir -p `dirname $@`
	install libgdiplus/src/.libs/libgdiplus.so.0 $@

### MONO RUNTIME ##############################################################

${TARGET}/target/armle-v7/bin/mono: ${MONOSRC}/autogen.sh
	cd ${MONOSRC} &&\
		. ${NDK}/bbndk-env.sh &&\
		env LDFLAGS=${LDFLAGS_ARM} ./autogen.sh --host=${ARCH_ARM} --with-xen-opt=no\
			--with-large-heap=no --disable-mcs-build --enable-small-config=yes &&\
		make clean && make
	mkdir -p `dirname $@`
	install ${MONOSRC}/mono/mini/mono $@

rebuild-mono-arm:
	cd ${MONOSRC} && . ${NDK}/bbndk-env.sh && env LDFLAGS=${LDFLAGS_ARM} make
		
${TARGET}/target/x86/bin/mono: ${MONOSRC}/autogen.sh
	cd ${MONOSRC} &&\
		. ${NDK}/bbndk-env.sh &&\
		env LDFLAGS=${LDFLAGS_X86} ./autogen.sh --host=${ARCH_X86} --with-xen-opt=no\
			--with-large-heap=no --disable-mcs-build --enable-small-config=yes &&\
		make clean && make
	mkdir -p `dirname $@`
	install ${MONOSRC}/mono/mini/mono $@

rebuild-mono-x86:
	cd ${MONOSRC} && . ${NDK}/bbndk-env.sh && env LDFLAGS=${LDFLAGS_X86} make

### MONO CORE LIBRARY #########################################################

mono-lib: ${TARGET}/lib/mscorlib.dll

${TARGET}/lib/mscorlib.dll: ${MONOSRC}/autogen.sh
	cd ${MONOSRC} && ( ./autogen.sh || ./autogen.sh ) && make
	mkdir -p `dirname $@`
	install ${MONOSRC}/mcs/class/lib/net_4_5/mscorlib.dll $@

${MONOSRC}/autogen.sh: submodules
glib/autogen.sh: submodules
libffi/configure: submodules
libgdiplus/autogen.sh: submodules

submodules: .gitmodules
	@git submodule update --init --recursive
	
reset-subprojects:
	@for i in ${SUBPROJECTS}; do\
		cd "$$i" && git clean -xfd && git reset --hard HEAD && cd ..;\
	done || true

.PHONY: clean all install glib-arm glib-x86 libgdiplus-arm libgdiplus-x86
