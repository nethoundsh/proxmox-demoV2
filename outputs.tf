output "vm_ipv4_address" {
  description = "IPv4 address assigned to lab-ubuntu via DHCP"
  value       = try(proxmox_virtual_environment_vm.lab_ubuntu.ipv4_addresses[1][0], "pending")
}

output "target_vm_ips" {
  description = "Static IPs of target VMs on vmbr1"
  value       = local.target_vms
}
