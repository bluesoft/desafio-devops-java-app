########### Backend configs
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Usa credenciais diretamente da configuração do aws-cli do meu usuário
  shared_credentials_files = ["~/.aws/credentials"]
  profile                  = var.aws_profile
}

########### Variaveis
variable "aws_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "image_build_number" {
  type = string
}

variable "untagged_images" {
  type = number
}

variable "aws_public_key" {
  type = string
}

variable "domain_name" {
  type    = string
}

########### Coleta dados do ambiente
# ID da Conta
data "aws_caller_identity" "current" {}
# IAM Role para nodes do ECS
data "aws_iam_policy_document" "ecs_node_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
# IAM Role para Tasks do ECS
data "aws_iam_policy_document" "ecs_task_doc" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
# AMI recomendada para ECS
data "aws_ssm_parameter" "ecs_node_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id"
}

########### Cria o registry no ECR
resource "aws_ecr_repository" "desafio" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = {
    Name = var.project_name
  }
}

########### Cria politica de retenção de imagens
resource "aws_ecr_lifecycle_policy" "desafio" {
  repository = aws_ecr_repository.desafio.name

  policy = <<EOF
	{
	    "rules": [
	        {
	            "rulePriority": 1,
	            "description": "Manter apenas ultimas ${var.untagged_images} imagens não taggeadas",
	            "selection": {
	                "tagStatus": "untagged",
	                "countType": "imageCountMoreThan",
	                "countNumber": ${var.untagged_images}
	            },
	            "action": {
	                "type": "expire"
	            }
	        }
	    ]
	}
	EOF
}

########### Taggeia e faz push da imagem do projeto para o ECR
resource "null_resource" "docker_desafio" {
  provisioner "local-exec" {
    command = <<EOF
    ECR_URL="${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    aws ecr get-login-password --region ${var.aws_region} --profile ${var.aws_profile} | docker login --username AWS --password-stdin "$ECR_URL"
    docker image tag "${var.project_name}:${var.image_build_number}" "$ECR_URL/${var.project_name}:${var.image_build_number}"
    docker image tag "${var.project_name}:${var.image_build_number}" "$ECR_URL/${var.project_name}:latest"
    docker push "$ECR_URL/${var.project_name}:${var.image_build_number}"
    docker push "$ECR_URL/${var.project_name}:latest"
    EOF
  }

  triggers = {
    "run_at" = timestamp()
  }

  depends_on = [
    aws_ecr_repository.desafio,
  ]
}

########### Rede
resource "aws_vpc" "desafio" {
  cidr_block           = "192.168.0.0/20"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = var.project_name
  }
}

resource "aws_internet_gateway" "desafio" {
  vpc_id = aws_vpc.desafio.id
  tags = {
    Name = "desafio"
  }
}

# Subnets públicas
resource "aws_subnet" "pub_desafio_a" {
  vpc_id                  = aws_vpc.desafio.id
  availability_zone       = "${var.aws_region}a"
  cidr_block              = cidrsubnet(aws_vpc.desafio.cidr_block, 4, 3)
  map_public_ip_on_launch = true
  tags = {
    Name = "pub_desafio_a"
  }
}

resource "aws_subnet" "pub_desafio_b" {
  vpc_id                  = aws_vpc.desafio.id
  availability_zone       = "${var.aws_region}b"
  cidr_block              = cidrsubnet(aws_vpc.desafio.cidr_block, 4, 4)
  map_public_ip_on_launch = true
  tags = {
    Name = "pub_desafio_b"
  }
}

resource "aws_route_table" "pub_desafio" {
  vpc_id = aws_vpc.desafio.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.desafio.id
  }
  tags = {
    Name = "pub_devops"
  }
}

resource "aws_route_table_association" "pub_desafio_a" {
  subnet_id      = aws_subnet.pub_desafio_a.id
  route_table_id = aws_route_table.pub_desafio.id
}

resource "aws_route_table_association" "pub_desafio_b" {
  subnet_id      = aws_subnet.pub_desafio_b.id
  route_table_id = aws_route_table.pub_desafio.id
}


########### Grupos de Segurança
# SG para EC2
resource "aws_security_group" "ecs_node_desafio" {
  name   = "ecs_node_desafio"
  vpc_id = aws_vpc.desafio.id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs_node_desafio"
  }
}

# SG para ALB
resource "aws_security_group" "alb_desafio" {
  name   = "alb_desafio"
  vpc_id = aws_vpc.desafio.id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb_desafio"
  }
}

# SG para o service do ECS
resource "aws_security_group" "ecs_task_desafio" {
  name   = "ecs_task_desafio"
  vpc_id = aws_vpc.desafio.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.desafio.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########### Route53 e ACM
resource "aws_route53_zone" "desafio" {
  name = var.domain_name
}

resource "aws_route53_record" "desafio" {
  zone_id = aws_route53_zone.desafio.zone_id
  name    = "${var.project_name}.${var.domain_name}"
  type    = "NS"
  ttl     = 300
  records = [aws_alb.desafio.dns_name]
}

resource "aws_acm_certificate" "desafio" {
  domain_name               = var.domain_name
  validation_method         = "DNS"
  subject_alternative_names = ["*.${var.domain_name}"]
}

resource "aws_acm_certificate_validation" "validate_crt_desafio" {
  certificate_arn         = aws_acm_certificate.desafio.arn
  validation_record_fqdns = [aws_route53_record.record_crt_validation.fqdn]
}

resource "aws_route53_record" "record_crt_validation" {
  name    = tolist(aws_acm_certificate.desafio.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.desafio.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.desafio.id
  records = [tolist(aws_acm_certificate.desafio.domain_validation_options)[0].resource_record_value]
  ttl     = 300
}

########### IAM roles
# Nodes do ECS
resource "aws_iam_role" "ecs_node_role_desafio" {
  name               = "ecs_node_role_desafio"
  assume_role_policy = data.aws_iam_policy_document.ecs_node_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_node_role_policy_desafio" {
  role       = aws_iam_role.ecs_node_role_desafio.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_node_profile_desafio" {
  name = "ecs_node_profile_desafio"
  path = "/ecs/instance/"
  role = aws_iam_role.ecs_node_role_desafio.name
}

# Tasks do ECS
resource "aws_iam_role" "ecs_task_role_desafio" {
  name               = "ecs_task_role_desafio"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role" "ecs_exec_role_desafio" {
  name               = "ecs_exec_role_desafio"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy_desafio" {
  role       = aws_iam_role.ecs_exec_role_desafio.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

########### Grupos de logs Cloudwatch 
resource "aws_cloudwatch_log_group" "desafio" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}


########### Compute - EC2
resource "aws_key_pair" "desafio" {
  key_name   = "desafio"
  public_key = var.aws_public_key
}

resource "aws_launch_template" "desafio" {
  name_prefix = "template_desafio"
  image_id    = data.aws_ssm_parameter.ecs_node_ami.value
  # 4 vcpu, 16GB ram
  instance_type          = "t3.xlarge"
  key_name               = aws_key_pair.desafio.key_name
  vpc_security_group_ids = [aws_security_group.ecs_node_desafio.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_node_profile_desafio.arn
  }

  monitoring {
    enabled = true
  }

  tags = {
    Name = "desafio"
  }

  user_data = base64encode(<<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.desafio.name} >> /etc/ecs/ecs.config;
    EOF
  )
}

########### ASG - EC2 (ECS Nodes)
resource "aws_autoscaling_group" "desafio" {
  vpc_zone_identifier = [
    aws_subnet.pub_desafio_a.id,
    aws_subnet.pub_desafio_b.id
  ]

  min_size                  = 2
  max_size                  = 10
  health_check_grace_period = 0
  health_check_type         = "EC2"
  protect_from_scale_in     = true

  launch_template {
    id      = aws_launch_template.desafio.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
  }

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "ecs_desafio"
    propagate_at_launch = true
  }
}

########### ALBs e Target Groups
resource "aws_alb" "desafio" {
  name               = "desafio"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_desafio.id]
  subnets            = [aws_subnet.pub_desafio_a.id, aws_subnet.pub_desafio_b.id]

  tags = {
    Name = "desafio"
  }

  depends_on = [aws_internet_gateway.desafio]
}

resource "aws_alb_listener" "alb_listener_desafio" {
  load_balancer_arn = aws_alb.desafio.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.desafio.arn
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.tg_desafio.arn
  }

  depends_on = [aws_acm_certificate.desafio, aws_acm_certificate_validation.validate_crt_desafio]
}


resource "aws_alb_target_group" "tg_desafio" {
  name        = "desafio"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.desafio.id

  health_check {
    enabled             = true
    healthy_threshold   = "2"
    unhealthy_threshold = "3"
    interval            = "10"
    matcher             = 200
    path                = "/actuator/health"
    port                = "8080"
    protocol            = "HTTP"
    timeout             = "8"
  }

  depends_on = [aws_alb.desafio]
}

########### Capacity provider e auto scaling do ECS
resource "aws_ecs_capacity_provider" "desafio" {
  name = "desafio"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.desafio.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "desafio" {
  cluster_name       = aws_ecs_cluster.desafio.name
  capacity_providers = [aws_ecs_capacity_provider.desafio.name]
  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.desafio.name
    base              = 1
    weight            = 100
  }
}

resource "aws_appautoscaling_target" "desafio" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.desafio.name}/${aws_ecs_service.desafio.name}"
  min_capacity       = 2
  max_capacity       = 10
}

resource "aws_appautoscaling_policy" "memory_desafio" {
  name               = "memory_desafio"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.desafio.resource_id
  scalable_dimension = aws_appautoscaling_target.desafio.scalable_dimension
  service_namespace  = aws_appautoscaling_target.desafio.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

########### Cria o cluster ECS e as Tasks
resource "aws_ecs_cluster" "desafio" {
  name = "desafio"
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "desafio"
  }
  depends_on = [aws_internet_gateway.desafio]
}

resource "aws_ecs_task_definition" "desafio" {
  family             = var.project_name
  task_role_arn      = aws_iam_role.ecs_task_role_desafio.arn
  execution_role_arn = aws_iam_role.ecs_exec_role_desafio.arn
  network_mode       = "awsvpc"
  cpu                = 2048
  memory             = 8192


  container_definitions = jsonencode([{
    name      = "desafio"
    image     = "${aws_ecr_repository.desafio.repository_url}:${var.image_build_number}"
    essential = true
    portMappings = [
      {
        containerPort = 8080
        hostPort      = 8080
      }
    ]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-region"        = var.aws_region,
        "awslogs-group"         = aws_cloudwatch_log_group.desafio.name,
        "awslogs-stream-prefix" = "desafio"
      }
    }
  }])
}

resource "aws_ecs_service" "desafio" {
  name            = "desafio"
  cluster         = aws_ecs_cluster.desafio.id
  task_definition = aws_ecs_task_definition.desafio.arn
  desired_count   = 5

  network_configuration {
    subnets         = [aws_subnet.pub_desafio_a.id, aws_subnet.pub_desafio_b.id]
    security_groups = [aws_security_group.ecs_task_desafio.id]
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.tg_desafio.arn
    container_name   = "desafio"
    container_port   = 8080
  }

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.desafio.name
    base              = 1
    weight            = 100
  }

  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_alb.desafio]
}

########### Outputs
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ecr_repo_name" {
  value = aws_ecr_repository.desafio.name
}

output "ecr_repo_arn" {
  value = aws_ecr_repository.desafio.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.desafio.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.desafio.arn
}

output "ecr_image_version" {
  value = "${aws_ecr_repository.desafio.repository_url}:${var.image_build_number}"
}

output "ecr_image_latest" {
  value = "${aws_ecr_repository.desafio.repository_url}:latest"
}

output "alb_url" {
  value = aws_alb.desafio.dns_name
}

output "repo_url" {
  value = aws_ecr_repository.desafio.repository_url
}
