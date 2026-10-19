output "api_invoke_url" {
  description = "URL base del API Gateway"
  value       = aws_api_gateway_stage.api_stage.invoke_url
}

output "sqs_queue_url" {
  description = "URL de la cola SQS"
  value       = aws_sqs_queue.telemetry_queue.id
}

output "grafana_url" {
  description = "URL de la interfaz de Grafana"
  value       = "http://${aws_instance.analytics_server.public_ip}:3000"
}

output "columnar_db_http" {
  description = "Endpoint HTTP de la Base de Datos Columnar (ClickHouse)"
  value       = "http://${aws_instance.analytics_server.public_ip}:8123"
}