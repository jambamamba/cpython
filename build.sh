#!/bin/bash -e
set -e

#git clone https://github.com/python/cpython.git
#git checkout v3.12.0a2
#cd cpython

#to run this script:
#./build.sh target=x86 builddir=~/repos/factory-installer/x86-build package=true
#./build.sh target=arm builddir=~/repos/factory-installer/arm-build package=true pythondir=~/repos/factory-installer/x86-build/cpython

#globals:
PROJECT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SDK_DIR=/opt/usr_data/sdk

function parseArgs()
{
   for change in "$@"; do
      name="${change%%=*}"
      value="${change#*=}"
      eval $name="$value"
   done
}

function stripArchive()
{
	local target="x86"
	parseArgs $@
	if [ "${target}" == "x86" ]; then
		local strip="$(which strip)"
	else
		local strip="${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/aarch64-fslc-linux/aarch64-fslc-linux-strip"
	fi

	if [ -f "${strip}" ]; then
		find . -name "*.a" -exec $strip --strip-debug --strip-unneeded -p {} \;
		find . -name "*.so*" -exec $strip --strip-all -p {} \;
	fi
}

function package(){
	local target="x86"
	local builddir="x86-build"
	parseArgs $@
	local workdir="${builddir}/cpython"
	mkdir -p $workdir

	cp -r $PROJECT_DIR/Include "${workdir}/"
	cp -r $PROJECT_DIR/Lib "${workdir}/"

	if [ -d "${builddir}" ]; then
		if [ ! -f "${builddir}/pyconfig.h" ]; then
			echo "Cannot package, missing pyconfig.in in build-dir"
			return;
		fi
		cp "${builddir}/pyconfig.h" "${workdir}/"
		cp "${builddir}/libpython3.12.a" "${workdir}/"
		find "${builddir}/Modules/" -name "*.so*" -exec cp {} "${workdir}/" \;
		#copy dynamic libraries
		cp "${builddir}/libpython3.so" "${workdir}/"
		cp "${builddir}/libpython3.12.so.1.0" "${workdir}/"
		pushd "${workdir}/"
		ln -sf libpython3.12.so.1.0 libpython3.12.so
		stripArchive target="${target}"
		popd
	fi

	local SHA="$(sudo git config --global --add safe.directory $PROJECT_DIR;sudo git rev-parse --verify --short HEAD)"
	pushd "${workdir}/.."
	local packagedir="$(pwd)"
	tar -cvJf cpython.${SHA}.tar.xz "cpython"
	popd
	
	echo "Build folder is ${builddir}"
	echo "Package is built at ${packagedir}/cpython.${SHA}.tar.xz"
}

function buildX86(){
	parseArgs $@
	mkdir -p "${builddir}/cpython"
	pushd "${builddir}/cpython"
	if [ "$clean" == "true" ]; then
		rm -fr *
	fi
	rm -fr /tmp/cpython-x86.cache
	$PROJECT_DIR/configure \
		--enable-shared \
		--disable-test-modules \
		--disable-test-suite \
		--cache-file=/tmp/cpython-x86.cache \
		--enable-profiling \
		--enable-optimizations \
		--enable-loadable-sqlite-extensions \
		--enable-big-digits \
		--with-trace-refs \
		--disable-ipv6 
	#--with-lto=full --enable-bolt --with-pydebug  
	# make clean
	make -j
	popd
}

function buildArm(){
	local pythondir=/usr/bin
	parseArgs $@
	mkdir -p "${builddir}/cpython"
	pushd "${builddir}/cpython"

	if [ ! -f "${pythondir}/python" ]; then
		echo "FAILED: need python installed on build machine - missing: ${pythondir}/python"
		exit -1
	fi

	if [ ! -f ${SDK_DIR}/environment-setup-aarch64-fslc-linux ]; then
	  echo "FAILED: cross compiler SDK not set, cannot continue"
	  exit -1
	fi

	if [ "$clean" == "true" ]; then
		rm -fr *
	fi

	rm -fr /tmp/cpython-arm.cache
	echo "ac_cv_file__dev_ptmx=no
	ac_cv_file__dev_ptc=no
	">config.site

	source ${SDK_DIR}/environment-setup-aarch64-fslc-linux
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pythondir} #:/opt/usr_data/sdk/sysroots/x86_64-fslcsdk-linux/lib/
	#export CFLAGS="$CFLAGS -O3"
	#export CPPFLAGS="$CPPFLAGS -O3"
	#export LDFLAGS="$LDFLAGS -s"

	CONFIG_SITE=./config.site \
	PYTHONPATH=${PROJECT_DIR}/Lib/site-packages \
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pythondir}" \
	$PROJECT_DIR/configure \
		--enable-shared \
		--disable-test-modules \
		--disable-test-suite \
		--cache-file=/tmp/cpython-arm.cache \
		--enable-profiling \
		--enable-optimizations \
		--enable-loadable-sqlite-extensions \
		--enable-big-digits \
		--with-trace-refs \
		--disable-ipv6 \
		--with-build-python=${pythondir}/python \
		--host=aarch64-fslc-linux \
		--build=x86_64-pc-linux-gnu
	# make clean
	VERBOSE=1 make -j
	popd
}


function main(){
	local target="x86"
	local builddir="$(pwd)/${target}-build"
	local pythondir="${builddir}/../x86-build"
	parseArgs $@

	if [ "$MSYSTEM" != "" ]; then
		echo "Does not build cpython on Windows msys or Linux mingw"
		exit -1
	fi

	pushd $PROJECT_DIR
	if [ "$target" == "x86" ]; then
		buildX86 builddir="${builddir}"
	elif [ "$target" == "arm" ]; then
		buildArm builddir="${builddir}" pythondir="${pythondir}" #pythondir should be the x06-build dir
	fi

	if [ "$package" == "true" ]; then
		package builddir="${builddir}/cpython" target="${target}"
	fi
	popd
}

time main $@
