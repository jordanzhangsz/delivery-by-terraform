#全局变量
variable "root_password" {
  default = "Abcd1234"
}

#创建VPC
resource "alicloud_vpc" "vpc" {
  name       = "VPC_WECUBE"
  cidr_block = "10.1.0.0/21"
}

#创建交换机（子网）- Wecube Platform组件运行的实例
resource "alicloud_vswitch" "switch_app" {
  name              = "SWITCH_WECUBE_APP"
  vpc_id            = "${alicloud_vpc.vpc.id}"
  cidr_block        = "10.1.1.0/24"
  availability_zone = "cn-hangzhou-b"
}

#创建交换机（子网）- Wecube Platform数据持久化的实例
resource "alicloud_vswitch" "switch_db" {
  name              = "SWITCH_WECUBE_DB1"
  vpc_id            = "${alicloud_vpc.vpc.id}"
  cidr_block        = "10.1.2.0/24"
  availability_zone = "cn-hangzhou-b"
}

#创建安全组
resource "alicloud_security_group" "sc_group" {
  name        = "SG_WECUBE"
  description = "Wecube Security Group"
  vpc_id      = "${alicloud_vpc.vpc.id}"
}

#创建安全规则
resource "alicloud_security_group_rule" "allow_all_tcp" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "1/65535"
  priority          = 1
  security_group_id = "${alicloud_security_group.sc_group.id}"
  cidr_ip           = "0.0.0.0/0"
}

#创建wecube插件上传后使用到的对象存储OSS
resource "alicloud_oss_bucket" "bucket-wecube-plugins" {
  bucket = "wecube-plugins"
}

#创建wecube资源服务器 - 对象存储OSS
resource "alicloud_oss_bucket" "bucket-wecube-artifacts" {
  bucket = "wecube-artifacts"
}

#创建WeCube Platform主机
resource "alicloud_instance" "instance_wecube_platform" {
  availability_zone = "cn-hangzhou-b"  
  security_groups   = "${alicloud_security_group.sc_group.*.id}"
  instance_type              = "ecs.n4.large"
  image_id          = "centos_8_0_x64_20G_alibase_20191225.vhd"
  system_disk_category       = "cloud_efficiency"
  instance_name              = "instance_wecube_platform"
  vswitch_id                 = "${alicloud_vswitch.switch_app.id}"
#  internet_max_bandwidth_out = 10
  password ="${var.root_password}"

#初始化配置
#  connection {
#    type     = "ssh"
#    user     = "root"
#    password = "${var.root_password}"
#    host     = "${alicloud_instance.instance_wecube_platform.public_ip}"
#  }
#
#  provisioner "file" {
#    source      = "application"
#    destination = "/root/application"
#  }
#
#  provisioner "remote-exec" {
#    inline = [
#      "chmod +x /root/application/wecube/install-wecube.sh",
#      "dos2unix /root/application/wecube/install-wecube.sh",
#	  "/root/application/wecube/install-wecube.sh"
#    ]
#  }
}

#创建服务器负载均衡SLB
resource "alicloud_slb" "slb_wecube" {
  name          = "slb_wecube"
  specification = "slb.s2.small"
  address_type  = "internet"
  internet_charge_type = "PayByBandwidth"
  bandwidth = 10
  tags = {
    tag_a = 1
    tag_b = 2
  }
}

#创建SLB负载访问控制列表
resource "alicloud_slb_acl" "slb_acl_wecube" {
  name       = "slb_acl_wecube"
  ip_version = "ipv4"
  entry_list {
#    entry   = "${alicloud_instance.instance_wecube_platform.private_ip}"
    entry = "0.0.0.0/24"
    comment = "Wecube app access list"
  }
}

#关联SLB负载均衡服务器和主机实例
resource "alicloud_slb_attachment" "slb_attachment_wecube" {
  load_balancer_id = "${alicloud_slb.slb_wecube.id}"
  instance_ids     = ["${alicloud_instance.instance_wecube_platform.id}"]
  weight           = 100
}

#创建负载均衡Web访问监听器
resource "alicloud_slb_listener" "slb_listener_web" {
  load_balancer_id          = "${alicloud_slb.slb_wecube.id}"
  backend_port              = 9080
  frontend_port             = 80
  protocol                  = "http"
  bandwidth                 = 5
  x_forwarded_for {
    retrive_slb_ip = true
    retrive_slb_id = true
	retrive_slb_proto = true 
  }
  acl_status      = "off"
  acl_type        = "white"
  acl_id          = "${alicloud_slb_acl.slb_acl_wecube.id}"
  request_timeout = 100
  idle_timeout    = 30
}

#创建负载均衡SSH监听器
resource "alicloud_slb_listener" "slb_listener_ssh" {
  load_balancer_id          = "${alicloud_slb.slb_wecube.id}"
  backend_port              = 22
  frontend_port             = 22
  protocol                  = "tcp"
  bandwidth                 = 5
  x_forwarded_for {
    retrive_slb_ip = true
    retrive_slb_id = true
	retrive_slb_proto = true 
  }
  acl_status      = "off"
  acl_type        = "white"
  acl_id          = "${alicloud_slb_acl.slb_acl_wecube.id}"
  request_timeout = 100
  idle_timeout    = 30
}

#配置单台主机（待研究）：
#provisioner "file" {
#  source      = "./scripts/install-wecube.sh"
#  destination = "/root/scripts/install-wecube.sh"
#
#  connection {
#    type     = "ssh"
#    user     = "root"
#    password = "Abcd1234"
#    host     = "${alicloud_instance.instance_wecube_platform.ip}"
#  }
#}

#配置多台主机（待研究）：
#resource "null_resource" "cluster" {
#  # Changes to any instance of the cluster requires re-provisioning
#  triggers = {
#    cluster_instance_ids = "${join(",", alicloud_instance.instance_wecube_platform.*.id)}"
#  }
#
#  # Bootstrap script can run on any instance of the cluster
#  # So we just choose the first in this case
#  connection {
#    host = "${element(alicloud_instance.instance_wecube_platform.*.public_ip, 0)}"
#  }
#
#  provisioner "remote-exec" {
#    # Bootstrap script called with private_ip of each node in the cluster
#    inline = [
#      "chmod +x /root/scripts/install-wecube.sh",
#      "/root/scripts/install-wecube.sh",
#    ]
#  }
#}
