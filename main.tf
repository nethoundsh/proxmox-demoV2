data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

resource "proxmox_download_file" "ubuntu_jammy" {
  node_name    = var.pve_node_name
  content_type = "iso"
  datastore_id = "local"

  url       = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  file_name = "jammy-server-cloudimg-amd64.img"
  overwrite = false
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  node_name    = var.pve_node_name
  content_type = "snippets"
  datastore_id = "local"

  source_raw {
    file_name = "lab-ubuntu-cloud-config.yaml"
    data      = <<-EOF
      #cloud-config
      hostname: lab-ubuntu
      timezone: America/New_York
      ssh_pwauth: true

      users:
        - default
        - name: ubuntu
          lock_passwd: false
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(data.local_file.ssh_public_key.content)}

      chpasswd:
        list: |
          ubuntu:${var.ubuntu_password}
        expire: false

      package_update: true
      packages:
        - qemu-guest-agent
        - net-tools
        - curl

      runcmd:
        - systemctl enable qemu-guest-agent
        - systemctl start qemu-guest-agent
        - echo done > /tmp/cloud-config.done
    EOF
  }
}

resource "proxmox_network_linux_bridge" "vmbr1" {
  node_name = var.pve_node_name
  name      = "vmbr1"
  comment   = "Isolated lab bridge"
}

resource "proxmox_virtual_environment_vm" "lab_ubuntu" {
  name      = "lab-ubuntu"
  node_name = var.pve_node_name

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = 2
    type  = "qemu64"
  }

  memory {
    dedicated = 2048
  }

  efi_disk {
    datastore_id = var.vm_datastore
    type         = "4m"
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
    file_id      = proxmox_download_file.ubuntu_jammy.id
  }

  network_device {
    bridge = "vmbr0"
  }

  network_device {
    bridge = proxmox_network_linux_bridge.vmbr1.name
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    dns {
      servers = ["1.1.1.1"]
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  started = true
}

# --- Jump host vmbr1 interface config ---

locals {
  target_vms = {
    "target-01" = "10.10.10.11"
  }
}

resource "null_resource" "lab_ubuntu_vmbr1_ip" {
  triggers = {
    bridge_id = proxmox_network_linux_bridge.vmbr1.id
  }

  connection {
    type  = "ssh"
    user  = "ubuntu"
    host  = proxmox_virtual_environment_vm.lab_ubuntu.ipv4_addresses[1][0]
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "printf 'network:\\n  version: 2\\n  ethernets:\\n    enp6s19:\\n      addresses:\\n        - 10.10.10.1/24\\n' | sudo tee /etc/netplan/99-vmbr1.yaml",
      "sudo netplan apply"
    ]
  }
}

# --- Template VM (never booted, cloned from) ---

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name      = "ubuntu-jammy-template"
  node_name = var.pve_node_name
  template  = true
  started   = false

  bios    = "ovmf"
  machine = "q35"

  cpu {
    cores = 2
    type  = "qemu64"
  }

  memory {
    dedicated = 2048
  }

  efi_disk {
    datastore_id = var.vm_datastore
    type         = "4m"
  }

  disk {
    datastore_id = var.vm_datastore
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
    file_id      = proxmox_download_file.ubuntu_jammy.id
  }

  network_device {
    bridge = proxmox_network_linux_bridge.vmbr1.name
  }

  agent {
    enabled = true
  }
}

# --- Per-target cloud-init snippets ---

resource "proxmox_virtual_environment_file" "target_cloud_config" {
  for_each = local.target_vms

  node_name    = var.pve_node_name
  content_type = "snippets"
  datastore_id = "local"

  source_raw {
    file_name = "${each.key}-cloud-config.yaml"
    data      = <<-EOF
      #cloud-config
      hostname: ${each.key}
      timezone: America/New_York
      ssh_pwauth: true

      users:
        - default
        - name: ubuntu
          lock_passwd: false
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${trimspace(data.local_file.ssh_public_key.content)}

      chpasswd:
        list: |
          ubuntu:${var.ubuntu_password}
        expire: false

      runcmd:
        - echo done > /tmp/cloud-config.done
    EOF
  }
}

# --- Target VMs cloned from template ---

resource "proxmox_virtual_environment_vm" "target" {
  for_each  = local.target_vms
  name      = each.key
  node_name = var.pve_node_name

  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_template.vm_id
    full  = true
  }

  agent {
    enabled = false
  }

  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = "${each.value}/24"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.target_cloud_config[each.key].id
  }

  started = true
}

# --- Baseline snapshots ---

resource "null_resource" "target_baseline_snapshot" {
  for_each = local.target_vms

  triggers = {
    vm_id = proxmox_virtual_environment_vm.target[each.key].vm_id
  }

  connection {
    type         = "ssh"
    user         = "ubuntu"
    host         = each.value
    agent        = true
    bastion_host = proxmox_virtual_environment_vm.lab_ubuntu.ipv4_addresses[1][0]
    bastion_user = "ubuntu"
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ${var.pve_ssh_user}@${var.pve_ssh_host} 'sudo qm snapshot ${proxmox_virtual_environment_vm.target[each.key].vm_id} clean --description \"Terraform baseline\"'"
  }
}

# --- Generated reset script ---

resource "local_file" "reset_script" {
  filename        = "${path.module}/reset.sh"
  file_permission = "0755"
  content         = <<-SCRIPT
    #!/usr/bin/env bash
    set -euo pipefail
    PVE_HOST="${var.pve_ssh_host}"
    PVE_USER="${var.pve_ssh_user}"
    SNAPSHOT="clean"

    declare -A TARGETS=(
    %{ for name, _ in local.target_vms ~}
      ["${name}"]="${proxmox_virtual_environment_vm.target[name].vm_id}"
    %{ endfor ~}
    )

    reset_vm() {
      local name="$1"
      local vm_id="$${TARGETS[$${name}]}"
      echo "Rolling $${name} (VM $${vm_id}) back to $${SNAPSHOT}..."
      ssh "$${PVE_USER}@$${PVE_HOST}" "sudo qm rollback $${vm_id} $${SNAPSHOT} --start"
      echo "$${name} reset complete."
    }

    if [[ $# -eq 0 ]]; then
      for name in "$${!TARGETS[@]}"; do
        reset_vm "$${name}"
      done
    else
      for name in "$@"; do
        reset_vm "$${name}"
      done
    fi
  SCRIPT
}
