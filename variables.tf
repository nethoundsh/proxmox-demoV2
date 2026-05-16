variable "pve_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint, e.g. https://192.168.1.11:8006/"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in the format pippi@pam!tokenid=uuid"
}

variable "pve_node_name" {
  type        = string
  default     = "mikanko"
  description = "Proxmox node name"
}

variable "vm_datastore" {
  type        = string
  default     = "local-zfs"
  description = "Datastore for VM disks and cloud-init drive"
}

variable "ubuntu_password" {
  type        = string
  sensitive   = true
  description = "Plaintext password for the ubuntu user"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  description = "Path to the SSH public key to inject into the VM"
}
