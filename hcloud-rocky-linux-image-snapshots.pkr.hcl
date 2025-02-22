/*
 * Creates a MicroOS snapshot for Kube-Hetzner
 */
packer {
  required_plugins {
    hcloud = {
      version = ">= 1.0.5"
      source  = "github.com/hashicorp/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  default   = env("HCLOUD_TOKEN")
  sensitive = true
}

# We download the OpenSUSE MicroOS x86 image from an automatically selected mirror.
variable "rocky_9_x86_mirror_link" {
  type    = string
  default = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

# We download the OpenSUSE MicroOS ARM image from an automatically selected mirror.
variable "rocky_9_arm_mirror_link" {
  type    = string
  default = "https://dl.rockylinux.org/pub/rocky/9/images/aarch64/Rocky-9-GenericCloud-Base.latest.aarch64.qcow2"
}

# If you need to add other packages to the OS, do it here in the default value, like ["vim", "curl", "wget"]
# When looking for packages, you need to search for OpenSUSE Tumbleweed packages, as MicroOS is based on Tumbleweed.
variable "packages_to_install" {
  type    = list(string)
  default = []
}

locals {
  #open-iscsi nfs-client I replace them
  needed_packages = join(" ", concat(["policycoreutils-restorecond policycoreutils policycoreutils-python-utils setools-console audit bind-utils wireguard-tools fuse xfsprogs cryptsetup lvm2 git cifs-utils bash-completion mtr tcpdump iscsi-initiator-utils nfs-utils python3-dnf-plugin-versionlock.noarch"], var.packages_to_install))

  # Add local variables for inline shell commands
  download_image = "wget --timeout=5 --waitretry=5 --tries=5 --retry-connrefused --inet4-only "

  write_image = <<-EOT
    set -ex
    echo 'Rocky image loaded, writing to disk... '
    qemu-img convert -p -f qcow2 -O host_device $(ls -a | grep -ie '^rocky.*qcow2$') /dev/sda
    echo 'done. Rebooting...'
    sleep 1 && udevadm settle && reboot
  EOT

  install_packages = <<-EOT
    set -ex
    echo "First reboot successful, installing needed packages..."    
    dnf install -y epel-release
    dnf update -y
    dnf install -y ${local.needed_packages}    
    setenforce 0
    rpm --import https://rpm.rancher.io/public.key
    dnf install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.stable.1/k3s-selinux-1.6-1.el9.noarch.rpm
    dnf versionlock add k3s-selinux
    restorecon -Rv /etc/selinux/targeted/policy
    restorecon -Rv /var/lib
    setenforce 1    
    sleep 1 && udevadm settle && reboot
  EOT

  clean_up = <<-EOT
    set -ex
    echo "Second reboot successful, cleaning-up..."
    rm -rf /etc/ssh/ssh_host_*
    echo "Make sure to use NetworkManager"
    touch /etc/NetworkManager/NetworkManager.conf
    sleep 1 && udevadm settle
  EOT
}

# Source for the MicroOS x86 snapshot
source "hcloud" "rockylinux-x86" {
  image       = "rocky-9"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cx22" # disk size of >= 40GiB is needed to install the MicroOS image
  snapshot_labels = {
    rocky-snapshot   = "yes"
    creator          = "kube-hetzner"
  }
  snapshot_name = "RockyLinux 9 x86 by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Source for the MicroOS ARM snapshot
source "hcloud" "rockylinux-arm" {
  image       = "rocky-9"
  rescue      = "linux64"
  location    = "nbg1"
  server_type = "cax11" # disk size of >= 40GiB is needed to install the MicroOS image
  snapshot_labels = {
    rocky-snapshot   = "yes"
    creator          = "kube-hetzner"
  }
  snapshot_name = "RockyLinux 9 ARM by Kube-Hetzner"
  ssh_username  = "root"
  token         = var.hcloud_token
}

# Build the MicroOS x86 snapshot
build {
  sources = ["source.hcloud.rockylinux-x86"]

  # Download the MicroOS x86 image
  provisioner "shell" {
    inline = ["${local.download_image}${var.rocky_9_x86_mirror_link}"]
  }

  # Write the MicroOS x86 image to disk
  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS x86 and do house-keeping
  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS x86 and do house-keeping
  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}

# Build the MicroOS ARM snapshot
build {
  sources = ["source.hcloud.rockylinux-arm"]

  # # Download the MicroOS ARM image
  provisioner "shell" {
    inline = ["${local.download_image}${var.rocky_9_arm_mirror_link}"]
  }

  # Write the MicroOS ARM image to disk
  provisioner "shell" {
    inline            = [local.write_image]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS ARM and do house-keeping
  provisioner "shell" {
    pause_before      = "5s"
    inline            = [local.install_packages]
    expect_disconnect = true
  }

  # Ensure connection to MicroOS ARM and do house-keeping
  provisioner "shell" {
    pause_before = "5s"
    inline       = [local.clean_up]
  }
}