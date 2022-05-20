provider "aws" {
    region = "eu-south-1"
    access_key = "***********"
    secret_key = "*************"
}


resource "aws_vpc" "testnet" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "Testnet"}
}

resource "aws_subnet" "testsubnet" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.testnet.id
  tags = { Name = "Testsubnet"}
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.testnet.id
  tags = {
    Name = "Gateway"
  }
}

resource "aws_route_table" "route" {
  vpc_id = aws_vpc.testnet.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "routeassoc" {
  subnet_id      = aws_subnet.testsubnet.id
  route_table_id = aws_route_table.route.id
}


resource "aws_security_group" "allow_80_22_443" {
  name        = "allow_80_22_443"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.testnet.id

  ingress {
    description      = "web from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "TLS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "ssh from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

ingress {
    description      = "ICMP"
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["10.0.1.0/24"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

ingress {
    description      = "kubernetesapi"
    from_port        = 6443
    to_port          = 6443 
    protocol         = "tcp"
    cidr_blocks      = ["10.0.1.0/24"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }
ingress {
    description      = "jenkins"
    from_port        = 30003
    to_port          = 30003
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    #ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_80_22_443_6443"
  }
}

resource "aws_network_interface" "njeinterface" {
  subnet_id       = aws_subnet.testsubnet.id
  private_ips     = ["10.0.1.51"]
  security_groups = [aws_security_group.allow_80_22_443.id]
}

resource "aws_network_interface" "dyinterface" {
  subnet_id       = aws_subnet.testsubnet.id
  private_ips     = ["10.0.1.52"]
  security_groups = [aws_security_group.allow_80_22_443.id]
}

resource "aws_network_interface" "treinterface" {
  subnet_id       = aws_subnet.testsubnet.id
  private_ips     = ["10.0.1.53"]
  security_groups = [aws_security_group.allow_80_22_443.id]
}




resource "aws_eip" "nje" {
  vpc                       = true
  network_interface         = aws_network_interface.njeinterface.id
  associate_with_private_ip = "10.0.1.51"
}

resource "aws_eip" "dy" {
  vpc                       = true
  network_interface         = aws_network_interface.dyinterface.id
  associate_with_private_ip = "10.0.1.52"
}

resource "aws_eip" "tre" {
  vpc                       = true
  network_interface         = aws_network_interface.treinterface.id
  associate_with_private_ip = "10.0.1.53"
}




resource "aws_instance" "ubuntu1" {
  depends_on = [aws_instance.ubuntu2]
  ami           = "ami-027f7881d2f6725e1"
   instance_type = "t3.small"
  tags = {name="testubu1"}
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.njeinterface.id
      }
  key_name = "test"
  provisioner "remote-exec" {
    inline = [
      "sudo apt-add-repository -y ppa:ansible/ansible",
      "sudo apt-get update -y",
      "sudo apt-get install python2.7 -y",
      "sudo apt-get install ansible -y",
      "sudo mkdir /home/ubuntu/ansible",
      "sudo chown -R ubuntu /home/ubuntu/ansible",
      "sudo hostnamectl set-hostname master"
    ]
    connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("test.pem")
    host     = self.public_ip
  }
    }

  provisioner "file" {
    source      = "kubetest/"
    destination = "/home/ubuntu/ansible"
    connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("test.pem")
    host     = self.public_ip
  }
  }


    provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/ubuntu/ansible/test.pem",
      "ansible-playbook -i /home/ubuntu/ansible/hosts  /home/ubuntu/ansible/nonroot.yml --ssh-common-args='-o StrictHostKeyChecking=no'",
      "ansible-playbook -i /home/ubuntu/ansible/hosts  /home/ubuntu/ansible/kubedep.yml --ssh-common-args='-o StrictHostKeyChecking=no'",
      "ansible-playbook -i /home/ubuntu/ansible/hosts  /home/ubuntu/ansible/init.yml --ssh-common-args='-o StrictHostKeyChecking=no'",
      "ansible-playbook -i /home/ubuntu/ansible/hosts  /home/ubuntu/ansible/work.yml --ssh-common-args='-o StrictHostKeyChecking=no'",
      "chmod 700 /home/ubuntu/ansible/jenkins/get_helm.sh",
      "/home/ubuntu/ansible/jenkins/get_helm.sh",
      "kubectl create namespace jenkins",
      "sudo mkdir /data/",
      "sudo mkdir /data/jenkins-volume/",
      "sudo chown -R ubuntu:ubuntu /data/jenkins-volume/",
      "kubectl apply -f /home/ubuntu/ansible/jenkins/pv.yaml",
      "kubectl apply -f /home/ubuntu/ansible/jenkins/pvc.yaml",
      "sudo chmod go-r ~/.kube/config",
      "helm repo add jenkins https://charts.jenkins.io",
      "kubectl taint nodes master node-role.kubernetes.io/master-",
      "kubectl cordon worker1",
      "kubectl cordon worker2",
      "helm install jenkins -n jenkins --values /home/ubuntu/ansible/jenkins/v.yaml jenkins/jenkins"

      #"helm install jenkins --namespace jenkins --values /home/ubuntu/ansible/jenkins/v.yml "
      
    ]
    connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("test.pem")
    host     = self.public_ip
  }
  }

}

resource "aws_instance" "ubuntu2" {
  depends_on = [aws_instance.ubuntu3]
  ami           = "ami-027f7881d2f6725e1"
   instance_type = "t3.micro"
  tags = {name="testubu2"}
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.dyinterface.id
      }
  key_name = "test"

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname worker1",
      "sudo apt-get update -y",
      "sudo apt-get install python2.7 -y"
      
      ]
    connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("test.pem")
    host     = self.public_ip
    }
    }
  }


resource "aws_instance" "ubuntu3" {
  ami           = "ami-027f7881d2f6725e1"
   instance_type = "t3.micro"
  tags = {name="testubu3"}
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.treinterface.id
      }
  key_name = "test"

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install python2.7 -y",
      "sudo hostnamectl set-hostname worker2"
      ]
    connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("test.pem")
    host     = self.public_ip
    }
    }       
}