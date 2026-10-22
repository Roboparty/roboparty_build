#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2026 wentywenty
#
# Artifact "ethercat": IgH EtherCAT Master userspace, packaged as "ethercat-dev".
# The kernel modules are built into the kernel image by the pre_package_kernel_image
# hook defined in compilation/packages/ethercat-deb.sh.

function artifact_ethercat_config_dump() {
	artifact_input_variables[BOARD]="${BOARD}"
}

function artifact_ethercat_prepare_version() {
	artifact_version="undetermined"        # outer scope
	artifact_version_reason="undetermined" # outer scope

	declare short_hash_size=4

	declare -A GIT_INFO_ETHERCAT=([GIT_SOURCE]="$(ethercat_upstream_url)" [GIT_REF]="$(ethercat_upstream_ref)")
	run_memoized GIT_INFO_ETHERCAT "git2info" memoized_git_ref_to_info
	debug_dict GIT_INFO_ETHERCAT

	[[ "${GIT_INFO_ETHERCAT[SHA1]}" =~ ^[0-9a-f]{40}$ ]] || exit_with_error "SHA1 is not sane: '${GIT_INFO_ETHERCAT[SHA1]}'"
	declare short_sha1="${GIT_INFO_ETHERCAT[SHA1]:0:${short_hash_size}}"

	declare hash_files="undetermined"
	calculate_hash_for_bash_deb_artifact "compilation/packages/ethercat-deb.sh"
	declare bash_hash="${hash_files}"
	declare bash_hash_short="${bash_hash:0:${short_hash_size}}"

	artifact_version="1-SA${short_sha1}-B${bash_hash_short}"

	declare -a reasons=(
		"ethercat upstream git revision \"${GIT_INFO_ETHERCAT[SHA1]}\""
		"framework bash hash \"${bash_hash}\""
	)
	artifact_version_reason="${reasons[*]}"

	artifact_map_packages=(["ethercat"]="ethercat-dev")

	artifact_name="ethercat"
	artifact_type="deb"
	artifact_deb_repo="global"
	artifact_deb_arch="${ARCH}"

	return 0
}

function artifact_ethercat_build_from_sources() {
	LOG_SECTION="compile_ethercat" do_with_logging compile_ethercat
}

function artifact_ethercat_cli_adapter_pre_run() {
	declare -g ARMBIAN_COMMAND_REQUIRE_BASIC_DEPS="yes"
	cli_standard_relaunch_docker_or_sudo
}

function artifact_ethercat_cli_adapter_config_prep() {
	use_board="yes" prep_conf_main_minimal_ni < /dev/null
}

function artifact_ethercat_get_default_oci_target() {
	artifact_oci_target_base="${GHCR_SOURCE}/roboparty/os/"
}

function artifact_ethercat_is_available_in_local_cache() {
	is_artifact_available_in_local_cache
}

function artifact_ethercat_is_available_in_remote_cache() {
	is_artifact_available_in_remote_cache
}

function artifact_ethercat_obtain_from_remote_cache() {
	obtain_artifact_from_remote_cache
}

function artifact_ethercat_deploy_to_remote_cache() {
	upload_artifact_to_oci
}
