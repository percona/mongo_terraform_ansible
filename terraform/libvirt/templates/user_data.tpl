#cloud-config
# vim: syntax=yaml
hostname: ${host_name}
manage_etc_hosts: true
users:
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${auth_key}
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    admin:admin
  expire: false
growpart:
  mode: auto
  devices: ['/']
package_update: true
package_upgrade: true
