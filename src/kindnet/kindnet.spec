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

%package kindnet
Summary: kindnet CNI for MicroShift
ExclusiveArch: x86_64 aarch64
Requires: microshift = %{version}

%description kindnet
The microshift-kindnet package provides the required manifests for the kindnet CNI and the dependent
kube-proxy to be installed on MicroShift.

%package kindnet-release-info
Summary: Release information for kindnet CNI for MicroShift
BuildArch: noarch
Requires: microshift-release-info = %{version}

%description kindnet-release-info
The microshift-kindnet-release-info package provides release information files for this
release. These files contain the list of container image references used by the kindnet CNI
with the dependent kube-proxy for MicroShift.

%install
install -d -m755 %{buildroot}/%{_sysconfdir}/microshift/config.d
install -d -m755 %{buildroot}/%{_sysconfdir}/microshift/manifests.d
install -d -m755 %{buildroot}%{_sysconfdir}/crio/crio.conf.d

# kindnet
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet
install -d -m755 %{buildroot}%{_sysconfdir}/systemd/system
# Copy all the manifests except the arch specific ones
install -p -m644 assets/optional/kindnet/0* %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet
install -p -m644 assets/optional/kindnet/kustomization.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet
install -p -m644 packaging/kindnet/00-disableDefaultCNI.yaml %{buildroot}%{_sysconfdir}/microshift/config.d/00-disableDefaultCNI.yaml
install -p -m644 packaging/kindnet/microshift-kindnet.service %{buildroot}%{_sysconfdir}/systemd/system/microshift.service
install -p -m644 packaging/crio.conf.d/13-microshift-kindnet.conf %{buildroot}%{_sysconfdir}/crio/crio.conf.d/13-microshift-kindnet.conf

%ifarch x86_64
cat assets/optional/kindnet/kustomization.x86_64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet/kustomization.yaml
%endif

%ifarch %{arm} aarch64
cat assets/optional/kindnet/kustomization.aarch64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet/kustomization.yaml
%endif

# kube-proxy
install -d -m755 %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy
# Copy all the manifests except the arch specific ones
install -p -m644 assets/optional/kube-proxy/0* %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy
install -p -m644 assets/optional/kube-proxy/kustomization.yaml %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy

%ifarch x86_64
cat assets/optional/kube-proxy/kustomization.x86_64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy/kustomization.yaml
%endif

%ifarch %{arm} aarch64
cat assets/optional/kube-proxy/kustomization.aarch64.yaml >> %{buildroot}/%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy/kustomization.yaml
%endif

# kindnet-release-info
mkdir -p -m755 %{buildroot}%{_datadir}/microshift/release
install -p -m644 assets/optional/kindnet/release-kindnet-{x86_64,aarch64}.json %{buildroot}%{_datadir}/microshift/release/
install -p -m644 assets/optional/kube-proxy/release-kube-proxy-{x86_64,aarch64}.json %{buildroot}%{_datadir}/microshift/release/

%files kindnet
%dir %{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet
%dir %{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy
%{_prefix}/lib/microshift/manifests.d/000-microshift-kindnet/*
%{_prefix}/lib/microshift/manifests.d/000-microshift-kube-proxy/*
%config(noreplace) %{_sysconfdir}/microshift/config.d/00-disableDefaultCNI.yaml
%{_sysconfdir}/systemd/system/microshift.service
%{_sysconfdir}/crio/crio.conf.d/13-microshift-kindnet.conf

%files kindnet-release-info
%{_datadir}/microshift/release/release-kindnet-{x86_64,aarch64}.json
%{_datadir}/microshift/release/release-kube-proxy-{x86_64,aarch64}.json
