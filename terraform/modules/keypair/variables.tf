variable "key_name" {
  description = "Key Pair Name. Also used as the SSM Parameter Name"
  type        = string
}

variable "kms_key_id" {
  description = "KMS Key ID used to encrypt the SSM Parameter"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all module resources."
  default     = {}
  type        = map(any)
}
