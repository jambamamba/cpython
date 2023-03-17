#!/bin/bash -e
set -e

#git clone https://github.com/python/cpython.git
#git checkout v3.12.0a2
#cd cpython

#globals:
PROJECT_DIR=$(pwd)
SDK_DIR=/opt/usr_data/sdk

function parseArgs()
{
   for change in "$@"; do
      name="${change%%=*}"
      value="${change#*=}"
      eval $name="$value"
   done
}

function pushBuildDir(){
	local workdir="workdir" #$(mktemp -d) #"/tmp/tmp.VqPGhjq76t"
	mkdir -p "${workdir}"
	pushd $workdir
}

function popBuildDir(){
	popd
}

function buildX86(){
	parseArgs $@
	mkdir -p x86-build
	pushd x86-build
	if [ "$clean" == "true" ]; then
		rm -fr *
	fi
	$PROJECT_DIR/configure --enable-shared --enable-profiling --enable-optimizations --enable-loadable-sqlite-extensions --enable-big-digits --with-trace-refs --disable-ipv6 
	#--with-lto=full --enable-bolt --with-pydebug  
	make -j
	popd
}

function buildArm(){
	parseArgs $@
	mkdir -p arm-build
	pushd arm-build
	if [ "$clean" == "true" ]; then
		rm -fr *
	fi

	echo "ac_cv_file__dev_ptmx=no
	ac_cv_file__dev_ptc=no
	">config.site

	source ${SDK_DIR}/environment-setup-aarch64-fslc-linux
	export CONFIG_SITE=./config.site
	export PYTHONPATH=../Lib/site-packages
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:../x86-build #:/opt/usr_data/sdk/sysroots/x86_64-fslcsdk-linux/lib/
	export PYTHONPATH=../Lib/site-packages
	#export CFLAGS="-O3"
	#export CPPFLAGS="-O3"
	#export LDFLAGS="-s"

	$PROJECT_DIR/configure --enable-shared --enable-profiling --enable-optimizations --enable-loadable-sqlite-extensions --enable-big-digits --with-trace-refs --disable-ipv6 --with-build-python=../x86-build/python --host=aarch64-fslc-linux --build=x86_64-pc-linux-gnu
	VERBOSE=1 make -j

	popd
}

function stripArchive()
{
	if [ "${target}" == "arm" ]; then 
		local strip="${SDK_DIR}/sysroots/x86_64-fslcsdk-linux/usr/bin/aarch64-fslc-linux/aarch64-fslc-linux-strip"
	else
		local strip=$(which strip)
	fi
	find . -name "*.a" -exec $strip --strip-debug --strip-unneeded -p {} \;
	find . -name "*.so*" -exec $strip --strip-all -p {} \;
}

function package(){
	local target=""
	parseArgs $@
	local installdir="${target}-installs/installs"
	mkdir -p "${installdir}"
	rm -fr "${installdir}/*"

	rsync -uav $PROJECT_DIR/Include "${installdir}/include"
	rsync -uav $PROJECT_DIR/Lib "${installdir}/"
	find "${installdir}/Lib" -name __pycache__ -type d -exec rm -fr {} \; || true
	rm -fr "${installdir}/Lib/test"

	mkdir -p "${installdir}/lib"
	cp ${target}-build/pyconfig.h "${installdir}/lib/"
#	cp ${target}-build/libpython3.12.a "${installdir}/lib/"
	find ${target}-build/Modules/ -name "*.so*" -exec cp {} "${installdir}/lib/" \;
	# copy dynamic libraries
	cp ${target}-build/libpython3.so "${installdir}/lib/"
	cp ${target}-build/libpython3.12.so.1.0 "${installdir}/lib/"
	pushd "${installdir}/lib/"
	ln -sf libpython3.12.so.1.0 libpython3.12.so
	stripArchive target=${target}
	cd ../../
	local SHA="$(sudo git config --global --add safe.directory $PROJECT_DIR;sudo git rev-parse --verify --short HEAD)"
	local output="cpython-$SHA-${target}.tar.xz"
	echo "Package is built at $(pwd)/${output}"
	tar -cvJf "${output}" installs
	if [ -d /home/$USER/Downloads ]; then
	   sudo cp -f "${output}" /home/$USER/Downloads/
	   echo "Package is availabled at /home/$USER/Downloads/${output}"
	fi
	popd
}

function main(){
	parseArgs $@
	pushBuildDir
	buildX86
	package target="x86"
	buildArm
	package target="arm"
	popBuildDir
}

time main $@

