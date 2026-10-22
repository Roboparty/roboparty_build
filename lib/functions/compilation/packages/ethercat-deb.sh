#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 wentywenty
#
# EtherCAT (IgH EtherCAT Master).
#
# Two halves, one file:
#   - compile_ethercat() builds the userspace (tool + libethercat + headers) into
#     the single deb "ethercat-dev" (runtime + development files).
#   - the artifact_kernel_version_parts__ethercat / pre_package_kernel_image__ethercat
#     hooks build the kernel modules (ec_master, ec_generic, ...) and stage them
#     into the kernel image (linux-image) during the kernel artifact build.
# No DKMS; modules ride with the kernel. Gated by INSTALL_ETHERCAT=yes.

function ethercat_upstream_url() {
	echo -n "https://gitlab.com/etherlab.org/ethercat.git"
}

# Pinned release (IgH tags are bare numbers, no "v" prefix).
function ethercat_upstream_ref() {
	echo -n "tag:1.6.13"
}

function add_host_dependencies__ethercat_build_tools() {
	[[ "${INSTALL_ETHERCAT:-no}" == "yes" ]] || return 0

	EXTRA_BUILD_DEPS+=("build-tools::autoconf" "build-tools::automake" "build-tools::libtool" "build-tools::pkg-config")
	if [[ "${host_arch:-$(uname -m)}" != "aarch64" ]]; then
		EXTRA_BUILD_DEPS+=("cross-arm64::gcc-aarch64-linux-gnu" "cross-arm64::g++-aarch64-linux-gnu")
	fi
}

# Contribute the module source revision to the kernel artifact version hash.
function artifact_kernel_version_parts__ethercat() {
	[[ "${INSTALL_ETHERCAT:-no}" == "yes" ]] || return 0

	declare -A GIT_INFO_ETHERCAT_MOD=([GIT_SOURCE]="$(ethercat_upstream_url)" [GIT_REF]="$(ethercat_upstream_ref)")
	run_memoized GIT_INFO_ETHERCAT_MOD "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_ETHERCAT_MOD

	artifact_version_parts["_ETHERCAT"]="ethercat${GIT_INFO_ETHERCAT_MOD[SHA1]:0:8}"
	artifact_version_part_order+=("0089-_ETHERCAT")
}

# Compile the IgH kernel modules and stage them into the kernel image.
# Runs in the kernel artifact build context (kernel-debs.sh pre_package_kernel_image).
function pre_package_kernel_image__ethercat() {
	[[ "${INSTALL_ETHERCAT:-no}" == "yes" ]] || return 0

	local upstream_url upstream_ref
	upstream_url="$(ethercat_upstream_url)"
	upstream_ref="$(ethercat_upstream_ref)"

	local install_mod_path="${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}"
	[[ -n "${install_mod_path}" ]] || exit_with_error "ethercat" "INSTALL_MOD_PATH is not set"
	[[ -n "${kernel_work_dir}" ]] || exit_with_error "ethercat" "kernel_work_dir is not set"

	fetch_from_repo "${upstream_url}" "ethercat" "${upstream_ref}"

	# Build the modules from a cached copy of the fetched source (never in-tree).
	local module_src="${SRC}/cache/sources/ethercat-modules-${kernel_version_family}"
	rm -rf "${module_src}"
	cp -a "${SRC}/cache/sources/ethercat" "${module_src}"
	rm -rf "${module_src}/.git"

	display_alert "ethercat" "Building kernel modules for ${kernel_version_family}" "info"
	run_host_command_logged "cd '${module_src}' && ./bootstrap"
	run_host_command_logged "cd '${module_src}' && ./configure --with-linux-dir='${kernel_work_dir}'"
	run_host_command_logged env ARCH="${ARCHITECTURE}" CROSS_COMPILE="${KERNEL_COMPILER}" \
		make -C "${module_src}" modules
	run_host_command_logged env ARCH="${ARCHITECTURE}" CROSS_COMPILE="${KERNEL_COMPILER}" \
		INSTALL_MOD_PATH="${install_mod_path}" make -C "${module_src}" modules_install

	depmod -b "${install_mod_path}" "${kernel_version_family}"
	rm -rf "${module_src}"
}

function compile_ethercat() {
	: "${artifact_version:?artifact_version is not set}"

	local upstream_url upstream_ref
	upstream_url="$(ethercat_upstream_url)"
	upstream_ref="$(ethercat_upstream_ref)"

	# Target triple; builds run on x86_64 hosts, so cross-compile by default.
	local cross_prefix="aarch64-linux-gnu"
	local host_arg="--host=${cross_prefix}"
	if [[ "$(uname -m)" == "aarch64" ]]; then
		host_arg=""
	fi

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-ethercat" cleanup_id tmp_dir # namerefs

	# Fetch pinned upstream source into cache and build in-place there.
	fetch_from_repo "${upstream_url}" "ethercat" "${upstream_ref}"
	local src_dir="${SRC}/cache/sources/ethercat"

	local pkg_dir="${tmp_dir}/ethercat-dev"
	mkdir -p "${pkg_dir}/DEBIAN"

	display_alert "ethercat" "Building userspace (kernel modules are built into the kernel image)" "info"
	run_host_command_logged "cd '${src_dir}' && ./bootstrap"
	run_host_command_logged "cd '${src_dir}' && ./configure ${host_arg} --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-kernel"
	run_host_command_logged "cd '${src_dir}' && make -j$(nproc)"
	run_host_command_logged "cd '${src_dir}' && make DESTDIR='${pkg_dir}' install"

	# Defensive: never ship kernel modules in this package (they live in linux-image).
	rm -rf "${pkg_dir}/lib/modules" "${pkg_dir}/usr/lib/modules"

	cat <<- END > "${pkg_dir}/DEBIAN/control"
		Package: ethercat-dev
		Version: ${artifact_version}
		Architecture: ${ARCH}
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: libc6
		Provides: ethercat, libethercat, ethercat-igh
		Replaces: ethercat-igh
		Conflicts: ethercat-igh
		Section: misc
		Priority: optional
		Description: IgH EtherCAT Master (runtime + development files)
		 Userspace for the IgH EtherCAT Master: the ethercat tool, libethercat,
		 headers and pkg-config/cmake files. Kernel modules are provided by the
		 board kernel image (no DKMS).
	END

	# Maintainer scripts, inlined (this package is small; no separate debian/ dir).
	cat <<- 'POSTINST' > "${pkg_dir}/DEBIAN/postinst"
		#!/bin/sh
		set -e
		# The IgH kernel modules ship inside the kernel image (no DKMS). Refresh
		# the module dependency cache, the linker cache and systemd's database.
		if command -v depmod >/dev/null 2>&1; then
			depmod -a >/dev/null 2>&1 || true
		fi
		if command -v ldconfig >/dev/null 2>&1; then
			ldconfig >/dev/null 2>&1 || true
		fi
		if command -v systemctl >/dev/null 2>&1; then
			systemctl daemon-reload >/dev/null 2>&1 || true
		fi
		exit 0
	POSTINST
	chmod 0755 "${pkg_dir}/DEBIAN/postinst"

	cat <<- 'PRERM' > "${pkg_dir}/DEBIAN/prerm"
		#!/bin/sh
		set -e
		if command -v systemctl >/dev/null 2>&1; then
			systemctl stop ethercat.service >/dev/null 2>&1 || true
			systemctl disable ethercat.service >/dev/null 2>&1 || true
		fi
		exit 0
	PRERM
	chmod 0755 "${pkg_dir}/DEBIAN/prerm"

	cat <<- 'POSTRM' > "${pkg_dir}/DEBIAN/postrm"
		#!/bin/sh
		set -e
		if command -v systemctl >/dev/null 2>&1; then
			systemctl daemon-reload >/dev/null 2>&1 || true
		fi
		exit 0
	POSTRM
	chmod 0755 "${pkg_dir}/DEBIAN/postrm"

	dpkg_deb_build "${pkg_dir}" "ethercat"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
