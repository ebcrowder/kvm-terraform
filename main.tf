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
  # pool   = "default"
}

resource "libvirt_volume" "volume" {
  count          = var.serverCount
  name           = "volume-${count.index}"
  base_volume_id = libvirt_volume.os_image.id
  # pool           = "default"
  format = "qcow2"
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.serverCount
  name  = "${var.hostname}-commoninit-${count.index}.iso"
  # pool           = "default"
  user_data = data.template_file.user_data[count.index].rendered
  # network_config = data.template_file.network_config.rendered
}


data "template_file" "user_data" {
  count    = var.serverCount
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${var.hostname}-${count.index}"
  }
}

# data "template_file" "network_config" {
#   template = file("${path.module}/network_config_dhcp.cfg")
# }

resource "libvirt_network" "network" {
  # the name used by libvirt
  name = "kvmnet"

  # mode can be: "nat" (default), "none", "route", "bridge"
  mode      = "bridge"
  autostart = true
  dhcp {
    enabled = true
  }

  #  the domain used by the DNS server in this network
  # domain = "kvmnet.local"

  #  list of subnets the addresses allowed for domains connected
  # also derived to define the host addresses
  # also derived to define the addresses served by the DHCP server
  addresses = ["192.168.122.0/24"]

  # (optional) the bridge device defines the name of a bridge device
  # which will be used to construct the virtual network.
  # (only necessary in "bridge" mode)
  bridge = "bridge0"

  # (optional) the MTU for the network. If not supplied, the underlying device's
  # default is used (usually 1500)
  # mtu = 9000
}

# Create the machine
resource "libvirt_domain" "domain" {
  count      = var.serverCount
  name       = "k3s-${count.index}"
  memory     = var.memoryMB
  vcpu       = var.cpu
  qemu_agent = true
  autostart  = true

  disk {
    volume_id = element(libvirt_volume.volume.*.id, count.index)
  }

  network_interface {
    network_name   = "kvmnet"
    bridge         = "bridge0"
    wait_for_lease = true
  }

  depends_on = [
    libvirt_network.network,
  ]

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id
}

output "ips" {
  value = libvirt_domain.domain.*.network_interface.0.addresses
}
