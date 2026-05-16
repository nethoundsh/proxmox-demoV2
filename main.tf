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
