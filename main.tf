# 1. Indicamos el proveedor de nube
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

# 2. Configuración de la región
provider "aws" {
  region = "us-east-1"
}

# 3. Nuestro primer recurso: Una VPC profesional
resource "aws_vpc" "mi_vpc_crack" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "VPC-Principal-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 4. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mi_vpc_crack.id

  tags = {
    Name        = "IGW-Principal-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 5. Subred Pública (us-east-1a)
resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.mi_vpc_crack.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "Subnet-Public-1a"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 6. Subred Privada (us-east-1a)
resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.mi_vpc_crack.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name        = "Subnet-Private-1a"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 7. Tabla de Ruteo Pública
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mi_vpc_crack.id

  # Ruta por defecto hacia Internet a través del IGW
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "RT-Publica-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 8. Asociación de la Tabla de Ruteo con la Subred Pública
resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_rt.id
}

# 9. Grupo de Seguridad para tráfico Web y SSH
resource "aws_security_group" "web_sg" {
  name        = "sg_web_dev"
  description = "Permitir trafico HTTP y SSH de entrada"
  vpc_id      = aws_vpc.mi_vpc_crack.id

  # Permitir trafico HTTP saliendo/entrando desde cualquier IP
  ingress {
    description = "HTTP desde cualquier lugar"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir acceso SSH (Puerto 22)
  ingress {
    description = "SSH para administracion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Nota: En produccion restringiremos esto a tu IP local
  }

  # Regla de salida: Permitir todo el trafico saliente hacia Internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "SG-Web-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# ==========================================
# FASE 2: PREPARACIÓN DE RED MULTI-AZ
# ==========================================

# 10. Subred Pública (us-east-1b)
resource "aws_subnet" "public_subnet_1b" {
  vpc_id                  = aws_vpc.mi_vpc_crack.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "Subnet-Public-1b"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 11. Subred Privada (us-east-1b)
resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.mi_vpc_crack.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name        = "Subnet-Private-1b"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 12. Asociación de Subred Pública 1b a la Tabla de Ruteo Pública
resource "aws_route_table_association" "public_subnet_1b_assoc" {
  subnet_id      = aws_subnet.public_subnet_1b.id
  route_table_id = aws_route_table.public_rt.id
}

# ==========================================
# LAUNCH TEMPLATE & DATA SOURCES
# ==========================================

# 13. Data Source para obtener la última AMI de Amazon Linux 2023
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-6.1-x86_64"]
  }
}

# 14. Plantilla de Lanzamiento para las instancias Web
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-template-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web_sg.id]
  }

  # Script de automatización de arranque
  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              
              # Obtener la Zona de Disponibilidad desde los metadatos de IMDSv2
              TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              EC2_AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
              
              echo "<div style='text-align:center; font-family:sans-serif; margin-top:50px;'>" > /var/www/html/index.html
              echo "<h1>🚀 ¡Despliegue exitoso con Terraform!</h1>" >> /var/www/html/index.html
              echo "<h3>Servidor corriendo en la Zona de Disponibilidad: <span style='color:green;'>$EC2_AZ</span></h3>" >> /var/www/html/index.html
              echo "</div>" >> /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "WebServer-Instance"
      Environment = "Lab"
      ManagedBy   = "Terraform"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================
# APPLICATION LOAD BALANCER & TARGET GROUP
# ==========================================

# 15. Target Group para verificar salud de los servidores web
resource "aws_lb_target_group" "web_tg" {
  name     = "tg-web-dev"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.mi_vpc_crack.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name        = "TG-Web-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 16. Application Load Balancer (ALB)
resource "aws_lb" "web_alb" {
  name               = "alb-web-dev"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]

  tags = {
    Name        = "ALB-Web-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 17. Listener HTTP (Puerto 80) que reenvia al Target Group
resource "aws_lb_listener" "web_listener_http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# 18. Output para ver el DNS del Load Balancer en la terminal
output "alb_dns_name" {
  description = "URL publica para acceder a la aplicacion a traves del ALB"
  value       = aws_lb.web_alb.dns_name
}

# ==========================================
# AUTO SCALING GROUP (ASG)
# ==========================================

# 19. Auto Scaling Group para alta disponibilidad
resource "aws_autoscaling_group" "web_asg" {
  name_prefix         = "asg-web-dev-"
  vpc_zone_identifier = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]
  target_group_arns   = [aws_lb_target_group.web_tg.arn]

  desired_capacity = 2
  min_size         = 1
  max_size         = 3

  # Usar Health Check del Load Balancer para detectar instancias caidas
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  # Forzar el reemplazo ordenado de instancias en actualizaciones
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "ASG-WebServer"
    propagate_at_launch = true
  }
}

# ==========================================
# FASE 3: SERVERLESS - DYNAMODB
# ==========================================

# 24. Tabla NoSQL DynamoDB en modo bajo demanda
resource "aws_dynamodb_table" "users_table" {
  name         = "TablaUsuariosDev"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"

  attribute {
    name = "UserId"
    type = "S" # Tipo String
  }

  tags = {
    Name        = "DynamoDB-Users-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Output para confirmar la creacion de la tabla DynamoDB
output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB creada"
  value       = aws_dynamodb_table.users_table.name
}

# ==========================================
# CÓMPUTO SERVERLESS - AWS LAMBDA
# ==========================================

# 25. Rol IAM para la funcion Lambda
resource "aws_iam_role" "lambda_role" {
  name = "role_lambda_dynamodb_dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 26. Politica IAM con permisos mínimos necesarios (DynamoDB + CloudWatch)
resource "aws_iam_role_policy" "lambda_policy" {
  name = "policy_lambda_dynamodb_dev"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.users_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 27. Generacion automatica del archivo .zip con el codigo Python
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-EOF
      import json
      import boto3
      import os

      dynamodb = boto3.resource('dynamodb')
      table_name = os.environ['TABLE_NAME']
      table = dynamodb.Table(table_name)

      def lambda_handler(event, context):
          # Encabezados CORS obligatorios para el navegador
          headers = {
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Headers': '*',
              'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
          }
          
          # Detectar el metodo HTTP (GET, POST, OPTIONS)
          http_method = event.get('requestContext', {}).get('http', {}).get('method', 'GET')
          
          # 1. Manejo de Preflight CORS (Peticiones OPTIONS del navegador)
          if http_method == 'OPTIONS':
              return {
                  'statusCode': 200,
                  'headers': headers,
                  'body': ''
              }
          
          # 2. Consultar usuarios (Peticiones GET)
          if http_method == 'GET':
              response = table.scan()
              items = response.get('Items', [])
              return {
                  'statusCode': 200,
                  'headers': headers,
                  'body': json.dumps(items)
              }
          
          # 3. Insertar usuario desde el formulario (Peticiones POST)
          if http_method == 'POST':
              body_str = event.get('body', '{}')
              payload = json.loads(body_str) if body_str else {}
              
              user_id = payload.get('id') or payload.get('UserId') or 'usr_default'
              nombre = payload.get('nombre') or payload.get('Nombre') or 'Usuario Anonimo'
              email = payload.get('email') or payload.get('Email') or 'sin-email@demo.com'
              
              item = {
                  'UserId': user_id,
                  'id': user_id,
                  'nombre': nombre,
                  'email': email,
                  'Nombre': nombre,
                  'Status': 'Serverless Active'
              }
              
              table.put_item(Item=item)
              
              return {
                  'statusCode': 200,
                  'headers': headers,
                  'body': json.dumps({'message': '¡Usuario registrado exitosamente!', 'item': item})
              }
          
          return {
              'statusCode': 200,
              'headers': headers,
              'body': json.dumps({'message': 'OK'})
          }
    EOF
    filename = "index.py"
  }
}

# 28. Recurso de la Funcion Lambda
resource "aws_lambda_function" "user_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "GestionUsuariosLambdaDev"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.users_table.name
    }
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Output para referencia
output "lambda_function_name" {
  description = "Nombre de la funcion Lambda"
  value       = aws_lambda_function.user_lambda.function_name
}

# ==========================================
# API GATEWAY (HTTP API)
# ==========================================

# 29. Crear HTTP API en API Gateway v2
resource "aws_apigatewayv2_api" "http_api" {
  name          = "api-usuarios-dev"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 30. Stage por defecto con auto-deploy habilitado
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# 31. Integracion entre API Gateway y Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"

  integration_method     = "POST"
  integration_uri        = aws_lambda_function.user_lambda.invoke_arn
  payload_format_version = "2.0"
}

# 32. Ruta HTTP: GET /users
resource "aws_apigatewayv2_route" "get_users_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /users"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# 33. Permiso explícito para que API Gateway pueda invocar la Lambda
resource "aws_lambda_permission" "api_gw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Output para probar la API
output "api_gateway_url" {
  description = "URL publica del API Gateway para invocar la Lambda"
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/users"
}

# ==========================================
# FRONTEND SERVERLESS (S3 + CLOUDFRONT)
# ==========================================

# 34. Bucket S3 para Frontend estatico
resource "aws_s3_bucket" "frontend_bucket" {
  bucket_prefix = "devops-crack-frontend-"
  force_destroy = true

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Bloqueo total de acceso público directo a S3
resource "aws_s3_bucket_public_access_block" "frontend_bucket_acl" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 35. Subida automática del archivo index.html de prueba a S3
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend_bucket.id
  key          = "index.html"
  content      = "<h1>🚀 Frontend Serverless desplegado con S3 + CloudFront usando Terraform!</h1>"
  content_type = "text/html"
}

# 36. CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "s3-frontend-oac-dev"
  description                       = "OAC para S3 Frontend Bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 37. Distribucion CDN con Amazon CloudFront
resource "aws_cloudfront_distribution" "frontend_cdn" {
  origin {
    domain_name              = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "S3Origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 38. Politica en S3 que autoriza unicamente las peticiones originadas desde CloudFront OAC
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn
          }
        }
      }
    ]
  })
}

# Output de la URL HTTPS global de CloudFront
output "cloudfront_domain_name" {
  description = "URL publica del Frontend alojado en CloudFront"
  value       = "https://${aws_cloudfront_distribution.frontend_cdn.domain_name}"
}

# ==========================================
# FASE 4: CONTENEDORES - ECR Y ECS CLUSTER
# ==========================================

# 39. Registro de Imagenes de Contenedores (Amazon ECR)
resource "aws_ecr_repository" "app_ecr" {
  name                 = "app-web-devops-dev"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Escaneo automatico de vulnerabilidades al subir imagen
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 40. Cluster de ECS (Fargate)
resource "aws_ecs_cluster" "main_cluster" {
  name = "cluster-fargate-dev"

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Output con la URL del repositorio ECR para el push de Docker
output "ecr_repository_url" {
  description = "URL publica del repositorio Amazon ECR"
  value       = aws_ecr_repository.app_ecr.repository_url
}

# ==========================================
# ECS FARGATE - TASK DEFINITION & SERVICE
# ==========================================

# 41. Rol de ejecucion IAM para ECS Fargate
resource "aws_iam_role" "ecs_execution_role" {
  name = "role_ecs_task_execution_dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Adjuntar la politica administrada por AWS para ejecucion de tareas ECS
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 42. Grupo de Seguridad para el Contenedor Fargate
resource "aws_security_group" "ecs_sg" {
  name        = "sg_ecs_fargate_dev"
  description = "Permitir trafico HTTP entrante al contenedor Fargate"
  vpc_id      = aws_vpc.mi_vpc_crack.id

  ingress {
    description = "HTTP desde cualquier origen"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "SG-ECS-Fargate-Dev"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 43. Definicion de Tarea (Task Definition)
resource "aws_ecs_task_definition" "app_task" {
  family                   = "task-app-web-dev"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 512 MB
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "app-container"
      image     = "public.ecr.aws/nginx/nginx:latest" # Placeholder inicial
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# 44. Servicio ECS Fargate
resource "aws_ecs_service" "app_service" {
  name            = "service-app-web-dev"
  cluster         = aws_ecs_cluster.main_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}