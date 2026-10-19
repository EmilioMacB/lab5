# Laboratorio 5: Pipeline de Streaming y Caché en AWS

Proyecto de infraestructura como código (Terraform) para desplegar un flujo de telemetría desacoplado en AWS, con aceleración por caché en API Gateway, procesamiento serverless y monitoreo en Grafana.

## Arquitectura

1. **Ingesta:** API Gateway (`POST /telemetry`) con integración nativa hacia Amazon SQS.
2. **Buffer de Streaming:** Cola SQS que desacopla la carga entrante y absorbe picos de tráfico.
3. **Procesamiento:** Función AWS Lambda (`processor.py`) que consume eventos en lotes mediante Event Source Mapping.
4. **Caché y Optimización:** Stage `prod` en API Gateway con clúster de caché de 0.5 GB para el endpoint `GET /metrics`.
5. **Observabilidad:** Servidor EC2 con Grafana (puerto 3000) visualizando el flujo de mensajes en tiempo real.

## Despliegue

```bash
# 1. Configurar credenciales temporales de AWS Academy
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# 2. Inicializar y desplegar
terraform init
terraform apply -auto-approve

# 3. Medir rendimiento con y sin caché
bash test_cache.sh