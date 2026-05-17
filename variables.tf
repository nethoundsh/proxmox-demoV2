variable "pve_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint, e.g. https://<your-pve-ip>:8006/"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token in the format user@pam!tokenid=uuid"
}

variable "pve_node_name" {
  type        = string
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

variable "pve_ssh_host" {
  type        = string
  description = "IP or hostname of the PVE host for SSH access (used for snippets and snapshots)"
}

variable "pve_ssh_user" {
  type        = string
  description = "SSH username on the PVE host"
}
