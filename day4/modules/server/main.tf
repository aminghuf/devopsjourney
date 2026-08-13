terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-*-${var.server_image}-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "default" {
  count      = var.create_ssh_key ? 1 : 0
  key_name   = var.ssh_key_name
  public_key = var.ssh_key_public
}

data "aws_key_pair" "existing" {
  count    = var.create_ssh_key ? 0 : 1
  key_name = var.ssh_key_name
}

locals {
  ssh_key_name = var.create_ssh_key ? aws_key_pair.default[0].key_name : data.aws_key_pair.existing[0].key_name
}
resource "aws_iam_role" "ec2_role" {
  name = "${var.server_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.server_name}-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.server_type
  key_name               = local.ssh_key_name
  vpc_security_group_ids = [aws_security_group.web_and_ssh.id]
  subnet_id              = var.subnet_id
  tags = {
    Name = var.server_name
  }
  lifecycle {
    ignore_changes = [ami]
  }
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
}

resource "aws_security_group" "web_and_ssh" {
  name        = var.firewall_name
  description = "Allow SSH from admin IP and HTTP/HTTPS from anywhere"
  vpc_id      = var.vpc_id
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.firewall_name
  }
}

resource "aws_eip" "web" {
  domain = "vpc"

  tags = {
    Name = var.server_name
  }
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.web.id
}

resource "cloudflare_record" "server_dns" {
  zone_id = var.cloudflare_zone_id
  name    = var.dns_record_name
  content = aws_eip.web.public_ip # Dynamically grabs the AWS Elastic IP
  type    = "A"
  proxied = false
}