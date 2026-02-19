resource "aws_sns_platform_application" "gcm_application" {
  name                = "fcm_application"
  platform            = "GCM"
  platform_credential = file("${path.module}/../asn-guardian-push-notification-firebase-adminsdk-fbsvc-036281f391.json")
}