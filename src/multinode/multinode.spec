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

%description
The microshift package provides an OpenShift Kubernetes distribution optimized for small form factor and edge computing.

%prep
%setup -n microshift-%{commit}
#
# End of the header copied from microshift/packaging/rpm/microshift.spec
#

%package multinode
Summary: Multinode dependencies for MicroShift
BuildArch: noarch
Requires: microshift = %{version}

%description multinode
The microshift-multinode package provides the required configuration files for running multinode MicroShift.

%install
install -d -m755 %{buildroot}/%{_sysconfdir}/microshift/config.d

# multinode
install -d -m755 %{buildroot}%{_sysconfdir}/systemd/system/microshift.service.d
install -p -m644 packaging/multinode/microshift-multinode.conf %{buildroot}%{_sysconfdir}/systemd/system/microshift.service.d/multinode.conf

%files multinode
%{_sysconfdir}/systemd/system/microshift.service.d/multinode.conf
