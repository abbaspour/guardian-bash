variable "aws_region" {
  default = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS profile"
  default = ""
}

variable "auth0_domain" {
  type        = string
  description = "Auth0 domain"
}

variable "auth0_tf_client_id" {
  type        = string
  description = "Terraform M2M client_id"
}

variable "auth0_tf_client_secret" {
  sensitive   = true
  type        = string
  description = "Terraform M2M client_secret"
}

variable "guardian_app_name" {
  default = "guardian-bash"
}

variable "sns_apns_platform_application_arn" {
  type        = string
  description = "SNS APNS Platform Application ARN for Apple Push Notifications"
  default     = ""
}

variable "sns_gcm_platform_application_arn" {
  type        = string
  description = "SNS GCM/FCM Platform Application ARN for Firebase Cloud Messaging"
  default     = ""
}
