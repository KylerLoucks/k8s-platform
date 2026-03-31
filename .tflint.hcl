plugin "aws" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  # Deep checks require AWS credentials
  deep_check = false # https://github.com/terraform-linters/tflint-ruleset-aws/blob/master/docs/rules/README.md
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}