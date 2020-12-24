terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.3"
    }
  }
}

variable "hostname" { default = "k3s-server" }
variable "memoryMB" { default = 1024 * 4 }
variable "cpu" { default = 1 }
variable "serverCount" { default = 3 }

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "os_image" {
  name   = "os_image"
  source = "http://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-20201217.0.x86_64.qcow2"
}

resource "libvirt_volume" "volume" {
  count          = var.serverCount
  name           = "volume-${count.index}"
  base_volume_id = libvirt_volume.os_image.id
  pool           = "default"
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count          = var.serverCount
  name           = "${var.hostname}-commoninit-${count.index}.iso"
  pool           = "default"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config.rendered
}


data "template_file" "user_data" {
  count    = var.serverCount
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${var.hostname}-${count.index}"
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config_dhcp.cfg")
}


# Create the machine
resource "libvirt_domain" "domain" {
  count  = var.serverCount
  name   = "k3s-${count.index}"
  memory = var.memoryMB
  vcpu   = var.cpu

  disk {
    volume_id = element(libvirt_volume.volume.*.id, count.index)
  }
  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id
}

output "ips" {
  value = libvirt_domain.domain.*.network_interface.0.addresses
}
