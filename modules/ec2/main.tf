# SECURITY GROUP
resource "aws_security_group" "sg_pub" {
  name        = "sg_pub"
  description = "Security Group public"
  vpc_id      = var.vpc_id

  egress {
    description = "All to All"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All from 10.0.0.0/16"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "TCP/22 from All"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TCP/80 from All"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_pub"
  }
}
resource "aws_security_group" "sg_priv" {
  name        = "sg_priv"
  description = "Security Group private"
  vpc_id      = var.vpc_id

  egress {
    description = "All to All"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All from 10.0.0.0/16"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "sg_priv"
  }
}

# EC2 LAUNCH TEMPLATE
data "template_file" "user_data" {
  template = file("./modules/ec2/userdata-notifier.sh")
  vars = {
    rds_endpoint = "${var.rds_endpoint}"
    rds_user     = "${var.rds_user}"
    rds_password = "${var.rds_password}"
    rds_name     = "${var.rds_name}"
  }
}

resource "aws_launch_template" "lt_app_notify" {
  name                   = "lt_app_notify"
  image_id               = var.ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sg_pub.id]
  key_name               = var.ssh_key
  user_data              = base64encode(data.template_file.user_data.rendered)


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "app_notify"
    }
  }
}

# AUTO SCALING GROUP
resource "aws_autoscaling_group" "asg_app_notify" {
  name                = "asg_app_notify"
  vpc_zone_identifier = ["${var.sn_pub_1a_id}", "${var.sn_pub_1c_id}"]
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  target_group_arns   = [aws_lb_target_group.tg_app_notify.arn]

  launch_template {
    id      = aws_launch_template.lt_app_notify.id
    version = "$Latest"
  }

}

# APPLICATION LOAD BALANCER
resource "aws_lb" "lb_app_notify" {
  name               = "lb-app-notify"
  load_balancer_type = "application"
  subnets            = [var.sn_pub_1a_id, var.sn_pub_1c_id]
  security_groups    = [aws_security_group.sg_pub.id]

  tags = {
    Name = "lb_app_notify"
  }
}

# APPLICATION LOAD BALANCER TARGET GROUP
resource "aws_lb_target_group" "tg_app_notify" {
  name     = "tg-app-notify"
  vpc_id   = var.vpc_id
  protocol = var.protocol
  port     = var.port

  tags = {
    Name = "tg_app_notify"
  }
}

# APPLICATION LOAD BALANCER LISTENER
resource "aws_lb_listener" "listener_app_notify" {
  load_balancer_arn = aws_lb.lb_app_notify.arn
  protocol          = var.protocol
  port              = var.port

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_app_notify.arn
  }
}

data "aws_caller_identity" "current" {}

resource "aws_vpc_endpoint_service" "example" {
  acceptance_required        = false
  allowed_principals         = [data.aws_caller_identity.current.arn]
  application_load_balancer_arns = [aws_lb.lb_app_notify.arn]
}

resource "aws_vpc_endpoint" "example" {
  service_name      = aws_vpc_endpoint_service.example.service_name
  subnet_ids        = [var.sn_pub_1a_id, var.sn_pub_1c_id]
  vpc_endpoint_type = aws_vpc_endpoint_service.example.service_type
  vpc_id            = var.vpc_id
}

locals {
  phone_numbers = ["+5511981928324"]
}

resource "aws_sns_topic" "topic" {
  name            = "my-topic"
  delivery_policy = jsonencode({
    "http" : {
      "defaultHealthyRetryPolicy" : {
        "minDelayTarget" : 20,
        "maxDelayTarget" : 20,
        "numRetries" : 3,
        "numMaxDelayRetries" : 0,
        "numNoDelayRetries" : 0,
        "numMinDelayRetries" : 0,
        "backoffFunction" : "linear"
      },
      "disableSubscriptionOverrides" : false,
      "defaultThrottlePolicy" : {
        "maxReceivesPerSecond" : 1
      }
    }
  })
}

resource "aws_sns_topic_subscription" "topic_sms_subscription" {
  count     = length(local.phone_numbers)
  topic_arn = aws_sns_topic.topic.arn
  protocol  = "sms"
  endpoint  = local.phone_numbers[count.index]
}
