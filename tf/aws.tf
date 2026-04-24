# AWS SNS Topic for Guardian Push Notifications
resource "aws_sns_topic" "guardian_push" {
  name = "${var.guardian_app_name}-push-notifications"

  tags = {
    Name        = "${var.guardian_app_name}-guardian-push"
    Application = "Auth0 Guardian"
    ManagedBy   = "Terraform"
  }
}

# SQS Queue for receiving SNS messages (for testing/listening)
resource "aws_sqs_queue" "guardian_listener" {
  name                       = "${var.guardian_app_name}-guardian-listener"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 30

  tags = {
    Name        = "${var.guardian_app_name}-guardian-listener"
    Application = "Auth0 Guardian"
    ManagedBy   = "Terraform"
  }
}

# SQS Queue Policy to allow SNS to send messages
resource "aws_sqs_queue_policy" "guardian_listener_policy" {
  queue_url = aws_sqs_queue.guardian_listener.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "SQS:SendMessage"
        Resource = aws_sqs_queue.guardian_listener.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.guardian_push.arn
          }
        }
      }
    ]
  })
}

# SNS Subscription to SQS for listening to messages
resource "aws_sns_topic_subscription" "guardian_to_sqs" {
  topic_arn = aws_sns_topic.guardian_push.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.guardian_listener.arn
}

# IAM User for Auth0 Guardian SNS Access
resource "aws_iam_user" "auth0_guardian_sns" {
  name = "${var.guardian_app_name}-auth0-guardian-sns-user"
  path = "/auth0/"

  tags = {
    Name        = "${var.guardian_app_name}-auth0-guardian-sns"
    Application = "Auth0 Guardian"
    ManagedBy   = "Terraform"
  }
}

# IAM Access Key for the Guardian SNS User
resource "aws_iam_access_key" "auth0_guardian_sns" {
  user = aws_iam_user.auth0_guardian_sns.name
}

# Attach AmazonSNSFullAccess Managed Policy to User
resource "aws_iam_user_policy_attachment" "auth0_guardian_sns_full_access" {
  user       = aws_iam_user.auth0_guardian_sns.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

resource "aws_sns_platform_application" "gcm_application" {
  name                = "fcm_application"
  platform            = "GCM"
  platform_credential = file("${path.module}/../asn-guardian-push-notification-firebase-adminsdk-fbsvc-036281f391.json")
}

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
