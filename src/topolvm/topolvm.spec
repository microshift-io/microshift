#
# Beginning of the header copied from microshift/packaging/rpm/microshift.spec
#
%global shortcommit %(c=%{commit}; echo ${c:0:7})
# Debug info not supported with Go
%global debug_package %{nil}

Name: microshift
Version: %{version}
Release: %{release}%{dist}
Summary: MicroShift service
License: ASL 2.0
URL: https://github.com/openshift/microshift
Source0: https://github.com/openshift/microshift/archive/%{commit}/microshift-%{shortcommit}.tar.gz

ExclusiveArch: x86_64 aarch64

%description
The microshift package provides an OpenShift Kubernetes distribution optimized for small form factor and edge computing.

%prep
%setup -n microshift-%{commit}
#
# End of the header copied from microshift/packaging/rpm/microshift.spec
#

%package topolvm
Summary: TopoLVM CSI Plugin for MicroShift
ExclusiveArch: x86_64 aarch64
Requires: microshift = %{version}

%description topolvm
The microshift-topolvm package provides the required manifests for the TopoLVM CSI and the dependent
cert-manager to be installed on MicroShift.

%install
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm
install -d -m755 %{buildroot}%{_sysconfdir}/microshift/config.d

install -p -m644 assets/optional/topolvm/*.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm
install -p -m644 packaging/microshift/dropins/disable-storage-csi.yaml %{buildroot}%{_sysconfdir}/microshift/config.d/01-disable-storage-csi.yaml

install -d -m755 %{buildroot}%{_sysconfdir}/greenboot/check/required.d
install -p -m755 packaging/greenboot/microshift-topolvm-check.sh %{buildroot}%{_sysconfdir}/greenboot/check/required.d/50_microshift_topolvm_check.sh

%files topolvm
%dir %{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm
%{_prefix}/lib/microshift/manifests.d/001-microshift-topolvm/*
%{_sysconfdir}/greenboot/check/required.d/50_microshift_topolvm_check.sh
%config(noreplace) %{_sysconfdir}/microshift/config.d/01-disable-storage-csi.yaml
