FROM quay.io/centos/centos:stream9

ENV LANG=en_US.UTF-8 

# Enable CRB to get python3-wheel, then install deps
RUN dnf -y update && \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y install \
      python3 \
      python3-pip \
      python3-psutil \
      python3-setuptools \
      python3-wheel \
      git \
      sshpass \
      openssh-clients \
      rsync \
      tar \
      gzip \
      unzip \
      which \
      jq \
      sudo \
      findutils \
      procps-ng \
      hostname \
      ca-certificates && \
    dnf clean all && rm -rf /var/cache/dnf/* 

# Ansible + ansible-runner
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir ansible-core ansible-runner && \
    pip3 install --no-cache-dir "github3.py>=4.0.0"

# Runner FS layout
RUN mkdir -p /runner/project /runner/inventory /runner/env /runner/artifacts && \
    echo "[all]" > /runner/inventory/hosts 

# Non-root user 
RUN useradd -m -s /bin/bash runner && \
	    chown -R runner:runner /runner

USER runner
RUN ansible-galaxy collection install community.general containers.podman

WORKDIR /runner/project
USER runner
CMD ["bash", "-lc", "echo 'Ansible:' && ansible --version && echo 'Runner:' && ansible-runner --version"]  
