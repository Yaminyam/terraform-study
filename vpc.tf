provider "aws" {
    profile = "tf-profile"
}

//한국, 도쿄, 버지니아 리전
locals {
    regions = ["ap-northeast-2", "ap-northeast-1", "us-east-1"]
}

resource "aws_vpc" "vpc" {
    count = 3
    cidr_block = "10.0.${count.index}.0/16"
    tags = {
        Name = "vpc-${count.index}"
    }
    provider = aws.regions[count.index]
}

//Subnet
resource "aws_subnet" "subnet" {
    count = 6
    cidr_block = "10.0.${count.index / 2}.${count.index % 2 * 128}/20"
    vpc_id = aws_vpc.vpc[count.index / 2].id
    availability_zone = "${local.regions[count.index / 2]}${count.index % 2 + 1}"
    tags = {
        Name = "subnet-${count.index}"
    }
    provider = aws.regions[count.index / 2]
}

//WAF
resource "aws_wafv2_web_acl" "web_acl" {
    count = 3
    name = "web-acl-${count.index}"
    scope = "REGIONAL"
    default_action {
        allow {}
    }
    provider = aws.regions[count.index]
}

resource "aws_wafv2_web_acl_association" "web_acl_association" {
    count = 3
    resource_arn = aws_alb.alb[count.index].arn
    web_acl_arn = aws_wafv2_web_acl.web_acl[count.index].arn
    provider = aws.regions[count.index]
}


//Transit Gateway
resource "aws_ec2_transit_gateway" "transit_gateway" {
    provider = "aws.ap-notheast-2"
    description = "Transit Gateway"
    tags = {
        Name = "transit-gateway"
    }
}

resource "aws_ec2_transit_gateway_attachment" "attachment" {
    count = 3
    subnet_ids = [aws_vpc.vpc[count.index].public_subnets[0]]
    transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
    vpc_id = aws_vpc.vpc[count.index].id
}

//security_group
resource "aws_security_group" "security_group" {
  count = 3
  name = "security-group-${count.index}"
  description = "Security Group"
  vpc_id = aws_vpc.vpc[count.index].id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  provider = "aws.${local.regions[count.index]}"
}

//Instance
resource "aws_instance" "public_instance" {
    count = 3
    ami           = "ami-0c94855ba95c71c99"
    instance_type = "t2.micro"
    subnet_id     = aws_subnet.subnet[count.index * 2].id
    tags = {
        Name = "public-instance-${count.index}"
    }
    provider = aws.regions[count.index]
}

//ALB
resource "aws_lb" "lb" {
  name = "my-lb"
  subnets = [aws_subnet.subnet[0].id, aws_subnet.subnet[2].id, aws_subnet.subnet[4].id]
  security_groups = [aws_security_group.security_group[0].id]
  provider = "aws.${local.regions[0]}"
}

resource "aws_lb_target_group" "target_group" {
  count = 3
  name = "my-target-group-${count.index}"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc[count.index].id
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group[0].arn
  }
  provider = "aws.${local.regions[0]}"
}

resource "aws_lb_target_group_attachment" "target_group_attachment" {
  count = 3
  target_group_arn = aws_lb_target_group.target_group[count.index].arn
  target_id = aws_instance.instance[count.index].id
  port = 80
  provider = "aws.${local.regions[count.index]}"
}