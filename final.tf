provider "aws" {
  region                  = "eu-west-2"
  shared_credentials_file = "./aws/credentials"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"

  tags = {
    Name = "MyVPC"
  }
}

resource "aws_subnet" "eu-west-2a" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "eu-west-2a"
  }
  depends_on                = [aws_vpc.myvpc]
}

resource "aws_subnet" "eu-west-2b" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "eu-west-2b"
  }
  depends_on                = [aws_vpc.myvpc]
}

resource "aws_internet_gateway" "mygw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "MyIG"
  }
  depends_on                = [aws_vpc.myvpc]
}

resource "aws_route" "route_to_ig" {
  route_table_id            = aws_vpc.myvpc.main_route_table_id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.mygw.id
  depends_on                = [aws_internet_gateway.mygw, aws_vpc.myvpc]
}

resource "aws_route_table_association" "eu-west-2a" {
  subnet_id      = aws_subnet.eu-west-2a.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
  depends_on                = [aws_subnet.eu-west-2a]
}

resource "aws_route_table_association" "eu-west-2b" {
  subnet_id      = aws_subnet.eu-west-2b.id
  route_table_id = aws_vpc.myvpc.main_route_table_id
  depends_on                = [aws_subnet.eu-west-2b]
}

resource "aws_efs_file_system" "myefs" {
  encrypted = true
  tags = {
    Name = "MyEFS"
  }
  depends_on =  [aws_vpc.myvpc]
}

resource "aws_efs_mount_target" "eu-west-2a" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.eu-west-2a.id
}

resource "aws_efs_mount_target" "eu-west-2b" {
  file_system_id = aws_efs_file_system.myefs.id
  subnet_id      = aws_subnet.eu-west-2b.id
}
