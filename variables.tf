variable "aws_region" {
  description = "Region de AWS para el despliegue"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para los nombres de los recursos"
  type        = string
  default     = "lab5-streaming"
}

variable "redshift_db_name" {
  description = "Nombre de la base de datos Redshift"
  type        = string
  default     = "dev"
}

variable "redshift_master_username" {
  description = "Usuario admin para Redshift"
  type        = string
  default     = "awsuser"
}

variable "redshift_master_password" {
  description = "Password admin para Redshift"
  type        = string
  sensitive   = true
  default     = "Lab5SecurePass2026!"
}