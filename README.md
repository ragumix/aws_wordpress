# AWS terraform file and ansible role for creating the following architecture:  
<img src="./Architecture.PNG" width="350" height="446">

**Note:** You have to precreate an SSH-key in your AWS account with name "Test_key" or change the name of key in the **key_name** parameter of 'resource "aws_launch_configuration" "my_conf"'.  
After the creation of all resources, you can manually delete EC2 instance with name **Delete_me**, because it needs only for creation of special AMI with preinstalled Apache and PHP.
