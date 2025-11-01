%global shortcommit %(c=%{commit}; echo ${c:0:7})
# Debug info not supported with Go
%global debug_package %{nil}

Name: microshift-topolvm
Version: %{version}
Release: %{release}%{dist}
Summary: TopoLVM CSI Plugin for MicroShift
License: ASL 2.0
URL: https://github.com/openshift/microshift
Source0: https://github.com/openshift/microshift/archive/%{commit}/microshift-%{shortcommit}.tar.gz
ExclusiveArch: x86_64 aarch64
Requires: microshift = %{version}

%description
The microshift-topolvm package provides the required manifests for the TopoLVM CSI and the dependent
cert-manager to be installed on MicroShift.

%files
%dir %{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm
%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm/*
%{_sysconfdir}/greenboot/check/required.d/50_microshift_topolvm_check.sh
%config(noreplace) %{_sysconfdir}/microshift/config.d/01-disable-storage-csi.yaml

%package release-info
Summary: Release information for TopoLVM components for MicroShift
BuildArch: noarch
Requires: microshift-release-info = %{version}

%description release-info
The microshift-topolvm-release-info package provides release information files for this
release. These files contain the list of container image references used by the TopoLVM CSI.

%files release-info
%{_datadir}/microshift/release/release-topolvm-{x86_64,aarch64}.json

%prep
%setup -n microshift-%{commit}

%install
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm
install -p -m644 assets/optional/topolvm/*.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm

install -d -m755 %{buildroot}%{_sysconfdir}/microshift/config.d
install -p -m644 packaging/microshift/dropins/disable-storage-csi.yaml %{buildroot}%{_sysconfdir}/microshift/config.d/01-disable-storage-csi.yaml

install -d -m755 %{buildroot}%{_sysconfdir}/greenboot/check/required.d
install -p -m755 packaging/greenboot/microshift-topolvm-check.sh %{buildroot}%{_sysconfdir}/greenboot/check/required.d/50_microshift_topolvm_check.sh

install -d -m755 %{buildroot}%{_datadir}/microshift/release
install -p -m644 assets/optional/topolvm/release-topolvm-{x86_64,aarch64}.json %{buildroot}%{_datadir}/microshift/release
