resource "auth0_guardian" "guardian_config" {
  //policy = "all-applications"
  policy = "never"

  email         = false
  otp           = false
  recovery_code = false

  push {
    enabled  = true
    provider = "direct"
    //provider = "sns"
    custom_app {
      app_name = "ASN"
    }

    direct_fcm {
      server_key = "${path.module}/../asn-guardian-push-notification-firebase-adminsdk-fbsvc-d4d77e2aa0.json"
    }

    direct_apns {
      bundle_id = "com.auth0.guardian.PushListener"
      p12       = filebase64("${path.module}/../Certificate_3des.p12")
      sandbox   = true
    }


    /*
    amazon_sns {
      aws_access_key_id                 = aws_iam_access_key.auth0_guardian_sns.id
      aws_secret_access_key             = aws_iam_access_key.auth0_guardian_sns.secret
      aws_region                        = var.aws_region
      sns_apns_platform_application_arn = "xxxxx"
      #sns_gcm_platform_application_arn  = aws_sns_topic.guardian_push.arn
      sns_gcm_platform_application_arn  = aws_sns_platform_application.gcm_application.arn
    }
    */
  }
}

