provider "aws" {
  region = "ap-northeast-1"
}

# VPCとサブネットの作成
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "public1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "public2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-1c"
}

# セキュリティグループの作成
resource "aws_security_group" "allow_http" {
  name   = "allow_http"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_all" {
  name   = "allow_all"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_main_route_table_association" "axum_service_public_association" {
  vpc_id         = aws_vpc.main.id
  route_table_id = aws_route_table.public.id
}

# ECSクラスタの作成
resource "aws_ecs_cluster" "main" {
  name = "axum-cluster"
}

resource "aws_lb" "axum_lb" {
  name               = "axum-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]

  tags = {
    Name = "axum-lb"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.axum_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.axum_tg.arn
  }
}

resource "aws_lb_listener_rule" "test_path_rule" {
  listener_arn = aws_lb_listener.front_end.arn

  priority = 10  # 優先順位は他のルールと衝突しないように選ぶ

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "This is a test response"
      status_code  = "200"
    }
  }

  condition {
    path_pattern {
      values = ["/test"]
    }
  }
}

resource "aws_lb_listener" "front_end_green" {
  load_balancer_arn = aws_lb.axum_lb.arn
  port              = "81"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.axum_tg_green.arn
  }
}

resource "aws_lb_target_group" "axum_tg" {
  name        = "axum-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    port                = "80"
    protocol            = "HTTP"
    matcher             = "200"
    path                = "/"
    interval            = 30
  }
}

# Green Target Group
resource "aws_lb_target_group" "axum_tg_green" {
  name        = "axum-tg-green"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    port                = "80"
    protocol            = "HTTP"
    matcher             = "200"
    path                = "/"
    interval            = 30
  }
}


resource "aws_iam_role" "execution_role" {
  name = "axum_task_execution_role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution_role_policy_attachment" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECSタスク定義
resource "aws_ecs_task_definition" "axum_task" {
  family                   = "axum-task"
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution_role.arn
  container_definitions    = file("task-definitions/axum.json")
}

resource "aws_cloudwatch_log_group" "axum_log_group" {
  name = "/ecs/axum-service"
}

# ECSサービス
resource "aws_ecs_service" "axum_service" {
  name            = "axum-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.axum_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets = [aws_subnet.private.id]
    security_groups  = [aws_security_group.allow_all.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.axum_tg.arn
    container_name   = "axum-app"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

resource "aws_ecr_repository" "axum_app" {
  name = "axum-app"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.axum_app.repository_url
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.axum_lb.dns_name
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = aws_subnet.private.id
}

output "public_subnet1_id" {
  description = "The ID of the first public subnet"
  value       = aws_subnet.public1.id
}

output "public_subnet2_id" {
  description = "The ID of the second public subnet"
  value       = aws_subnet.public2.id
}

output "security_group_allow_http_id" {
  description = "The ID of the security group that allows HTTP traffic"
  value       = aws_security_group.allow_http.id
}

output "security_group_allow_all_id" {
  description = "The ID of the security group that allows all traffic"
  value       = aws_security_group.allow_all.id
}

# CodeDeployのためのrole

resource "aws_iam_role" "codedeploy_service_role" {
  name = "codedeploy-service-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
  role       = aws_iam_role.codedeploy_service_role.name
}


# CodeDeployアプリケーション
resource "aws_codedeploy_app" "axum_app" {
  name             = "axum-app"
  compute_platform = "ECS"
}

resource "aws_sns_topic" "axum_topic" {
  name = "axum-topic"
}

# CodeDeployデプロイメントグループ
resource "aws_codedeploy_deployment_group" "axum_group" {
  app_name               = aws_codedeploy_app.axum_app.name
  deployment_group_name  = "axum-group"
  service_role_arn       = aws_iam_role.codedeploy_service_role.arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.axum_service.name
  }

  trigger_configuration {
    trigger_events     = ["DeploymentFailure"]
    trigger_name       = "axum-trigger"
    trigger_target_arn = aws_sns_topic.axum_topic.arn
  }

  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = aws_lb_target_group.axum_tg.name
      }
      target_group {
        name = aws_lb_target_group.axum_tg_green.name
      }

      prod_traffic_route {
        listener_arns = [aws_lb_listener.front_end.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.front_end_green.arn]
      }
    }
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }
}