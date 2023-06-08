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

resource "aws_security_group" "db_security_group" {
  count = 3
  name_prefix = "my-db-security-group-${count.index}"
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
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
  count = 3
  name = "autoscaling-group"
  launch_configuration = aws_launch_configuration.launch_configuration[0].name
  min_size = 1
  max_size = 3
  desired_capacity = 2
  vpc_zone_identifier = [aws_subnet.subnet[count.index * 2].id, aws_subnet.subnet[count.index * 2 + 1].id]
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_lb" "lb" {
  count = 3
  name = "my-lb"
  internal = false
  load_balancer_type = "application"
  subnets = [aws_subnet.subnet[count.index * 2].id, aws_subnet.subnet[count.index * 2 + 1].id]
  security_groups = [aws_security_group.security_group[count.index].id]
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_lb_target_group" "target_group" {
  count = 3
  name = "my-target-group"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc[count.index].id
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_lb_listener" "listener" {
  count = 3
  load_balancer_arn = aws_lb.lb.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  count = 3
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
  alb_target_group_arn = aws_lb_target_group.target_group.arn
  provider = "aws.${local.regions[count.index]}"
}

resource "aws_db_subnet_group" "subnet_group" {
    count = 3
    name = "db-subnet-group"
    subnet_ids = [aws_subnet.subnet[count.index * 2].id, aws_subnet.subnet[count.index * 2 + 1].id]
}

resource "aws_db_instance" "db_instance" {
    count = 3
    identifier = "mydb-${count.index}"
    engine = "mysql"
    engine_version = "8.0"
    instance_class = "db.t2.micro"
    allocated_storage = 20
    vpc_security_group_ids = [aws_security_group.db_security_group[count.index].id]
    db_subnet_group_name = aws_db_subnet_group.subnet_group[count.index].name
    provider = "aws.${local.regions[count.index]}"
}