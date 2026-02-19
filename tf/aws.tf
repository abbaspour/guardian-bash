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

