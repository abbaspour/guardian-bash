# Auth0 Guardian Push Configuration (AWS SNS)

resource "auth0_guardian" "guardian_config" {
  policy = "all-applications"

  push {
    enabled  = true
    provider = "sns"

    amazon_sns {
      aws_access_key_id                 = aws_iam_access_key.auth0_guardian_sns.id
      aws_secret_access_key             = aws_iam_access_key.auth0_guardian_sns.secret
      aws_region                        = var.aws_region
      sns_apns_platform_application_arn = "xxxxx"
      #sns_gcm_platform_application_arn  = aws_sns_topic.guardian_push.arn
      sns_gcm_platform_application_arn  = aws_sns_platform_application.gcm_application.arn
    }
  }
}


