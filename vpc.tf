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