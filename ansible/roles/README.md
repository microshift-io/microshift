# Ansible Roles for MicroShift/OKD Bootc Installation

This repository contains Ansible roles for provisioning and managing MicroShift or OKD Bootc installations.

## Roles
### `microshift-okd-download`
This role downloads MicroShift released assets (RPMs) from `microshift-io` GitHub [repository](https://github.com/microshift-io/microshift/releases).
#### Variables
* `download_path`: (String) The local path where artifacts should be downloaded.
### `microshift-okd-bootc`
This role is responsible for building and running MicroShift okd inside a bootc podman container , based on the downloaded artifacts from `microshift-okd-download` role.


## Usage Example downloading and building container with the downloaded RPMs
  - create example inventory file (inventory.ini)

    ```
    microshift-vm ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_rsa
    ```

  - create a playbook (build-microshift.yaml)
    ```yaml
    - hosts: microshift-vm
      roles:
        - role: microshift-okd-download
          download_path: "/var/tmp/microshift_rpms"
        - role: microshift-okd-bootc
          microshift_download_dir: "/var/tmp/microshift_rpms"

    ```
  - run the playbook
    ```bash
    ansible-playbook build-microshift.yaml -i inventory.ini
    ```