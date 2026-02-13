%global debug_package %{nil}

Name: containernetworking-plugins
# Setting epoch to workaround containers-common's Obsolete of 'containernetworking-plugins < 2'
Epoch: 1
Version: %{ver}
Release: 1
Summary: Binaries required to provision kubernetes container networking

Packager: MicroShift team
License: Apache-2.0
URL: https://microshift.io
Source0: %{name}-%{version}.tar.gz

%description
%{summary}.

%prep
%setup -q -c

%build
# Nothing to build

%install
# Detect host arch
KUBE_ARCH="$(uname -m)"

# Install files
mkdir -p %{buildroot}/usr/libexec/cni/
mkdir -p %{buildroot}%{_sysconfdir}/cni/net.d/

cp -a ${KUBE_ARCH}/* %{buildroot}/usr/libexec/cni/

%files
/usr/libexec/cni/
%dir %{_sysconfdir}/cni
%dir %{_sysconfdir}/cni/net.d
%license LICENSE
%doc README.md

%changelog
* Fri Feb 13 2026 Patryk Matuszak <pmatusza@redhat.com> 0.0.0
- Init specfile based on https://download.opensuse.org/repositories/isv:/kubernetes:/core:/prerelease:/v1.36/rpm/src/kubernetes-cni-1.8.0-150500.1.1.src.rpm
