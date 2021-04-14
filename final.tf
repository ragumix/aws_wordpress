provider "aws" {
  region                  = "eu-west-2"
  shared_credentials_file = "./aws/credentials"
}

module "myip" {
  source  = "4ops/myip/http"
  version = "1.0.0"
}

resource "aws_vpc" "myvpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "MyVPC"
  }
}

resource "aws_subnet" "eu-west-2a" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-2a"

  tags = {
    Name = "eu-west-2a"
  }
  depends_on = [aws_vpc.myvpc]
}

resource "aws_subnet" "eu-west-2b" {
  vpc_id            = aws_vpc.myvpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-2b"

  tags = {
    Name = "eu-west-2b"
  }
  depends_on = [aws_vpc.myvpc]
}

resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "MyIG"
  }
  depends_on = [aws_subnet.eu-west-2a, aws_subnet.eu-west-2b]
}

resource "aws_route" "route_to_ig" {
  route_table_id         = aws_vpc.myvpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mygw.id
  depends_on             = [aws_internet_gateway.mygw]
}

resource "aws_route_table_association" "eu-west-2a" {
  subnet_id      = aws_subnet.eu-west-2a.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
  depends_on     = [aws_subnet.eu-west-2a, aws_route.route_to_ig]
}

resource "aws_route_table_association" "eu-west-2b" {
  subnet_id      = aws_subnet.eu-west-2b.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
  depends_on     = [aws_subnet.eu-west-2b, aws_route.route_to_ig]
}

resource "aws_efs_file_system" "myefs" {
  encrypted = true
  tags = {
    Name = "MyEFS"
  }
  depends_on = [aws_route_table_association.eu-west-2a, aws_route_table_association.eu-west-2b]
}

resource "aws_efs_mount_target" "eu-west-2a" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.eu-west-2a.id
  depends_on     = [aws_efs_file_system.myefs]
}

resource "aws_efs_mount_target" "eu-west-2b" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.eu-west-2b.id
  depends_on     = [aws_efs_file_system.myefs]
}

resource "aws_security_group" "SG_for_EC2" {
  name        = "SG_for_EC2"
  description = "Allow 80, 443, 22 port inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "TLS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${module.myip.address}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "SG_for_RDS" {
  name        = "SG_for_RDS"
  description = "Allow MySQL inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "RDS from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "SG_for_EFS" {
  name        = "SG_for_EFS"
  description = "Allow NFS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description     = "NFS from EC2"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.SG_for_EC2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [aws_subnet.eu-west-2a.id, aws_subnet.eu-west-2b.id]
}

resource "aws_db_instance" "mysql" {
  identifier                      = "mysql2"
  engine                          = "mysql"
  engine_version                  = "8.0.20"
  instance_class                  = "db.t2.micro"
  db_subnet_group_name            = aws_db_subnet_group.default.name
  enabled_cloudwatch_logs_exports = ["general", "error"]
  name                            = "wordpress_db"
  username                        = var.rds_credentials.username
  password                        = var.rds_credentials.password
  allocated_storage               = 20
  max_allocated_storage           = 0
  backup_retention_period         = 7
  backup_window                   = "00:00-00:30"
  maintenance_window              = "Sun:21:00-Sun:21:30"
  storage_type                    = "gp2"
  vpc_security_group_ids          = [aws_security_group.SG_for_RDS.id]
  skip_final_snapshot             = true
  depends_on = [aws_vpc.myvpc]
}

resource "aws_launch_configuration" "my_conf" {
  name          = "My Launch Config with WP"
  image_id      = "ami-048d22f921ab08674"
  instance_type = "t2.micro"
  key_name = "Test_key"
  security_groups = [aws_security_group.SG_for_EC2.id]
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted = false
  }
  depends_on = [aws_vpc.myvpc]
}

resource "aws_autoscaling_group" "my_asg" {
  name                      = "my_asg"
  max_size                  = 4
  min_size                  = 0
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  launch_configuration      = aws_launch_configuration.my_conf.name
  vpc_zone_identifier       = [aws_subnet.eu-west-2a.id, aws_subnet.eu-west-2b.id]
  depends_on = [aws_vpc.myvpc]
}
