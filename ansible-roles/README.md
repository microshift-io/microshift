# Ansible Roles for MicroShift/OKD Bootc Installation

This repository contains Ansible roles for provisioning and managing MicroShift or OKD Bootc installations.

## Roles


### `microshift-okd-download`

This role downloads MicroShift released assets (RPMs) from the microshift okd GitHub [repository](https://github.com/microshift-io/microshift/releases/tag).

#### Variables

*   `download_path`: (String) The local path where artifacts should be downloaded.
*


#### Usage Example
```yaml
- hosts: my_target_hosts
  roles:
    - role: microshift-okd-download
      download_path: "/var/tmp/okd_artifacts"
```


### `microshift-okd-bootc`

This role is responsible for building and running MicroShift okd inside a bootc podman container

#### Variables

*   `bootc_version`:  (String) Specifies the version of Bootc to install. Default: `latest`.
*   `microshift_okd`: (String)  Choose between `microshift` or `okd`. Default: `microshift`
*   `other_variable_1`: (String) [**FILL IN: Description of the variable and its purpose.**] Default: `some_value`.
*   `other_variable_2`: (Boolean) [**FILL IN: Description of the variable and its purpose.**] Default: `true`.

#### Usage Example

```yaml
- hosts: my_target_hosts
  roles:
    - role: microshift-okd-bootc
      bootc_version: "v1.2.3"
      microshift_okd: "okd"
      other_variable_1: "custom_setting"
```