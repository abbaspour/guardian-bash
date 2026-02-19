output "sns_topic_arn" {
  description = "ARN of the SNS topic for Guardian push notifications"
  value       = aws_sns_topic.guardian_push.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.guardian_push.name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for listening to Guardian push messages"
  value       = aws_sqs_queue.guardian_listener.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.guardian_listener.arn
}

output "iam_user_name" {
  description = "Name of the IAM user for Auth0 Guardian"
  value       = aws_iam_user.auth0_guardian_sns.name
}

output "iam_user_arn" {
  description = "ARN of the IAM user"
  value       = aws_iam_user.auth0_guardian_sns.arn
}

output "aws_access_key_id" {
  description = "AWS Access Key ID for Auth0 Guardian (use in Auth0 Dashboard)"
  value       = aws_iam_access_key.auth0_guardian_sns.id
}

output "aws_secret_access_key" {
  description = "AWS Secret Access Key for Auth0 Guardian (sensitive - store securely)"
  value       = aws_iam_access_key.auth0_guardian_sns.secret
  sensitive   = true
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

resource "local_file" "env_file" {
  filename = "${path.module}/../.env"
  content  = <<-EOT
    SQS_QUEUE_URL=${aws_sqs_queue.guardian_listener.url}
    AWS_REGION=${var.aws_region}
  EOT
}
