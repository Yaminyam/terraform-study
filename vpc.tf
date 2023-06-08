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

resource "aws_launch_configuration" "launch_configuration" {
  count = 3
  name_prefix = "launch-configuration-${count.index}"
  image_id = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.security_group[count.index].id]
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_autoscaling_group" "autoscaling_group" {
  name = "autoscaling-group"
  launch_configuration = aws_launch_configuration.launch_configuration[0].name
  min_size = 1
  max_size = 3
  desired_capacity = 2
  vpc_zone_identifier = [aws_subnet.subnet[0].id, aws_subnet.subnet[2].id, aws_subnet.subnet[4].id]
  target_group_arns = [aws_lb_target_group.target_group[0].arn]
  provider = "aws.${local.regions[0]}"
}

resource "aws_lb" "lb" {
  name = "my-lb"
  internal = false
  load_balancer_type = "application"
  subnets = [aws_subnet.subnet[1].id, aws_subnet.subnet[3].id, aws_subnet.subnet[5].id]
  security_groups = [aws_security_group.security_group[0].id]
  provider = "aws.${local.regions[0]}"
}

resource "aws_lb_target_group" "target_group" {
  name = "my-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc[0].id
  provider = "aws.${local.regions[0]}"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
  provider = "aws.${local.regions[0]}"
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  alb_target_group_arn = aws_lb_target_group.target_group.arn
  provider = "aws.${local.regions[0]}"
}