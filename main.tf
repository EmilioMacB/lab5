# 1. Empaquetar la Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/processor.py"
  output_path = "${path.module}/lambda/processor.zip"
}

# Red por defecto
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 2. Cola SQS (Streaming / Mensajeria)
resource "aws_sqs_queue" "telemetry_queue" {
  name                       = "${var.project_name}-queue"
  message_retention_seconds  = 86400 # 1 dia
  visibility_timeout_seconds = 90
}

# 3. Security Group para Grafana y Columnar DB
resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Permitir trafico a Grafana y Base de Datos Columnar"
  vpc_id      = data.aws_vpc.default.id

  # Grafana Web UI
  ingress {
    description = "Grafana Web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ClickHouse HTTP / Columnar DB
  ingress {
    description = "ClickHouse HTTP"
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Servidor Columnar DB + Grafana
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "analytics_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.small"
  vpc_security_group_ids      = [aws_security_group.lab_sg.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker
              systemctl enable --now docker

              # ClickHouse (Columnar DB)
              docker run -d --name columnar-db \
                -p 8123:8123 -p 9000:9000 \
                --ulimit nofile=262144:262144 \
                clickhouse/clickhouse-server:latest

              # Grafana
              docker run -d --name grafana \
                -p 3000:3000 \
                -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
                -e "GF_USERS_ALLOW_SIGN_UP=false" \
                grafana/grafana-oss:latest
              EOF

  tags = {
    Name = "${var.project_name}-columnar-grafana"
  }
}

# 5. Lambda Processor
resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-processor"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "processor.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15
}

# Event Source Mapping (SQS -> Lambda)
resource "aws_lambda_event_source_mapping" "sqs_lambda" {
  event_source_arn = aws_sqs_queue.telemetry_queue.arn
  function_name    = aws_lambda_function.stream_processor.arn
  batch_size       = 10
}

# 6. API Gateway con Cache
resource "aws_api_gateway_rest_api" "telemetry_api" {
  name        = "${var.project_name}-api"
  description = "API Gateway para streaming y consulta con cache"
}

# Recurso /telemetry (Ingesta POST hacia SQS)
resource "aws_api_gateway_resource" "telemetry_resource" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  parent_id   = aws_api_gateway_rest_api.telemetry_api.root_resource_id
  path_part   = "telemetry"
}

resource "aws_api_gateway_method" "post_telemetry" {
  rest_api_id   = aws_api_gateway_rest_api.telemetry_api.id
  resource_id   = aws_api_gateway_resource.telemetry_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integracion directa API Gateway -> SQS SendMessage
resource "aws_api_gateway_integration" "sqs_integration" {
  rest_api_id             = aws_api_gateway_rest_api.telemetry_api.id
  resource_id             = aws_api_gateway_resource.telemetry_resource.id
  http_method             = aws_api_gateway_method.post_telemetry.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.telemetry_queue.name}"
  credentials             = data.aws_iam_role.lab_role.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

resource "aws_api_gateway_method_response" "post_response_200" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  resource_id = aws_api_gateway_resource.telemetry_resource.id
  http_method = aws_api_gateway_method.post_telemetry.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "sqs_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  resource_id = aws_api_gateway_resource.telemetry_resource.id
  http_method = aws_api_gateway_method.post_telemetry.http_method
  status_code = aws_api_gateway_method_response.post_response_200.status_code

  response_templates = {
    "application/json" = "{\"status\": \"Record queued to SQS successfully\"}"
  }
  depends_on = [aws_api_gateway_integration.sqs_integration]
}

# Recurso /metrics (GET para probar rendimiento CON y SIN cache)
resource "aws_api_gateway_resource" "metrics_resource" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  parent_id   = aws_api_gateway_rest_api.telemetry_api.root_resource_id
  path_part   = "metrics"
}

resource "aws_api_gateway_method" "get_metrics" {
  rest_api_id   = aws_api_gateway_rest_api.telemetry_api.id
  resource_id   = aws_api_gateway_resource.metrics_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "mock_integration" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  resource_id = aws_api_gateway_resource.metrics_resource.id
  http_method = aws_api_gateway_method.get_metrics.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "get_metrics_200" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  resource_id = aws_api_gateway_resource.metrics_resource.id
  http_method = aws_api_gateway_method.get_metrics.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "mock_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  resource_id = aws_api_gateway_resource.metrics_resource.id
  http_method = aws_api_gateway_method.get_metrics.http_method
  status_code = aws_api_gateway_method_response.get_metrics_200.status_code

  response_templates = {
    "application/json" = <<EOF
{
  "status": "success",
  "data": {
    "total_records": 150000,
    "system_load": "optimal",
    "timestamp": "$context.requestTime"
  }
}
EOF
  }
  depends_on = [aws_api_gateway_integration.mock_integration]
}

# Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id

  depends_on = [
    aws_api_gateway_integration.sqs_integration,
    aws_api_gateway_integration.mock_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Stage con Cache habilitado (0.5 GB)
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id         = aws_api_gateway_deployment.api_deployment.id
  rest_api_id           = aws_api_gateway_rest_api.telemetry_api.id
  stage_name            = "prod"
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"
}

resource "aws_api_gateway_method_settings" "metrics_cache_settings" {
  rest_api_id = aws_api_gateway_rest_api.telemetry_api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  method_path = "metrics/GET"

  settings {
    caching_enabled      = true
    cache_ttl_in_seconds = 300
    metrics_enabled      = true
  }
}