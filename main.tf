terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

// ------------ Data ------------ //

data "aws_availability_zones" "available" {
  state = "available"
}

output "alb_sg_id" {
    value = aws_security_group.alb_sg.id
}

output "web_server_sg_id" {
    value = aws_security_group.web_server_sg.id
}

output "alb_arn" {
    value = aws_lb.my_alb.arn
}

// ------------ Variables ------------ //
variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "region" {}

variable "vpc_cidr" {}

variable "public_subnet_names" {
  type = list(string)
  default = [
    "Public Subnet 1",
    "Public Subnet 2"
  ]
}

variable "web_server_subnet_names" {
  type = list(string)
  default = [
    "Web Server Subnet 1",
    "Web Server Subnet 2"
  ]
}

variable "database_subnet_names" {
  type = list(string)
  default = [
    "Database Subnet 1",
    "Database Subnet 2"
  ]
}

# variable "public_subnet_1_cidr" {}


// ------------ Provider ------------ //

provider "aws" {
  profile    = "default"
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  skip_credentials_validation = true
}

// ------------ VPC ------------ //

resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = "false"

  tags = {
    Name = "Task 4-1 VPC"
  }
}


//////////////////////////////////////////////////
// ------------ Internet Gateway ------------ //
//////////////////////////////////////////////

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Task 4-1 Internet Gateway"
  }
}


//////////////////////////////////////////////
// ------------ Route Tables ------------ //
//////////////////////////////////////////

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "Private_route_table"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "Public_route_table"
  }
}



////////////////////////////////////////
// ------------ Subnets ------------ //
//////////////////////////////////////


resource "aws_subnet"  "public_subnets" {
  count                   = 2

  cidr_block              = "192.168.${count.index}.0/24"
  vpc_id                  = aws_vpc.my_vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = tomap({ "Name" = "${var.public_subnet_names[count.index]}" })
}

resource "aws_subnet"  "web_server_subnets" {
  count                   = 2

  cidr_block              = "192.168.${2+count.index}.0/24"
  vpc_id                  = aws_vpc.my_vpc.id
  map_public_ip_on_launch = "false"
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = tomap({ "Name" = "${var.web_server_subnet_names[count.index]}" })
}

resource "aws_subnet"  "database_subnets" {
  count                   = 2

  cidr_block              = "192.168.${4+count.index}.0/24"
  vpc_id                  = aws_vpc.my_vpc.id
  map_public_ip_on_launch = "false"
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = tomap({ "Name" = "${var.database_subnet_names[count.index]}" })
}

////////////////////////////////////////////////////////
// ------------ Route Table Association ------------ //
//////////////////////////////////////////////////////


resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = "${aws_subnet.public_subnets.*.id[count.index]}"
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "web_server_route_table_association" {
  count = 2

  subnet_id      = "${aws_subnet.web_server_subnets.*.id[count.index]}"
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "database_route_table_association" {
  count = 2

  subnet_id      = "${aws_subnet.database_subnets.*.id[count.index]}"
  route_table_id = aws_route_table.private_route_table.id
}

////////////////////////////////////////////
// ------------ NAT Gateway ------------ //
//////////////////////////////////////////

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gw_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "Task 4-1 NAT Gateway"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.my_igw]
}

///////////////////////////////////////////
// ------------ Elastic IP ------------ //
/////////////////////////////////////////


resource "aws_eip" "nat_gw_eip" {
  vpc      = true

  depends_on = [aws_internet_gateway.my_igw]
}


////////////////////////////////////////////////
// ------------ Security Groups ------------ //
//////////////////////////////////////////////

resource "aws_security_group" "alb_sg" {
  name        = "Task 4-1 ALB-SG"
  description = "Application load balancer security group"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description      = "Allows https requests"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "web_server_sg" {
  name        = "Web-Server-SG"
  description = "Web Server security group"
  vpc_id      = aws_vpc.my_vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_security_group_rule" "web_server_sg_rule" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_server_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group" "database_sg" {
  name        = "Database-SG"
  description = "Database security group"
  vpc_id      = aws_vpc.my_vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group_rule" "Database_sg_rule" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database_sg.id
  source_security_group_id = aws_security_group.web_server_sg.id
}


//////////////////////////////////////////////////////
// ------------ Elastic Load Balancer ------------ //
////////////////////////////////////////////////////

resource "aws_lb" "my_alb" {
  name               = "Task-4-1-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public_subnets : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name     = "Task-4-1-Target-Group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}
